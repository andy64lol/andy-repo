# andy-repo

Arch Linux package repository for Lynxer. Package archives are versioned and
older builds are retained in this directory.

The repository publishes a separate pacman database for each architecture.
Add the matching section to `/etc/pacman.conf`:

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

The current package version is `0.1.8.3-2` on both architectures. Refresh the
package databases after adding the repository with `sudo pacman -Syu`.
