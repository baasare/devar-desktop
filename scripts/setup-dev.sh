#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
ENGINE_SOURCE="${DEVAR_ENGINE_SOURCE:-../../../devar.engine}"
engine_arch=$(uname -m)
if [ -d "$ENGINE_SOURCE" ]; then
  if [ "$engine_arch" = "arm64" ]; then
    .venv/bin/python -m pip install -e "$ENGINE_SOURCE[embedding]"
  else
    .venv/bin/python -m pip install -e "$ENGINE_SOURCE"
  fi
else
  .venv/bin/python -m pip install "devar-engine>=0.1.1,<0.2.0"
fi
if [ "$engine_arch" = "x86_64" ]; then
  .venv/bin/python -m pip install --no-binary pywhispercpp pywhispercpp==1.5.1
fi
swift build
