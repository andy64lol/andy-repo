#!/usr/bin/env bash
# Prepare and push a new package release for andy-repo.
#
# Takes upstream Arch package archives (or zips wrapping them, nested any number
# of times), relabels them to the next pkgrel of the version this repo
# publishes, drops them into packages/, updates the docs, and pushes.
#
# The pacman databases are deliberately NOT touched here: the
# update-x86_64-db.yml / update-aarch64-db.yml workflows rebuild them with
# repo-add inside an archlinux container and then dispatch the Pages deploy.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: scripts/publish.sh [--dry-run] <archive|zip> [<archive|zip> ...]

  --dry-run  print every planned action without writing, committing or pushing

Examples:
  scripts/publish.sh tmp/lynxer-arch-x86_64.zip tmp/lynxer-arch-aarch64.zip
  scripts/publish.sh --dry-run tmp/'lynxer-arch-0.1.9b1h(0.1.9b1-4)-lynxer-arch-x86_64(2).zip'
USAGE
}

dry_run=false
inputs=()
while (($#)); do
  case $1 in
    --dry-run) dry_run=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *) inputs+=("$1") ;;
  esac
  shift
done

if ((${#inputs[@]} == 0)); then
  usage >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

for tool in bsdtar fakeroot unzip zstd xz git vercmp; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$tool" >&2
    exit 1
  }
done

dirty=$(git status --porcelain | grep -v '^?? tmp/' || true)
if [[ -n $dirty ]]; then
  printf 'The work tree is not clean:\n%s\n' "$dirty" >&2
  exit 1
fi

branch=$(git symbolic-ref --short HEAD)
git fetch origin "$branch"
if [[ $(git rev-parse HEAD) != $(git rev-parse "origin/$branch") ]]; then
  printf 'Local %s is not in sync with origin/%s; pull or rebase first.\n' \
    "$branch" "$branch" >&2
  exit 1
fi

mkdir -p "$repo_root/tmp"
work_dir=$(mktemp -d "$repo_root/tmp/publish.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

# Unwraps zips (possibly nested) until a package archive is left.
unwrap_archive() {
  local source=$1 slot=$2 candidate depth=0
  mkdir -p "$slot"
  cp -- "$source" "$slot/"
  candidate="$slot/$(basename -- "$source")"

  while [[ $candidate == *.zip ]]; do
    ((depth++))
    if ((depth > 5)); then
      printf 'Too many nested zip levels in %s\n' "$source" >&2
      return 1
    fi
    local extract_dir="$slot/level$depth"
    mkdir -p "$extract_dir"
    unzip -q -o -- "$candidate" -d "$extract_dir"

    local entries=()
    mapfile -t entries < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -print)
    if ((${#entries[@]} != 1)); then
      printf 'Expected one entry inside %s, found %d\n' \
        "$candidate" "${#entries[@]}" >&2
      return 1
    fi
    candidate=${entries[0]}
  done

  [[ $candidate == *.pkg.tar.* ]] || {
    printf 'No package archive inside %s (got %s)\n' "$source" "$candidate" >&2
    return 1
  }
  printf '%s\n' "$candidate"
}

# Prints the version of $2 currently published in the database of $1.
published_version() {
  local database=$1 package_name=$2
  local db_file="packages/$database.db.tar.zst"
  [[ -f $db_file ]] || return 0

  local entry
  entry=$(bsdtar -tf "$db_file" | grep -E "^${package_name}-[^/]+/desc$" | head -n 1 || true)
  [[ -n $entry ]] || return 0

  bsdtar -xOf "$db_file" "$entry" |
    awk '/^%VERSION%$/ { getline; print; exit }'
}

declare -a archives=()
declare -a package_names=()
declare -a upstream_versions=()

index=0
for input in "${inputs[@]}"; do
  [[ -f $input ]] || {
    printf 'No such file: %s\n' "$input" >&2
    exit 1
  }

  archive=$(unwrap_archive "$input" "$work_dir/input$index")
  ((index++)) || true

  package_info=$(bsdtar -xOf "$archive" .PKGINFO)
  package_name=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"$package_info")
  upstream_pkgver=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"$package_info")
  package_arch=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<<"$package_info")

  [[ -n $package_name && -n $upstream_pkgver && -n $package_arch ]] || {
    printf 'Invalid package metadata in %s\n' "$input" >&2
    exit 1
  }
  case $package_arch in
    x86_64 | aarch64) ;;
    *)
      printf 'Unsupported package architecture: %s\n' "$package_arch" >&2
      exit 1
      ;;
  esac

  archives+=("$archive")
  package_names+=("$package_name")
  upstream_versions+=("$upstream_pkgver")
done

package_name=${package_names[0]}
if printf '%s\n' "${package_names[@]}" | sort -u | grep -qvxF -- "$package_name"; then
  printf 'All inputs must be the same package; got: %s\n' \
    "$(printf '%s\n' "${package_names[@]}" | sort -u | paste -sd ' ')" >&2
  exit 1
fi

# Upstream labels hotfixes with a trailing "h" (0.1.9b1h-1); this repo publishes
# them as the next pkgrel of the plain version (0.1.9b1-4).
base_version=${upstream_versions[0]%-*}
base_version=${base_version%h}
if printf '%s\n' "${upstream_versions[@]}" |
  sort -u | grep -qvxF -- "${upstream_versions[0]}"; then
  printf 'Inputs disagree on the upstream version: %s\n' \
    "$(printf '%s\n' "${upstream_versions[@]}" | sort -u | paste -sd ' ')" >&2
  exit 1
fi

