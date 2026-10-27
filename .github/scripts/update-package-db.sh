#!/usr/bin/env bash
set -euo pipefail

package_arch=${1:?usage: update-package-db.sh <x86_64|aarch64>}
case "$package_arch" in
  x86_64)
    database_name=andy
    ;;
  aarch64)
    database_name=andy-aarch64
    ;;
  *)
    printf 'Unsupported package architecture: %s\n' "$package_arch" >&2
    exit 2
    ;;
esac

shopt -s nullglob
package_files=(packages/*-"$package_arch".pkg.tar.* packages/*-any.pkg.tar.*)
if ((${#package_files[@]} == 0)); then
  printf 'No %s package archives found under packages/\n' "$package_arch" >&2
  exit 1
fi

declare -A latest_versions=()
declare -A latest_packages=()

for package_file in "${package_files[@]}"; do
  package_info=$(bsdtar -xOf "$package_file" .PKGINFO)
  package_name=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"$package_info")
  package_version=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"$package_info")
  archive_arch=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<<"$package_info")

  if [[ -z "$package_name" || -z "$package_version" || ( "$archive_arch" != "$package_arch" && "$archive_arch" != any ) ]]; then
    printf 'Invalid package metadata in %s\n' "$package_file" >&2
    exit 1
  fi

  current_version=${latest_versions[$package_name]-}
  if [[ -z "$current_version" ]] || (( $(vercmp "$package_version" "$current_version") >= 0 )); then
    latest_versions[$package_name]=$package_version
    latest_packages[$package_name]=$package_file
  fi
done

mapfile -t package_names < <(printf '%s\n' "${!latest_packages[@]}" | sort)
selected_packages=()
for package_name in "${package_names[@]}"; do
  selected_packages+=("${latest_packages[$package_name]}")
done

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
cp "packages/$database_name.db.tar.zst" "$build_dir/$database_name.db.tar.zst.old"
cp "packages/$database_name.files.tar.zst" "$build_dir/$database_name.files.tar.zst.old"
repo-add "$build_dir/$database_name.db.tar.zst" "${selected_packages[@]}"

cp "$build_dir/$database_name.db.tar.zst" "packages/$database_name.db.tar.zst"
cp "$build_dir/$database_name.files.tar.zst" "packages/$database_name.files.tar.zst"
cp "$build_dir/$database_name.db.tar.zst.old" "packages/$database_name.db.tar.zst.old"
cp "$build_dir/$database_name.files.tar.zst.old" "packages/$database_name.files.tar.zst.old"

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  "packages/$database_name.db.tar.zst" \
  "packages/$database_name.db.tar.zst.old" \
  "packages/$database_name.files.tar.zst" \
  "packages/$database_name.files.tar.zst.old"

if git diff --cached --quiet; then
  printf 'The %s package database is already current.\n' "$package_arch"
  exit 0
fi

git commit -m "Update $package_arch package database"

pushed=false
for attempt in 1 2 3 4 5; do
  git fetch origin main
  git rebase origin/main
  if git push origin HEAD:main; then
    pushed=true
    break
  fi
  sleep "$((attempt * 2))"
done

if [[ "$pushed" != true ]]; then
  printf 'Could not push the %s package database update.\n' "$package_arch" >&2
  exit 1
fi

curl --fail-with-body --silent --show-error \
  -X POST \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/workflows/jekyll-gh-pages.yml/dispatches" \
  -d '{"ref":"main"}'
