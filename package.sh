#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO=bambulab/BambuStudio
PACKAGE=bambu-studio
TAG="${1:?upstream tag is required}"
UPSTREAM_VERSION="${2:?upstream version is required}"
VERSION="${3:?Debian package version is required}"
ARCH="${4:?Debian architecture is required}"

if [[ "$ARCH" != amd64 || "$(dpkg --print-architecture)" != amd64 ]]; then
  echo "The official Linux AppImage requires an amd64 build host and target." >&2
  exit 2
fi
[[ "$TAG" =~ ^v[0-9]+(\.[0-9]+){3}$ ]]
[[ "$UPSTREAM_VERSION" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
dpkg --validate-version "$VERSION"

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PKGROOT="$WORK/pkg"
APPROOT="$PKGROOT/usr/lib/$PACKAGE"
DOCROOT="$PKGROOT/usr/share/doc/$PACKAGE"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/usr/bin" "$APPROOT" "$DOCROOT" "$ROOT/dist"

release_json="$(gh api "repos/$UPSTREAM_REPO/releases/tags/$TAG")"
asset="$(jq -er '
  [.assets[] | select(.name | test("^BambuStudio_ubu22[-_].*\\.AppImage$"))]
  | if length == 1 then .[0].name else error("Expected exactly one Ubuntu 22.04 AppImage") end
' <<<"$release_json")"
expected="$(jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .digest // empty' <<<"$release_json")"
[[ "$asset" != */* && "$expected" =~ ^sha256:[0-9a-f]{64}$ ]]
if [[ -n "${BAMBU_APPIMAGE_CACHE:-}" && -f "$BAMBU_APPIMAGE_CACHE/$asset" ]]; then
  cp -- "$BAMBU_APPIMAGE_CACHE/$asset" "$WORK/$asset"
else
  gh release download "$TAG" --repo "$UPSTREAM_REPO" --pattern "$asset" --dir "$WORK"
fi
printf '%s  %s\n' "${expected#sha256:}" "$WORK/$asset" | sha256sum --check --strict
chmod 0755 "$WORK/$asset"
(cd "$WORK"; "./$asset" --appimage-extract >/dev/null)
EXTRACT="$WORK/squashfs-root"
test -x "$EXTRACT/AppRun"
test -x "$EXTRACT/bin/bambu-studio"
test -d "$EXTRACT/resources"
test -d "$EXTRACT/usr/share/icons"
test -s "$EXTRACT/BambuStudio.desktop"

# Preserve upstream layout: AppRun resolves bin/ and resources/ relative to itself.
cp -a "$EXTRACT/." "$APPROOT/"
find "$APPROOT" -type d -exec chmod 0755 {} +
find "$APPROOT" -type f -exec chmod a+r {} +
ln -s "../lib/$PACKAGE/AppRun" "$PKGROOT/usr/bin/$PACKAGE"

install -Dm0644 "$EXTRACT/BambuStudio.desktop" "$PKGROOT/usr/share/applications/BambuStudio.desktop"
sed -i -e 's|^Exec=AppRun |Exec=/usr/bin/bambu-studio |' \
  -e '/^X-AppImage-Version=/d' \
  -e '/^Keywords=/s/;*$/;/' "$PKGROOT/usr/share/applications/BambuStudio.desktop"
grep -Fx 'Exec=/usr/bin/bambu-studio %U' "$PKGROOT/usr/share/applications/BambuStudio.desktop"
cp -a "$EXTRACT/usr/share/icons" "$PKGROOT/usr/share/"
find "$PKGROOT/usr/share/icons" -type d -exec chmod 0755 {} +
find "$PKGROOT/usr/share/icons" -type f -exec chmod 0644 {} +
# Avoid duplicating the installed desktop integration in the private app tree.
rm -rf "$APPROOT/usr/share/icons" "$APPROOT/BambuStudio.desktop"

gh api "repos/$UPSTREAM_REPO/contents/LICENSE?ref=$TAG" --jq .content | tr -d '\n' | base64 --decode > "$DOCROOT/LICENSE"
test -s "$DOCROOT/LICENSE"
cat > "$DOCROOT/copyright" <<COPYRIGHT
Bambu Studio is distributed under the GNU Affero General Public License,
version 3. See /usr/share/doc/$PACKAGE/LICENSE.

Upstream release: https://github.com/$UPSTREAM_REPO/releases/tag/$TAG
Corresponding upstream source and build scripts:
 https://github.com/$UPSTREAM_REPO/tree/$TAG
 https://github.com/$UPSTREAM_REPO/archive/refs/tags/$TAG.tar.gz

The upstream binary and its bundled resources are redistributed unmodified;
the Coplo packaging scripts and desktop integration are available at
 https://github.com/gymZJ/bambu-studio-deb
Bundled third-party components retain their respective upstream licenses.
COPYRIGHT
chmod 0644 "$DOCROOT/"*

installed_size="$(du -sk "$PKGROOT/usr" | awk '{print $1}')"
awk -v version="$VERSION" -v arch="$ARCH" -v installed_size="$installed_size" '
  /^Description:/ {
    print "Version: " version
    print "Architecture: " arch
    print "Installed-Size: " installed_size
  }
  { print }
' "$ROOT/debian/control" > "$PKGROOT/DEBIAN/control"
chmod 0644 "$PKGROOT/DEBIAN/control"
find "$PKGROOT" -type d -exec chmod 0755 {} +

output="$ROOT/dist/${PACKAGE}_${VERSION}_${ARCH}.deb"
dpkg-deb -Zxz -z1 --threads-max=4 --build --root-owner-group "$PKGROOT" "$output"
dpkg-deb --info "$output"
echo "Built $output from Bambu Studio $UPSTREAM_VERSION ($TAG)"
