# andy-repo

Arch Linux package repository for Lynxer, Desktools, Elfinstaller, Tandem, and Cyz.
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

The current versions on both architectures are Lynxer `0.1.9b2-5`,
Desktools `0.1.0-1`, Elfinstaller `0.1.0-1`, Tandem `0.2.1-1`, and Cyz
`0.0.2-1`. The detached `cyz-debug` symbols are available for `x86_64` only.
Refresh the package databases after adding the repository with `sudo pacman
-Syu`. See [PACKAGES.md](PACKAGES.md) for the full package list.
