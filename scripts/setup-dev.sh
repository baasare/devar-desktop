#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
ENGINE_SOURCE="${DEVAR_ENGINE_SOURCE:-../../../devar.engine}"
if [ -d "$ENGINE_SOURCE" ]; then
  .venv/bin/python -m pip install -e "$ENGINE_SOURCE[embedding]"
else
  .venv/bin/python -m pip install "devar-engine[embedding]>=0.2.0,<0.3.0"
fi
swift build
