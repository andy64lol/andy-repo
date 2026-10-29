# andy-repo

Arch Linux package repository for Lynxer, Desktools, Elfinstaller, and Tandem.
The pacman databases and package archives live in `packages/`; GitHub Pages
publishes that directory at the repository URL.

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

The current versions on both architectures are Lynxer `0.1.8.4-1`,
Desktools `0.1.0-1`, Elfinstaller `0.1.0-1`, and Tandem `0.1.1-1`. Refresh the
package databases after adding the repository with `sudo pacman -Syu`. See
[PACKAGES.md](PACKAGES.md) for the full package list.
