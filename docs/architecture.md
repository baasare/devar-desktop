# Architecture

Devar Desktop is a native SwiftUI/AppKit menu bar app with a local Python process for audio capture, streaming transcription, and scripture search. The Swift app and helper exchange newline-delimited JSON through standard input/output. The helper is based on the public [`devar-engine`](https://github.com/baasare/devar.engine) package; this project does not vendor or fork that engine.

```text
Selected macOS audio input
        ↓
Local speech helper → rolling transcript in memory
        ↓
Exact reference detection → keyword ranking → optional semantic ranking
        ↓
Native menu bar panel → operator reviews and copies a reference or verse
```

On Apple silicon, speech uses Moonshine Streaming. The engine can add local EmbeddingGemma semantic ranking after its model and translation index are ready. On Intel, the package uses a CPU Whisper.cpp transcription fallback and keeps direct-reference and keyword matching; semantic ranking is unavailable.

Bible data and model weights are runtime assets. Model downloads come from their upstream providers and are cached locally. A selected Bible JSON file must be provided by the developer or included in a private test package under terms that permit that use. No licensed Bible text or generated model cache belongs in this source repository.

The companion remains separate from the Devar web dashboard, backend, account system, and projector workflow. It does not create a service or send a verse to a projector. The operator copies content into the presentation tool they already use.
