# Privacy notes

Devar Desktop is designed as a local companion for a live sermon workflow.

## Audio and transcript

The app captures audio only after the operator presses **Start listening**, and only from the selected microphone or soundboard input. It does not capture system audio from other apps. The current implementation holds audio buffers and a short rolling transcript in memory. It does not save raw audio or full sermon transcripts. Stopping or quitting ends capture and clears the active rolling context.

## Local processing and downloads

Transcription and scripture matching run locally on the Mac or Windows PC. The first setup downloads speech and, on Apple silicon, semantic-search model files from their upstream providers. Later processing uses locally cached assets. The app has no sign-in, analytics, telemetry, or cloud transcription feature.

The Bible text used for lookup is supplied as a local JSON file or bundled by a private test build. This repository and public releases do not include Bible translation text. You are responsible for using a dataset whose license permits your use and distribution.

## Permissions

macOS microphone access is needed to capture the chosen input. Denying access keeps listening disabled; it does not trigger a cloud fallback. Launch at login does not start audio capture.

## Prototype limits

These notes describe the current prototype. Review the implementation and release notes before relying on them for a production deployment. See [CONTRIBUTING.md](../CONTRIBUTING.md) for safe bug-report guidance.
