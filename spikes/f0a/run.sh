#!/usr/bin/env bash
# F0-A reproducible runner. Everything happens inside the disposable
# drinphone-spike:f0a container; the host is only touched under spikes/f0a/.
#   spikes/f0a/run.sh image | extract | linux | android | all
set -euo pipefail
cd "$(dirname "$0")"
HERE=$PWD
# Git Bash on Windows: hand docker a C:/... path and stop MSYS rewriting /work.
if command -v cygpath >/dev/null; then HERE=$(cygpath -m "$PWD"); export MSYS_NO_PATHCONV=1; fi
IMG=drinphone-spike:f0a
APPIMAGE=Linphone-6.2.4-x86_64.AppImage
APPIMAGE_SHA256=585c6cc47778117b92d4b387eea9368b5a1642bfc274b0dc86558b98a2dacf6c

in_box() { docker run --rm -u 1000:1000 -v "$HERE:/work" -w /work "$IMG" bash -c "$1"; }

image() { docker build -t "$IMG" .; }

extract() {
  mkdir -p vendor && cd vendor
  [ -f "$APPIMAGE" ] || curl -fsSLO "https://download.linphone.org/releases/linux/app/$APPIMAGE"
  echo "$APPIMAGE_SHA256  $APPIMAGE" | sha256sum -c -
  cd "$HERE"
  in_box "cd vendor && rm -rf squashfs-root && { chmod +x $APPIMAGE 2>/dev/null || test -x $APPIMAGE; } && ./$APPIMAGE --appimage-extract >/dev/null"
}

linux() {
  # liblinphone does not create its default data dir; without it the DB open fails and core_start returns -2.
  in_box "mkdir -p ~/.local/share/linphone && cd probe && flutter pub get && flutter build linux --debug && \
    LIB=\$(ls /work/vendor/squashfs-root/usr/lib/liblinphone.so* | head -1) && \
    F0A_LIBLINPHONE=\$LIB F0A_RESOURCES=/work/vendor/squashfs-root/usr/share \
    timeout 60 xvfb-run -a build/linux/x64/debug/bundle/drinphone_f0a_probe 2>&1 | tee ../linux-run.log"
}

android() {
  in_box "cd probe && flutter pub get && flutter build apk --debug 2>&1 | tee ../android-build.log"
}

case "${1:-all}" in
  image) image ;; extract) extract ;; linux) linux ;; android) android ;;
  all) image; extract; linux; android ;;
  *) echo "usage: $0 image|extract|linux|android|all" >&2; exit 2 ;;
esac
