#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(cat "$root/VERSION")}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a version such as 0.1.0' >&2; exit 1; }
arch=$(dpkg --print-architecture)
[[ "$arch" == amd64 ]] || { echo 'The M45 APT repository currently supports amd64.' >&2; exit 1; }
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$root" log -1 --format=%ct)}"
make -C "$root" all
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pkg/DEBIAN" "$stage/pkg/usr/lib/evenaudio" \
  "$stage/pkg/usr/share/doc/evenaudio" "$stage/debian" "$root/dist"
install -m 0644 "$root"/{evenaudio,engine,routing,presets,interface,appearance,tray,window_preferences}.py \
  "$stage/pkg/usr/lib/evenaudio/"
install -m 0644 "$root/libevenaudio.so" "$stage/pkg/usr/lib/evenaudio/"
install -D -m 0644 "$root/assets/evenaudio.svg" "$stage/pkg/usr/lib/evenaudio/assets/evenaudio.svg"
strip --strip-unneeded "$stage/pkg/usr/lib/evenaudio/libevenaudio.so"
install -D -m 0755 "$root/packaging/evenaudio" "$stage/pkg/usr/bin/evenaudio"
install -D -m 0644 "$root/packaging/evenaudio.desktop" "$stage/pkg/usr/share/applications/evenaudio.desktop"
install -D -m 0644 "$root/assets/evenaudio.svg" "$stage/pkg/usr/share/icons/hicolor/scalable/apps/evenaudio.svg"
install -m 0644 "$root/README.md" "$stage/pkg/usr/share/doc/evenaudio/"
install -m 0644 "$root/LICENSE" "$stage/pkg/usr/share/doc/evenaudio/copyright"
# Derive the native DSP's dependencies from the build platform's shlibs data.
printf 'Source: evenaudio\n\nPackage: evenaudio\nArchitecture: amd64\n' > "$stage/debian/control"
shlibs=$(cd "$stage" && dpkg-shlibdeps -O -e"$stage/pkg/usr/lib/evenaudio/libevenaudio.so")
shlibs=${shlibs#shlibs:Depends=}
cat > "$stage/pkg/DEBIAN/control" <<EOF
Package: evenaudio
Version: $version
Section: sound
Priority: optional
Architecture: $arch
Maintainer: M45 Software <noreply@github.com>
Installed-Size: $(du -sk "$stage/pkg/usr" | cut -f1)
Depends: python3 (>= 3.10), python3-tk, pulseaudio-utils, libpulse0, $shlibs
Recommends: python3-gi, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1
Homepage: https://github.com/M45-Software/EvenAudio
Description: Seven-band live desktop audio compressor
 Stereo-linked compression with instant attack, adjustable release, presets,
 optional voice leveling, and a Tk interface with optional tray controls.
 Works with an existing PulseAudio server or PipeWire's PulseAudio service.
EOF
(cd "$stage/pkg" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum > DEBIAN/md5sums)
find "$stage/pkg" -type d -exec chmod 0755 {} +
find "$stage/pkg" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
dpkg-deb --root-owner-group --build "$stage/pkg" "$root/dist/evenaudio_${version}_${arch}.deb"
