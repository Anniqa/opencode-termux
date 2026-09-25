#!/usr/bin/env bash
# Create distribution packages for OpenCode 2 (opencode2) for Android
#
# Usage: ./scripts/make-packages-v2.sh
#
# Creates three package formats:
# 1. ZIP: opencode2-${OPENCODE_VERSION}-android-aarch64.zip (standalone binary)
# 2. Pacman: opencode2-${OPENCODE_VERSION}-1-aarch64.pkg.tar.xz (Termux pacman format)
# 3. Deb: opencode2_${OPENCODE_VERSION}_aarch64.deb (Termux deb format)
#
# Layouts (the wrapper supports both):
#   zip:      opencode2, opencode2.bin, libopentui.so in one directory
#   packages: $PREFIX/bin/opencode2, $PREFIX/libexec/opencode2/opencode2.bin,
#             $PREFIX/lib/libopentui.so

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env-v2.sh"

BIN="$DIST_DIR/opencode2.bin"
LIB="$OPENTUI_LIB"
OUT="$PACKAGE_DIR"
rm -rf "$OUT"
mkdir -p "$OUT" "$DIST_DIR/flat"
test -x "$BIN"
test -f "$LIB"

echo "=== Creating packages for opencode2 v${OPENCODE_VERSION} ==="

# ==========================================
# Wrapper (identical file ships in zip, pacman, deb)
# ==========================================
cat > "$DIST_DIR/flat/opencode2" <<'WEOF'
#!/data/data/com.termux/files/usr/bin/sh
# opencode2 - wrapper for the OpenCode 2 CLI on Android/Termux
#
# Path resolution order (supports both layouts):
#   flat zip:    opencode2, opencode2.bin, libopentui.so in the same directory
#   installed:   bin/opencode2, libexec/opencode2/opencode2.bin, lib/libopentui.so
set -eu

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
DIR="$(CDPATH= cd -- "$(dirname "$SELF")" && pwd)"

# Termux markers, in case we are launched outside a Termux shell
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="${PREFIX}/bin:${PREFIX}/bin/applets:${PATH:-/data/data/com.termux/files/usr/bin:/bin:/usr/bin}"

TAGFIX="$PREFIX/lib/libtagfix.so"
if [ -f "$TAGFIX" ]; then
    export LD_PRELOAD="${TAGFIX}${LD_PRELOAD:+:$LD_PRELOAD}"
fi

# Locate the native library directory.
NATIVE_LIB_DIR=""
for candidate in "$DIR/../libexec/opencode2" "$PREFIX/libexec/opencode2" "$DIR/../lib" "$PREFIX/lib" "$DIR"; do
    if [ -f "$candidate/libopentui.so" ]; then
        NATIVE_LIB_DIR="$candidate"
        break
    fi
done
if [ -n "$NATIVE_LIB_DIR" ]; then
    export OPENTUI_LIB_PATH="$NATIVE_LIB_DIR/libopentui.so"
    export LD_LIBRARY_PATH="$NATIVE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# @parcel/watcher only bundles a host-arch native binding in this build;
# disable it on Android/Termux to avoid a dlopen architecture mismatch.
export OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER="${OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER:-true}"

# Locate opencode2.bin. Prefer the installed package layout first so
# upgrades do not accidentally execute a stale flat-layout binary.
for candidate in \
    "$DIR/../libexec/opencode2/opencode2.bin" \
    "$PREFIX/libexec/opencode2/opencode2.bin" \
    "$DIR/opencode2.bin"
do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "opencode2: error: could not find opencode2.bin" >&2
exit 127
WEOF

cp "$BIN" "$DIST_DIR/flat/opencode2.bin"
cp "$LIB" "$DIST_DIR/flat/libopentui.so"
chmod 755 "$DIST_DIR/flat/opencode2" "$DIST_DIR/flat/opencode2.bin"

# ==========================================
# 1. ZIP package
# ==========================================
echo ">>> Creating ZIP package..."
ZIP="$OUT/opencode2-${OPENCODE_VERSION}-android-aarch64.zip"
(cd "$DIST_DIR/flat" && zip -9 "$ZIP" opencode2 opencode2.bin libopentui.so >/dev/null)
echo "    Created $ZIP"

