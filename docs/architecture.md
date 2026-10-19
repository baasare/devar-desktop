# Architecture

Devar Desktop has native SwiftUI/AppKit and Windows desktop shells with a local Python process for audio capture, transcription, and scripture search. Each native app and the helper exchange newline-delimited JSON through standard input/output. The helper is based on the public [`devar-engine`](https://github.com/baasare/devar.engine) package; this project does not vendor or fork that engine.

```text
Selected microphone or soundboard input
        ↓
Local speech helper → rolling transcript in memory
        ↓
Exact reference detection → keyword ranking → optional semantic ranking
        ↓
Native menu bar panel → operator reviews and copies a reference or verse
```

On Apple silicon, speech uses Moonshine Streaming. On Intel Macs and Windows x64, the package uses a CPU Whisper.cpp transcription fallback. Semantic ranking depends on a compatible Devar Engine runtime; keyword matching remains available when it is not.

Bible data and model weights are runtime assets. Model downloads come from their upstream providers and are cached locally. A selected Bible JSON file must be provided by the developer or included in a private test package under terms that permit that use. No licensed Bible text or generated model cache belongs in this source repository.

The companion remains separate from the Devar web dashboard, backend, account system, and projector workflow. It does not create a service or send a verse to a projector. The operator copies content into the presentation tool they already use. The Windows shell uses the notification area (system tray), and both platforms capture the selected input device rather than audio playing in other apps.
