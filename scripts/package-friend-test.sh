#!/bin/sh
set -eu

desktop_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$desktop_dir"

if [ "$(uname -m)" != "arm64" ]; then
  echo "Build the friend-test package on an Apple Silicon Mac." >&2
  exit 1
fi
if [ ! -x .venv/bin/python ]; then
  echo "Run scripts/setup-dev.sh first." >&2
  exit 1
fi
if [ -z "${DEVAR_BIBLE_SOURCE_DIR:-}" ]; then
  echo "Set DEVAR_BIBLE_SOURCE_DIR to a folder containing the Bible files you are allowed to share for this private test." >&2
  exit 1
fi
if [ ! -f "$DEVAR_BIBLE_SOURCE_DIR/nkjv.json" ]; then
  echo "DEVAR_BIBLE_SOURCE_DIR must contain nkjv.json because NKJV is the app default." >&2
  exit 1
fi

.venv/bin/python -m pip install -r requirements-packaging.txt

package_root="$desktop_dir/.build/friend-package"
helper_dist="$package_root/pyinstaller-dist"
rm -rf "$package_root"
mkdir -p "$package_root"

set --
if .venv/bin/python -c 'import mlx, mlx_vlm' >/dev/null 2>&1; then
  set -- \
    --collect-all mlx \
    --collect-all mlx_vlm \
    --collect-data mlx_audio \
    --hidden-import=mlx.core \
    --hidden-import=mlx.nn \
    --hidden-import=mlx_vlm.embedding_loader \
    --hidden-import=mlx_vlm.models.embedding_gemma2 \
    --hidden-import=mlx_vlm.models.embedding_gemma2.embedding_gemma2 \
    --hidden-import=mlx_vlm.models.embedding_gemma2.config
else
  echo "EmbeddingGemma runtime is not installed; packaging keyword-search mode."
fi

.venv/bin/python -m PyInstaller \
  --noconfirm --clean --onedir --console \
  --name DevarSpeech \
  --distpath "$helper_dist" \
  --workpath "$package_root/pyinstaller-work" \
  --specpath "$package_root" \
  --collect-all moonshine_voice \
  --collect-all devar_engine \
  "$@" \
  Sources/DevarDesktop/Resources/desktop_bridge.py

export DEVAR_PACKAGE_HELPER_DIR="$helper_dist/DevarSpeech"
export DEVAR_OPEN_AFTER_BUILD=0
export DEVAR_PACKAGE_SMOKE_TEST=1
scripts/build-app.sh
