# Contributing to Devar Desktop

Thanks for helping improve Devar Desktop. This repository contains only the macOS companion app and its project site. The web dashboard, backend, and presentation projector are maintained elsewhere.

## Before opening an issue

Search existing issues first. Include your macOS version, Mac processor (Apple silicon or Intel), Devar build/source revision, and the steps needed to reproduce a problem. Do not attach sermon recordings, transcripts, Bible files, model weights, credentials, or clipboard contents.

## Development setup

Follow the source setup in [README.md](README.md). Keep your licensed Bible dataset outside the repository and set `DEVAR_BIBLE_PATH` for local runs. Never add licensed text, model caches, recordings, or generated app bundles to a pull request.

Before submitting a change, run the relevant checks:

```sh
swift build
.venv/bin/python -m unittest discover -s tests -v
```

For UI changes, include a short description of the affected state and a screenshot made with synthetic content. Do not submit screenshots containing private sermon material or personal information.

## Pull requests

- Keep changes scoped to the desktop companion or its standalone site.
- Explain the user-visible behavior and how you verified it.
- Update documentation when setup, privacy, audio capture, model behavior, or packaging changes.
- Preserve explicit operator control over microphone capture and copy actions.
- Do not add telemetry or cloud processing without documenting the data flow and obtaining maintainer review.

By contributing, you agree that your contributions are provided under the repository's MIT License.
