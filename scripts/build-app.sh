#!/bin/sh
set -eu

desktop_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "${1:-}" = "--friend-test-both" ]; then
  if [ -z "${DEVAR_BIBLE_SOURCE_DIR:-}" ]; then
    echo "Set DEVAR_BIBLE_SOURCE_DIR to approved Bible JSON files before building friend-test DMGs." >&2
    exit 1
  fi
  "$desktop_dir/scripts/package-friend-test.sh"
  "$desktop_dir/scripts/package-intel-friend-test.sh"
  exit 0
fi

cd "$desktop_dir"

if [ -z "${DEVAR_PACKAGE_HELPER_DIR:-}" ] && [ ! -x .venv/bin/python ]; then
  echo "Run scripts/setup-dev.sh first to install the local audio helper." >&2
  exit 1
fi

swift_arch="${DEVAR_PACKAGE_ARCH:-$(uname -m)}"
if [ -n "${DEVAR_SWIFT_TRIPLE:-}" ]; then
  swift build -c release --triple "$DEVAR_SWIFT_TRIPLE"
  swift_arch="${DEVAR_SWIFT_TRIPLE%%-*}"
else
  swift build -c release
fi
swift_binary="$desktop_dir/.build/$swift_arch-apple-macosx/release/DevarDesktop"
swift_resources="$desktop_dir/.build/$swift_arch-apple-macosx/release/DevarDesktop_DevarDesktop.bundle"
app="$desktop_dir/dist/Devar.app"
dist="$desktop_dir/dist"
pkill -x DevarDesktop 2>/dev/null || true
python3 -c 'import shutil; shutil.rmtree("dist/Devar.app", ignore_errors=True)'
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$swift_binary" "$app/Contents/MacOS/DevarDesktop"
cp "$swift_resources/devar-logo-mark.png" "$app/Contents/Resources/devar-logo-mark.png"
if [ -n "${DEVAR_PACKAGE_HELPER_DIR:-}" ]; then
  if [ ! -x "$DEVAR_PACKAGE_HELPER_DIR/DevarSpeech" ]; then
    echo "Packaged helper not found at $DEVAR_PACKAGE_HELPER_DIR/DevarSpeech" >&2
    exit 1
  fi
  cp -R "$DEVAR_PACKAGE_HELPER_DIR" "$app/Contents/Resources/DevarSpeech"
fi
if [ -n "${DEVAR_BIBLE_SOURCE_DIR:-}" ]; then
  mkdir -p "$app/Contents/Resources/Bibles"
  for translation in nkjv niv nlt; do
    if [ ! -f "$DEVAR_BIBLE_SOURCE_DIR/$translation.json" ]; then
      echo "The private test package needs $translation.json in DEVAR_BIBLE_SOURCE_DIR." >&2
      exit 1
    fi
    cp "$DEVAR_BIBLE_SOURCE_DIR/$translation.json" "$app/Contents/Resources/Bibles/"
  done
fi
iconset="$desktop_dir/dist/Devar.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
sips -s format png -z 1024 1024 Sources/DevarDesktop/Resources/devar-logo-mark.png --out "$iconset/source.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$iconset/source.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$iconset/source.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
rm "$iconset/source.png"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Devar.icns"
rm -rf "$iconset"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Devar</string>
  <key>CFBundleDisplayName</key><string>Devar</string>
  <key>CFBundleIdentifier</key><string>church.devar.desktop.local</string>
  <key>CFBundleExecutable</key><string>DevarDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Devar</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Devar listens to the audio input you select to transcribe sermon speech and find Bible passages on this Mac.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
if [ "${DEVAR_PACKAGE_SMOKE_TEST:-0}" = "1" ]; then
  "$app/Contents/Resources/DevarSpeech/DevarSpeech" --self-test-embedding-runtime
fi

case "$swift_arch" in
  arm64)
    architecture_name="Apple-Silicon"
    volume_name="Devar Apple Silicon"
    install_note="Install-Devar-Apple-Silicon.txt"
    architecture_note="Apple silicon Macs (M1 or later)"
    search_note="On-device semantic scripture search uses EmbeddingGemma."
    model_note="speech and EmbeddingGemma scripture-search models"
    ;;
  x86_64)
    architecture_name="Intel"
    volume_name="Devar Intel"
    install_note="Install-Devar-Intel.txt"
    architecture_note="Intel Macs"
    search_note="Scripture search uses spoken-reference and keyword matching; semantic search is unavailable on Intel."
    model_note="the CPU speech model"
    ;;
  *)
    echo "DMG packaging supports arm64 and x86_64 builds; got $swift_arch." >&2
    exit 1
    ;;
esac

if [ "${DEVAR_SKIP_DMG:-0}" != "1" ] && [ -n "${DEVAR_PACKAGE_HELPER_DIR:-}" ]; then
  stage="$desktop_dir/.build/dmg-$swift_arch"
  artifact="$dist/Devar-$architecture_name.dmg"
  rm -rf "$stage"
  mkdir -p "$stage" "$dist"
  ditto "$app" "$stage/Devar.app"
  ln -s /Applications "$stage/Applications"
  cat > "$stage/$install_note" <<NOTES
Devar Desktop for macOS

1. Drag Devar.app to Applications.
2. Open Devar from Applications or Spotlight. If macOS warns that it cannot
   verify the developer, Control-click Devar and choose Open.
3. Allow microphone access when asked.
4. In Settings → Suggestions, choose a folder containing your licensed Bible
   JSON file (for example, nkjv.json). Bible text is not included.
5. On first launch, keep the Mac online while Devar downloads $model_note.
   Later launches use the local cached files.
$search_note

This build is for $architecture_note running macOS 15 or later. It is ad hoc signed
and is not notarized. On first open, Control-click Devar and choose Open if
macOS blocks the app. Translation data must be obtained and used under its own license.
NOTES
  rm -f "$artifact"
  hdiutil create -volname "$volume_name" -srcfolder "$stage" -ov -format UDZO "$artifact"
  echo "Created $artifact"
elif [ "${DEVAR_SKIP_DMG:-0}" != "1" ]; then
  echo "Skipped portable DMG: a bundled speech helper is required."
fi

if [ "${DEVAR_OPEN_AFTER_BUILD:-1}" = "1" ]; then
  open "$app"
  echo "Opened $app"
fi
