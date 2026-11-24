# Bambu Studio Debian Package

Debian package for Bambu Studio.

- Upstream: <https://github.com/bambulab/BambuStudio>
- Coplo APT repository: <https://deb.coplo.xyz/>
- Architecture: amd64
- License: AGPL-3.0 (bundled components retain their respective licenses)

## Install

```bash
sudo apt install bambu-studio
```

The package extracts the official Ubuntu 22.04 AppImage (the lowest upstream
glibc baseline), verifies the GitHub Release SHA-256 digest, and installs the
application, bundled libraries and resources, desktop launcher, and icons.
No FUSE or AppImage runtime is needed. The upstream license and exact tagged
source URL are installed in `/usr/share/doc/bambu-studio/`.

The workflow tracks stable upstream releases every six hours and increments
the Debian revision when packaging changes. No arm64 package is published
because upstream does not currently supply an arm64 Linux AppImage.

## Build locally

Requires an amd64 Debian/Ubuntu host with Bash, gh, jq, coreutils, and dpkg.

```bash
./package.sh v02.09.01.70 2.9.1.70 2.9.1.70-1 amd64
```

An optional `BAMBU_APPIMAGE_CACHE` directory can supply an already downloaded
upstream asset; its digest is always checked.
