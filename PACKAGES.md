# Packages

This repository currently offers the following packages for both `x86_64`
(`[andy]`) and `aarch64` (`[andy-aarch64]`).

| Package | Version | Description | Runtime dependencies | Upstream |
| --- | --- | --- | --- | --- |
| `desktools` | `0.1.0-1` | Create and edit `.desktop` launchers | `gcc-libs` | — |
| `elfinstaller` | `0.1.0-1` | A simple terminal application to install and manage ELF packages | — | https://github.com/andy64lol/elfinstaller |
| `lynxer` | `0.1.8.4-1` | A small, statically-flavoured C-style programming language with a standalone native runtime | `libffi`, `alsa-lib`, `bzip2` | https://github.com/andy64lol/Lynxer |
| `tandem` | `0.1.1-1` | A language, compiler, package workflow, and embedded runtime for Lua programs | `gcc-libs`, `openssl`, `zlib` | https://github.com/andy64lol/Tandem |

## Package archives

### x86_64

- `desktools-0.1.0-1-x86_64.pkg.tar.zst`
- `elfinstaller-0.1.0-1-x86_64.pkg.tar.zst`
- `lynxer-0.1.8.4-1-x86_64.pkg.tar.zst`
- `tandem-0.1.1-1-x86_64.pkg.tar.zst`

### aarch64

- `desktools-0.1.0-1-aarch64.pkg.tar.xz`
- `elfinstaller-0.1.0-1-aarch64.pkg.tar.xz`
- `lynxer-0.1.8.4-1-aarch64.pkg.tar.xz`
- `tandem-0.1.1-1-aarch64.pkg.tar.xz`

## Install

Add the section matching your architecture to `/etc/pacman.conf`:

```ini
# x86_64
[andy]
SigLevel = Optional
Server = https://andy64lol.github.io/andy-repo/
```

```ini
# aarch64
[andy-aarch64]
SigLevel = Optional
Server = https://andy64lol.github.io/andy-repo/
```

Then refresh the package databases and install a package:

```sh
sudo pacman -Syu
sudo pacman -S <package>
```
