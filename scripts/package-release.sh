#!/bin/sh
set -eu

desktop_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$desktop_dir"

python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt -r requirements-packaging.txt
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then
  .venv/bin/python -m pip install "devar-engine>=0.1.1,<0.2.0"
  .venv/bin/python -m PyInstaller \
    --noconfirm --clean --onedir --console \
    --name DevarSpeech \
    --distpath .build/release-helper \
    --workpath .build/release-work \
    --specpath .build \
    --collect-all moonshine_voice \
    --collect-all devar_engine \
    Sources/DevarDesktop/Resources/desktop_bridge.py
elif [ "$arch" = "x86_64" ]; then
  .venv/bin/python -m pip install "devar-engine>=0.1.1,<0.2.0"
  .venv/bin/python -m pip install --no-binary pywhispercpp pywhispercpp==1.5.1
  intel_python() {
    DYLD_LIBRARY_PATH="$desktop_dir/.venv/lib/python3.12/site-packages${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
      .venv/bin/python "$@"
  }
  intel_python -c 'import platform, pywhispercpp.model; assert platform.machine() == "x86_64"'
  set --
  for dylib in "$desktop_dir"/.venv/lib/python3.12/site-packages/libwhisper*.dylib "$desktop_dir"/.venv/lib/python3.12/site-packages/libggml*.dylib; do
    [ -f "$dylib" ] || continue
    set -- "$@" --add-binary "$dylib:."
  done
  intel_python -m PyInstaller \
    --noconfirm --clean --onedir --console \
    --name DevarSpeech \
    --distpath .build/release-helper \
    --workpath .build/release-work \
    --specpath .build \
    --collect-all pywhispercpp \
    --collect-all devar_engine \
    --collect-all sounddevice \
    --hidden-import=_pywhispercpp \
    "$@" \
    Sources/DevarDesktop/Resources/desktop_bridge.py
else
  echo "DMG builds require an Apple silicon or Intel Mac runner; found $arch." >&2
  exit 1
fi

export DEVAR_PACKAGE_ARCH="$arch"
export DEVAR_PACKAGE_HELPER_DIR="$desktop_dir/.build/release-helper/DevarSpeech"
if [ -n "${GITHUB_REF_NAME:-}" ]; then
  DEVAR_APP_VERSION="${GITHUB_REF_NAME#v}"
  export DEVAR_APP_VERSION
fi
export DEVAR_OPEN_AFTER_BUILD=0
scripts/build-app.sh
