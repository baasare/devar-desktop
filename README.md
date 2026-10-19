# Devar Desktop

<p align="center">
  <img src="site/assets/devar-mark.svg" alt="Devar" width="76" />
</p>

<h3 align="center">Keep your presentation workflow. Find the verse faster.</h3>

<p align="center">
  A local-first macOS menu bar companion for church media teams.
  <br />
  <a href="https://baasare.github.io/devar-desktop/">Project site</a> ·
  <a href="docs/architecture.md">How it works</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

Devar listens to an audio input you choose, transcribes sermon speech, and
surfaces likely Bible references beside the apps your team already uses. Review
the match, copy the reference or verse, and paste it into your presentation.
Devar does not replace your presentation software or project verses for you.

> **Project status:** early, open-source macOS prototype. It targets macOS 15 or
> later and supports Apple silicon and Intel with separate speech runtimes.
> Download separate Apple silicon and Intel DMGs from
> [GitHub Releases](https://github.com/baasare/devar-desktop/releases). Bible
> files have separate translation licenses and are not included in this
> repository or public releases.

## What it does

- Lives in the macOS menu bar with a compact panel and an always-available
  listening control strip.
- Captures only the input device you select, such as a microphone or connected
  soundboard interface. It does not capture audio playing from other apps.
- Shows a rolling two-line transcript and ranked scripture suggestions.
- Searches quoted scripture with the released engine's local keyword ranker.
- Compatible development engine builds can add spoken-reference tracking and
  EmbeddingGemma semantic ranking; those newer engine modules are not yet in
  the current PyPI release.
- Copies a reference or verse only when you choose a copy action.
- Keeps audio and transcript context in memory; the app does not save sermon
  recordings or transcripts.
- Runs transcription and verse search on your Mac after required models and a
  Bible dataset have been prepared.

On Apple silicon, the prototype uses Moonshine Streaming. The current released
Devar Engine provides keyword search; compatible development builds can add
EmbeddingGemma semantic ranking and direct-reference tracking. On Intel, it uses
a CPU Whisper.cpp fallback and keyword search; semantic ranking is not available.
Model downloads happen during app setup, not when you press **Start listening**.

## Install a release

Download the DMG matching your Mac from
[GitHub Releases](https://github.com/baasare/devar-desktop/releases/latest),
drag Devar to Applications, and open it. These builds are ad hoc signed and
not notarized; if macOS blocks the first launch, Control-click Devar and choose
**Open**. Allow microphone access when prompted.

Devar does not include Bible translation text. In **Settings → Suggestions**,
choose a folder containing the Bible JSON files you are licensed to use. Files
should be named for their translation, such as `nkjv.json` or `niv.json`, and
use objects with `book`, `chapter`, `verse`, and `text` fields. The selected
folder is saved on your Mac.

The first launch downloads the local speech model and may take a few minutes.
Later starts use the downloaded model. Press **Start listening** after the
app reports that setup is ready.

## Try the prototype from source

### Requirements

- macOS 15 or later
- Xcode 16 or later with the macOS SDK and Swift 6 toolchain
- Python 3.12
- A Bible JSON file whose license permits your intended use

Clone the repository and install the local speech/search helper:

```sh
git clone https://github.com/baasare/devar-desktop.git
cd devar-desktop
scripts/setup-dev.sh
```

The app requires Bible data to suggest verses. Set `DEVAR_BIBLE_PATH` to a
licensed JSON file before opening Devar. The expected format is an array of
objects with `book`, `chapter`, `verse`, and `text` fields:

```json
[
  {"book":"John","chapter":3,"verse":16,"text":"..."}
]
```

Then launch the native menu bar app:

```sh
DEVAR_BIBLE_PATH=/absolute/path/to/bible.json swift run
```

The first run prepares local speech models. Keep the Mac online while those
files download. Choose an audio input, wait for readiness, then press **Start
listening**. macOS will ask for microphone access. Listening starts only after
you press Start, including when the app launches at login. The released PyPI
engine currently supports keyword scripture matching; newer reference tracking
and semantic ranking require a compatible engine development build.

## Build a local app bundle

```sh
scripts/build-app.sh
```

This creates and opens `dist/Devar.app`. For a self-contained local test DMG,
first build the Python helper and provide a licensed Bible directory:

```sh
DEVAR_BIBLE_SOURCE_DIR=/path/to/approved/bibles scripts/package-friend-test.sh
```

That script creates an Apple silicon DMG. It embeds the Bible files you supply,
so keep the resulting DMG private unless the dataset license explicitly permits
redistribution. Intel packaging is available from an Intel Mac with the
required Python/Rosetta toolchain:

```sh
DEVAR_BIBLE_SOURCE_DIR=/path/to/approved/bibles scripts/package-intel-friend-test.sh
```

Both packages are ad hoc signed and not notarized. macOS may require you to
Control-click the app and choose **Open**. The binaries are intended for local
testing; public release DMGs are built without Bible files.

To publish a version, push a `v*` tag (for example `v0.2.0`). GitHub Actions
builds separate Apple silicon and Intel DMGs and attaches both to a GitHub
Release. The public builds use the released `devar-engine` keyword search and
do not include licensed translation data.

## Privacy and permissions

Devar captures audio only after an explicit Start action. Audio and the rolling
transcript stay in memory and are not saved by the app. Speech and scripture
search run locally after model setup. Setup downloads speech/embedding model
files from their upstream providers. This prototype has no account, telemetry,
or cloud transcription path.

Read [the privacy notes](docs/privacy.md) for the data boundaries and
[the architecture overview](docs/architecture.md) for the processing flow.

## Contributing

Issues and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md), and please do not include sermon audio,
transcripts, licensed Bible files, model weights, or credentials in issues or
pull requests.

## License

Devar Desktop source code is released under the MIT License. See [LICENSE](LICENSE).
Third-party dependencies, model weights, and Bible translation data have their
own licenses and terms; this license does not change them.

Devar is an independent project and is not affiliated with Apple, Google, or
Moonshine AI.