published_x86_64=$(published_version andy "$package_name")
published_aarch64=$(published_version andy-aarch64 "$package_name")
if [[ -n $published_x86_64 && -n $published_aarch64 &&
  $published_x86_64 != "$published_aarch64" ]]; then
  printf 'The two architecture databases disagree on %s: %s vs %s\n' \
    "$package_name" "$published_x86_64" "$published_aarch64" >&2
  exit 1
fi
current_version=${published_x86_64:-$published_aarch64}

if [[ -z $current_version ]]; then
  new_version="$base_version-1"
else
  current_base=${current_version%-*}
  current_rel=${current_version##*-}
  if [[ $base_version == "$current_base" ]]; then
    new_version="$base_version-$((current_rel + 1))"
  else
    if (( $(vercmp "$base_version" "$current_base") < 0 )); then
      printf 'WARNING: %s is older than the published %s\n' \
        "$base_version" "$current_version" >&2
    fi
    new_version="$base_version-1"
  fi
fi

printf 'Package      : %s\n' "$package_name"
printf 'Published    : %s\n' "${current_version:-<not published yet>}"
printf 'New version  : %s\n' "$new_version"
printf 'Architectures: %s\n' \
  "$(printf '%s\n' "${archives[@]}" |
    sed -E 's#.*-(x86_64|aarch64)\.pkg\.tar\..*#\1#' | sort -u | paste -sd ' ')"

declare -a targets=()
index=0
for archive in "${archives[@]}"; do
  package_arch=$(bsdtar -xOf "$archive" .PKGINFO |
    awk -F ' = ' '$1 == "arch" { print $2; exit }')

  case $archive in
    *.pkg.tar.zst)
      compression=--zstd
      extension=zst
      ;;
    *.pkg.tar.xz)
      compression=--xz
      extension=xz
      ;;
    *)
      printf 'Unsupported archive compression: %s\n' "$archive" >&2
      exit 1
      ;;
  esac

  target="packages/${package_name}-${new_version}-${package_arch}.pkg.tar.${extension}"
  if [[ -e $target ]]; then
    printf '%s already exists\n' "$target" >&2
    exit 1
  fi
  targets+=("$target")

  if [[ $dry_run == true ]]; then
    printf '[dry-run] would repack %s -> %s (from %s)\n' \
      "$(basename -- "$archive")" "$target" "$archive"
    ((index++)) || true
    continue
  fi

  fakeroot -- bash -c '
    set -euo pipefail
    archive=$1
    target=$2
    new_version=$3
    compression=$4
    work=$5

    rm -rf "$work"
    mkdir -p "$work"
    bsdtar -xpf "$archive" -C "$work"
    sed -i "s|^pkgver = .*$|pkgver = $new_version|" "$work/.PKGINFO"

    rm -f "$work/.MTREE"
    cd "$work"
    mapfile -t payload < <(find . -mindepth 1 -maxdepth 1 -printf "%P\n" |
      grep -v -x -e .BUILDINFO -e .PKGINFO -e .MTREE | sort)

    bsdtar -cf - --format=mtree \
      --options="!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link" \
      .BUILDINFO .PKGINFO "${payload[@]}" | gzip -n -9 -c > .MTREE

    bsdtar "$compression" -cf "$target" .BUILDINFO .MTREE .PKGINFO "${payload[@]}"
  ' _ "$archive" "$repo_root/$target" "$new_version" "$compression" "$work_dir/repack$index"

  ((index++)) || true
  printf 'Wrote %s\n' "$target"
done

if [[ -n $current_version ]]; then
  escaped_version=${current_version//./\\.}
  changed=0
  for doc in README.md PACKAGES.md; do
    [[ -f $doc ]] || continue
    updated=$(mktemp)
    sed "s/$escaped_version/$new_version/g" "$doc" >"$updated"
    if cmp -s "$doc" "$updated"; then
      rm -f "$updated"
      continue
    fi
    ((changed++)) || true
    if [[ $dry_run == true ]]; then
      printf '[dry-run] would rewrite %s: %s -> %s\n' \
        "$doc" "$current_version" "$new_version"
      rm -f "$updated"
    else
      cat "$updated" >"$doc"
      rm -f "$updated"
      printf 'Updated %s\n' "$doc"
    fi
  done
  if ((changed == 0)); then
    printf 'Neither README.md nor PACKAGES.md mentions %s\n' "$current_version" >&2
    exit 1
  fi
fi

if [[ $dry_run == true ]]; then
  printf '[dry-run] would commit "%s" and push to origin/%s\n' \
    "Update $package_name to $new_version" "$branch"
  printf '[dry-run] no changes were written (except under tmp/).\n'
  exit 0
fi

git add "${targets[@]}"
if [[ -n $current_version ]]; then
  git add README.md PACKAGES.md
fi

git commit -q -m "Update $package_name to $new_version" -m \
  "Repacked from the upstream build and refreshed the documented version. The package databases are rebuilt by CI."

pushed=false
for attempt in 1 2 3; do
  git fetch origin "$branch"
  git rebase "origin/$branch"
  if git push origin "HEAD:$branch"; then
    pushed=true
    break
  fi
  sleep "$((attempt * 2))"
done

if [[ $pushed != true ]]; then
  printf 'Could not push to origin/%s\n' "$branch" >&2
  exit 1
fi

printf '\nPushed %s. CI now rebuilds both pacman databases and deploys Pages;\n' \
  "$new_version"
printf 'once that finishes, run "sudo pacman -Sy" to see it (pacman -S alone\n'
printf 'keeps using the cached database).\n'
