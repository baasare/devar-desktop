#!/bin/sh
set -eu

desktop_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$desktop_dir"

if [ -z "${DEVAR_BIBLE_SOURCE_DIR:-}" ]; then
  echo "Set DEVAR_BIBLE_SOURCE_DIR to a folder containing the Bible files you are allowed to share." >&2
  exit 1
fi
for translation in nkjv niv nlt; do
  if [ ! -f "$DEVAR_BIBLE_SOURCE_DIR/$translation.json" ]; then
    echo "The private test package needs $translation.json in DEVAR_BIBLE_SOURCE_DIR." >&2
    exit 1
  fi
done

package_root="$desktop_dir/.build/intel-friend-package"
venv="$desktop_dir/.build/intel-venv"
mkdir -p "$package_root"
if [ ! -x "$venv/bin/python" ]; then
  arch -x86_64 python3 -m venv "$venv"
fi
intel_python() {
  arch -x86_64 env \
    "DYLD_LIBRARY_PATH=$venv/lib/python3.12/site-packages${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
    "$venv/bin/python" "$@"
}

intel_python -m pip install --upgrade pip
intel_python -m pip install pyinstaller==6.22.3 'sounddevice>=0.5,<0.6' 'devar-engine[embedding]>=0.2.0,<0.3.0'
intel_python -m pip install --no-binary pywhispercpp pywhispercpp==1.5.1
intel_python -c 'import platform, sounddevice, devar_engine; assert platform.machine() == "x86_64"; import pywhispercpp.model; print("Intel helper dependencies are ready")'

helper_dist="$package_root/pyinstaller-dist"
rm -rf "$helper_dist" "$package_root/pyinstaller-work"
mkdir -p "$helper_dist"
set --
for dylib in "$venv"/lib/python3.12/site-packages/libwhisper*.dylib "$venv"/lib/python3.12/site-packages/libggml*.dylib; do
  [ -f "$dylib" ] || continue
  set -- "$@" --add-binary "$dylib:."
done
intel_python -m PyInstaller \
  --noconfirm --clean --onedir --console \
  --name DevarSpeech \
  --distpath "$helper_dist" \
  --workpath "$package_root/pyinstaller-work" \
  --specpath "$package_root" \
  --collect-all pywhispercpp \
  --collect-all devar_engine \
  --collect-all sounddevice \
  --hidden-import=_pywhispercpp \
  "$@" \
  Sources/DevarDesktop/Resources/desktop_bridge.py

export DEVAR_PACKAGE_ARCH=x86_64
export DEVAR_SWIFT_TRIPLE=x86_64-apple-macosx15.0
export DEVAR_PACKAGE_HELPER_DIR="$helper_dist/DevarSpeech"
export DEVAR_OPEN_AFTER_BUILD=0
scripts/build-app.sh