# ==========================================
# 2. Pacman package (Termux)
# ==========================================
echo ">>> Creating pacman package..."
STAGE="$OUT/pacman-stage"
mkdir -p "$STAGE/data/data/com.termux/files/usr/bin"
mkdir -p "$STAGE/data/data/com.termux/files/usr/libexec/opencode2"
cp "$DIST_DIR/flat/opencode2" "$STAGE/data/data/com.termux/files/usr/bin/opencode2"
cp "$BIN" "$STAGE/data/data/com.termux/files/usr/libexec/opencode2/opencode2.bin"
cp "$LIB" "$STAGE/data/data/com.termux/files/usr/libexec/opencode2/libopentui.so"
chmod 755 "$STAGE/data/data/com.termux/files/usr/bin/opencode2"
chmod 755 "$STAGE/data/data/com.termux/files/usr/libexec/opencode2/opencode2.bin"
cat > "$STAGE/.PKGINFO" <<PEOF
pkgname = opencode2
pkgver = ${OPENCODE_VERSION}-1
pkgdesc = OpenCode 2 AI coding assistant for Android/Termux
url = https://github.com/guysoft/opencode-termux
builddate = $(date +%s)
packager = opencode-termux
size = $(stat -c%s "$BIN")
arch = aarch64
license = MIT
depend = ripgrep
PEOF

PACMAN_NAME="opencode2-${OPENCODE_VERSION}-1-aarch64.pkg.tar.xz"
(cd "$STAGE" && tar cf - .PKGINFO data | xz -9 > "$OUT/$PACMAN_NAME")
echo "    Created $PACMAN_NAME"

# ==========================================
# 3. Deb package (Termux)
# ==========================================
echo ">>> Creating deb package..."
DEB_STAGE="$OUT/deb-stage"
mkdir -p "$DEB_STAGE/data/data/data" "$DEB_STAGE/DEBIAN"
cp -a "$STAGE/data/data/." "$DEB_STAGE/data/data/data/"
cat > "$DEB_STAGE/DEBIAN/control" <<DEOF
Package: opencode2
Version: ${OPENCODE_VERSION}
Architecture: aarch64
Maintainer: Guy Sheffer <guysoft@gmail.com>
Installed-Size: $(du -sk "$DEB_STAGE/data" | cut -f1)
Depends: ripgrep
Section: utils
Priority: optional
Homepage: https://github.com/guysoft/opencode-termux
Description: OpenCode 2 AI coding assistant for Android/Termux
 This package provides the OpenCode v2 CLI (opencode2) and the Android
 OpenTUI renderer. It installs alongside the v1 opencode package.
DEOF
printf '2.0\n' > "$DEB_STAGE/debian-binary"
(cd "$DEB_STAGE/data" && tar czf "$DEB_STAGE/data.tar.gz" data)
(cd "$DEB_STAGE/DEBIAN" && tar czf "$DEB_STAGE/control.tar.gz" control)
(cd "$DEB_STAGE" && ar rc "$OUT/opencode2_${OPENCODE_VERSION}_aarch64.deb" debian-binary control.tar.gz data.tar.gz)
DEB_NAME="opencode2_${OPENCODE_VERSION}_aarch64.deb"
echo "    Created $DEB_NAME"

# ==========================================
# Summary
# ==========================================
rm -rf "$STAGE" "$DEB_STAGE"
(cd "$OUT" && sha256sum "$DEB_NAME" "$PACMAN_NAME" "opencode2-${OPENCODE_VERSION}-android-aarch64.zip" > SHA256SUMS)
echo ""
echo "=== Packages created ==="
echo ""
ls -lh "$OUT"/*.{zip,xz,deb} "$OUT/SHA256SUMS"
echo ""
echo "Install on Termux:"
echo "  pacman -U $PACMAN_NAME"
echo "  dpkg -i $DEB_NAME"
echo "  unzip opencode2-${OPENCODE_VERSION}-android-aarch64.zip"
