"""Local JSON-lines bridge for Moonshine streaming and Devar verse search."""

from __future__ import annotations

import json
import os
import platform
import sys
import threading
import time
from collections import deque
from pathlib import Path

_write_lock = threading.Lock()
_state_lock = threading.Lock()
_semantic_prepare_lock = threading.Lock()
_active = None
_active_thread = None
_stopping = False
_generation = 0
_transcriber = None
_whisper_model = None
_preparing = False
_translation = "NKJV"
_last_query = ""
_last_suggested_at = 0.0
_recent_text = ""
_bible = None
_semantic_embedder = None
_semantic_index = None
_semantic_index_translation = None
_reference_tracker = None
_reference_lookup = {}
_last_direct_references: set[str] = set()
_preferred_direct_reference: str | None = None
_completed_text = ""
_active_text = ""
_suggestion_count = 3
_refresh_seconds = 3.0
_context_chars = 450


def emit(kind: str, **payload) -> None:
    with _write_lock:
        sys.stdout.write(json.dumps({"type": kind, **payload}, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def bible_path(translation: str) -> Path | None:
    # During development the repository's approved KJV source is reused in
    # place. Packaged builds can provide DEVAR_BIBLE_DIR or DEVAR_BIBLE_PATH
    # for the user-selected translation without copying licensed data into this
    # source tree.
    import os

    bundled_dir = Path(os.environ["DEVAR_BIBLE_DIR"]) if os.environ.get("DEVAR_BIBLE_DIR") else None
    if bundled_dir:
        bundled_path = bundled_dir / f"{translation.lower()}.json"
        if bundled_path.is_file():
            return bundled_path
    override = Path(os.environ["DEVAR_BIBLE_PATH"]) if os.environ.get("DEVAR_BIBLE_PATH") else None
    if override and override.is_file():
        return override
    root = Path(os.environ.get("DEVAR_REPO_ROOT", Path(__file__).resolve().parents[5]))
    candidate = root / "apps" / "frontend" / "public" / "bibles" / f"{translation.lower()}.json"
    return candidate if candidate.is_file() else None


def load_bible(translation: str):
    global _bible, _translation, _semantic_index, _semantic_index_translation, _reference_lookup
    from devar_engine.suggestions import BibleIndex

    path = bible_path(translation)
    if path is None:
        raise FileNotFoundError(
            f"{translation} Bible data was not found. Configure a Bible data file before listening."
        )
    _translation = translation
    _bible = BibleIndex(path)
    _semantic_index = None
    _semantic_index_translation = None
    _reference_lookup = {
        _reference_key(verse.reference): verse for verse in _bible.all_verses()
    }


def _reference_key(reference: str) -> str:
    import re

    value = re.sub(r"[^a-z0-9:]+", "", reference.casefold())
    return value.replace("psalms", "psalm").replace("songofsongs", "songofsolomon")


def prepare_semantic_search(translation: str | None = None) -> None:
    """Warm EmbeddingGemma and cache verse vectors without blocking listening."""
    global _semantic_embedder, _semantic_index, _semantic_index_translation
    selected = (translation or _translation).upper()
    emit("semantic-search", preparing=True)
    try:
        with _semantic_prepare_lock:
            from devar_engine.embeddinggemma import EmbeddingGemma2, ensure_model
            from devar_engine.semantic import SemanticBibleIndex

            if _semantic_index is not None and _semantic_index_translation == selected:
                return
            model_file = ensure_model()
            if _semantic_embedder is None:
                _semantic_embedder = EmbeddingGemma2(model_file)
            bible = _bible if selected == _translation and _bible is not None else None
            if bible is None:
                from devar_engine.suggestions import BibleIndex

                path = bible_path(selected)
                if path is None:
                    raise FileNotFoundError(f"{selected} Bible data is unavailable for semantic search.")
                bible = BibleIndex(path)
            cache_dir = Path.home() / "Library" / "Application Support" / "Devar" / "VerseIndex"
            index = SemanticBibleIndex(
                bible,
                _semantic_embedder,
                cache_dir=cache_dir,
                progress=lambda fraction: emit("progress", fraction=fraction, item="Preparing verses"),
            )
            if selected == _translation and bible is _bible:
                _semantic_index = index
                _semantic_index_translation = selected
        emit("semantic-index-ready", translation=selected)
    except Exception as exc:
        emit("notice", message=f"Semantic search is unavailable; keyword suggestions remain on. {exc}")
    finally:
        emit("semantic-search", preparing=False)


def suggest(text: str, force: bool = False, reference_text: str | None = None) -> None:
    global _last_query, _last_suggested_at, _recent_text
    global _last_direct_references, _preferred_direct_reference

    try:
        from devar_engine.semantic import hybrid_suggest
    except ImportError:
        # The latest public PyPI release may predate optional semantic ranking.
        # Keep keyword search usable until the matching engine release is available.
        from devar_engine.suggestions import keyword_suggest

        hybrid_suggest = None

    cleaned = " ".join(text.split()).strip()
    if len(cleaned) < 10 or (cleaned == _last_query and not force):
        return
    now = time.monotonic()

    # Exact spoken references should not wait for the slower contextual refresh
    # interval. Moonshine emits partial text before a line is finalized, so this
    # path can show a verse as soon as the reference is recognized.
    if _bible is not None and _reference_tracker is not None:
        direct_matches = _reference_tracker.observe(
            cleaned if reference_text is None else reference_text
        )
        direct_keys = [
            _reference_key(match.reference)
            for match in direct_matches
            if _reference_key(match.reference) in _reference_lookup
        ]
        newly_heard = [key for key in direct_keys if key not in _last_direct_references]
        if newly_heard:
            # Transcript context retains earlier references. Promote the first
            # newly recognized reference so an older exact match cannot stay
            # above the verse the preacher just called out.
            _preferred_direct_reference = newly_heard[-1]
        elif _preferred_direct_reference not in direct_keys:
            _preferred_direct_reference = direct_keys[0] if direct_keys else None
        _last_direct_references = set(direct_keys)
        direct = [
            _reference_lookup[_reference_key(match.reference)]
            for match in direct_matches
            if _reference_key(match.reference) in _reference_lookup
        ]
        if direct:
            if _preferred_direct_reference is not None:
                direct.sort(
                    key=lambda verse: (
                        _reference_key(f"{verse.book} {verse.chapter}:{verse.verse}")
                        != _preferred_direct_reference
                    )
                )
            _last_query = cleaned
            _last_suggested_at = now
            _recent_text = cleaned[-_context_chars:]
            emit(
                "suggestions",
                suggestions=[
                    {
                        "reference": f"{verse.book} {verse.chapter}:{verse.verse}",
                        "translation": _translation,
                        "text": verse.text,
                    }
                    for verse in direct[:_suggestion_count]
                ],
                transcript=_recent_text,
            )
            return

    if not force and now - _last_suggested_at < _refresh_seconds:
        return
    _last_query = cleaned
    _last_suggested_at = now
    _recent_text = cleaned[-_context_chars:]
    if _bible is None:
        load_bible(_translation)
    if hybrid_suggest is None:
        matches = keyword_suggest(_bible, _recent_text, top_k=_suggestion_count)
    else:
        try:
            matches = hybrid_suggest(
                _bible,
                _recent_text,
                semantic_index=(
                    _semantic_index if _semantic_index_translation == _translation else None
                ),
                # Reference detection runs against the current utterance above.
                # Searching the full rolling transcript for references would keep
                # an old callout ahead of fresh quote-based matches for too long.
                include_references=False,
                top_k=_suggestion_count,
            )
        except Exception as exc:
            # Keep the live workflow available if a model/runtime fails mid-service.
            from devar_engine.suggestions import keyword_suggest

            emit("notice", message=f"Semantic search paused; using keyword matches. {exc}")
            matches = keyword_suggest(_bible, _recent_text, top_k=_suggestion_count)
    results = []
    for match in matches:
        verses = getattr(match, "verses", [])
        if not verses:
            continue
        results.append({
            "reference": match.reference,
            "translation": _translation,
            "text": " ".join(verse.text for verse in verses),
        })
    emit("suggestions", suggestions=results, transcript=_recent_text)


def stop_listening(next_state: str = "stopped") -> None:
    global _active, _active_thread, _stopping, _generation
    with _state_lock:
        _generation += 1
        _stopping = True
        mic = _active
    if mic is not None:
        try:
            mic.stop()
        except Exception:
            pass
        try:
            mic.close()
        except Exception:
            pass
    with _state_lock:
        _active = None
        _active_thread = None
        _stopping = False
    emit("state", state=next_state)


def prepare_runtime(translation: str) -> None:
    """Load Bible and architecture-appropriate speech models before Start."""
    global _transcriber, _whisper_model, _preparing
    if _preparing or _transcriber is not None or _whisper_model is not None:
        return
    _preparing = True
    try:
        emit("state", state="loading-data")
        load_bible(translation)
        is_intel = platform.machine().lower() in {"x86_64", "amd64"}
        if is_intel:
            emit("notice", message="Semantic verse search is unavailable on Intel Macs. Direct references and keyword suggestions remain available.")
        else:
            threading.Thread(
                target=prepare_semantic_search,
                args=(translation,),
                name="devar-semantic-index",
                daemon=True,
            ).start()
        emit("state", state="loading-model")
        if is_intel:
            from pywhispercpp.model import Model

            model_dir = Path.home() / "Library" / "Application Support" / "Devar" / "WhisperModels"
            model_dir.mkdir(parents=True, exist_ok=True)
            _whisper_model = Model(
                "tiny.en",
                models_dir=str(model_dir),
                n_threads=max(2, min(4, (os.cpu_count() or 4) - 1)),
                print_progress=False,
                print_realtime=False,
                redirect_whispercpp_logs_to=None,
                context_params={"use_gpu": False},
            )
            engine = "Whisper.cpp · CPU"
        else:
            from moonshine_voice import ModelArch, Transcriber, get_model_for_language, get_spelling_model_path

            model_path, model_arch = get_model_for_language(
                "en", ModelArch.MEDIUM_STREAMING,
                on_progress=lambda fraction, name: emit("progress", fraction=fraction, item=name),
            )
            spelling_path = get_spelling_model_path("en")
            _transcriber = Transcriber(model_path, model_arch, spelling_model_path=spelling_path)
            engine = "Moonshine Streaming"
        emit("engine", name=engine)
        emit("state", state="prepared")
    except Exception as exc:
        emit("state", state="error")
        emit("error", message=str(exc))
    finally:
        _preparing = False


def start_listening(device_index: int, translation: str, suggestion_count: int, refresh_seconds: float, context_seconds: int) -> None:
    global _active, _active_thread, _last_query, _last_suggested_at, _recent_text
    global _completed_text, _active_text, _suggestion_count, _refresh_seconds, _context_chars, _stopping, _generation
    global _reference_tracker, _last_direct_references, _preferred_direct_reference
    if _transcriber is None and _whisper_model is None:
        emit("state", state="error")
        emit("error", message="Devar is still preparing the local speech model. Wait for setup to finish, then try again.")
        return
    with _state_lock:
        _generation += 1
        generation = _generation
        _stopping = False
    _last_query = ""
    _last_suggested_at = 0.0
    _recent_text = ""
    _completed_text = ""
    _active_text = ""
    _last_direct_references = set()
    _preferred_direct_reference = None
    try:
        from devar_engine.references import SpokenReferenceTracker

        _reference_tracker = SpokenReferenceTracker(
            context_ttl=max(45.0, float(context_seconds) * 2.0)
        )
    except ImportError:
        _reference_tracker = None
        emit(
            "notice",
            message="This Devar Engine version does not include live spoken-reference detection. Keyword scripture search remains available.",
        )
    _suggestion_count = min(max(int(suggestion_count), 1), 10)
    _refresh_seconds = min(max(float(refresh_seconds), 1.0), 15.0)
    _context_chars = min(max(int(context_seconds), 10), 120) * 15
    emit("state", state="connecting")

    if _whisper_model is not None:
        _start_whisper_listening(device_index, generation)
        return

    def run():
        global _active, _stopping
        mic = None
        try:
            if translation != _translation:
                load_bible(translation)
                threading.Thread(
                    target=prepare_semantic_search,
                    args=(translation,),
                    name="devar-semantic-index",
                    daemon=True,
                ).start()
            from moonshine_voice import MicTranscriber, ModelArch

            def on_text(text: str) -> None:
                if _stopping or generation != _generation:
                    return
                global _active_text
                _active_text = text.strip()
                context = f"{_completed_text} {_active_text}".strip()[-_context_chars:]
                emit("transcript", text=context, final=False)
                try:
                    suggest(context, force=False, reference_text=_active_text)
                except Exception as exc:
                    emit("error", message=f"Verse suggestions failed: {exc}")

            def on_line(line) -> None:
                if _stopping or generation != _generation:
                    return
                global _completed_text, _active_text
                text = (getattr(line, "text", "") or "").strip()
                if text and text != _active_text:
                    _completed_text = f"{_completed_text} {text}".strip()
                elif text and not _completed_text.endswith(text):
                    _completed_text = f"{_completed_text} {text}".strip()
                _completed_text = _completed_text[-_context_chars:]
                _active_text = ""
                emit("transcript", text=_completed_text, final=True)
                try:
                    suggest(_completed_text, force=True, reference_text=text)
                except Exception as exc:
                    emit("error", message=f"Verse suggestions failed: {exc}")

            mic = (
                MicTranscriber()
                .language("en")
                .model_arch(ModelArch.MEDIUM_STREAMING)
                .device(device_index)
                .use_transcriber(_transcriber)
                .on_progress(lambda fraction, name: emit(
                    "progress", fraction=fraction, item=name
                ))
                .on_text(on_text)
                .on_line(on_line)
                .on_error(lambda error: emit("error", message=str(error)))
            )
            with _state_lock:
                _active = mic
            mic.load()
            if _stopping or generation != _generation:
                mic.close()
                return
            mic.start()
            if _stopping or generation != _generation:
                mic.stop()
                mic.close()
                return
            emit("state", state="listening")
            while not _stopping and generation == _generation:
                time.sleep(0.1)
        except Exception as exc:
            emit("state", state="error")
            emit("error", message=str(exc))
        finally:
            with _state_lock:
                mic = _active if generation == _generation else None
                if generation == _generation:
                    _active = None
            if mic is not None:
                try:
                    mic.close()
                except Exception:
                    pass

    thread = threading.Thread(target=run, name="devar-moonshine", daemon=True)
    with _state_lock:
        _active_thread = thread
    thread.start()


def _merge_transcript_overlap(previous: str, current: str) -> str:
    """Append only new words from successive overlapping Whisper windows."""
    old_words = previous.split()
    new_words = current.split()
    overlap = 0
    for size in range(min(len(old_words), len(new_words)), 0, -1):
        old_tail = [word.casefold().strip(".,!?;:") for word in old_words[-size:]]
        new_head = [word.casefold().strip(".,!?;:") for word in new_words[:size]]
        if old_tail == new_head:
            overlap = size
            break
    appended = " ".join(new_words[overlap:])
    return " ".join(part for part in (previous, appended) if part).strip()


def _start_whisper_listening(device_index: int, generation: int) -> None:
    """Capture continuously and transcribe short rolling windows on Intel."""
    global _active, _active_thread
    import numpy as np
    import sounddevice as sd

    audio_lock = threading.Lock()
    chunks = deque(maxlen=12)
    sample_count = 0

    def on_audio(indata, frames, timing, status):
        nonlocal sample_count
        if status:
            emit("audio-status", message=str(status))
        with audio_lock:
            chunks.append(indata[:, 0].copy())
            sample_count += frames

    def run():
        nonlocal sample_count
        global _active, _active_thread, _completed_text, _active_text
        stream = None
        last_window_text = ""
        try:
            stream = sd.InputStream(
                device=device_index,
                samplerate=16000,
                channels=1,
                dtype="float32",
                blocksize=16000,
                callback=on_audio,
            )
            stream.start()
            with _state_lock:
                if generation != _generation or _stopping:
                    return
                _active = stream
            emit("state", state="listening")
            last_processed_samples = 0
            while generation == _generation and not _stopping:
                time.sleep(0.5)
                with audio_lock:
                    available = sample_count
                    if available - last_processed_samples < 32000 or not chunks:
                        continue
                    snapshot = np.concatenate(list(chunks))[-96000:].copy()
                    last_processed_samples = available
                segments = _whisper_model.transcribe(
                    snapshot,
                    n_threads=max(2, min(4, (os.cpu_count() or 4) - 1)),
                    language="en",
                    no_context=True,
                    no_timestamps=True,
                    print_progress=False,
                    print_realtime=False,
                )
                text = " ".join(segment.text.strip() for segment in segments if segment.text.strip())
                if not text or text == last_window_text:
                    continue
                _completed_text = _merge_transcript_overlap(_completed_text, text)[-_context_chars:]
                _active_text = text
                last_window_text = text
                emit("transcript", text=_completed_text, final=False)
                try:
                    suggest(_completed_text, force=True, reference_text=text)
                except Exception as exc:
                    emit("error", message=f"Verse suggestions failed: {exc}")
        except Exception as exc:
            if generation == _generation and not _stopping:
                emit("state", state="error")
                emit("error", message=str(exc))
        finally:
            if stream is not None:
                try:
                    stream.stop()
                    stream.close()
                except Exception:
                    pass
            with _state_lock:
                if generation == _generation:
                    _active = None
                    _active_thread = None

    thread = threading.Thread(target=run, name="devar-whisper-cpu", daemon=True)
    with _state_lock:
        _active_thread = thread
    thread.start()


def list_devices() -> list[dict]:
    import sounddevice as sd

    devices = []
    for index, device in enumerate(sd.query_devices()):
        inputs = int(device.get("max_input_channels", 0))
        if inputs > 0:
            devices.append({
                "id": index,
                "name": str(device["name"]),
                "channels": inputs,
                "defaultSampleRate": int(device.get("default_samplerate", 0)),
            })
    return devices


def main() -> None:
    if "--self-test-embedding-runtime" in sys.argv:
        from mlx_vlm.utils import get_model_and_args

        module, model_type = get_model_and_args({"model_type": "embedding_gemma2"})
        if model_type != "embedding_gemma2" or not hasattr(module, "Model"):
            raise RuntimeError("EmbeddingGemma model module could not be loaded")
        print("EmbeddingGemma runtime is bundled and loadable")
        return

    engine = "Whisper.cpp · CPU" if platform.machine().lower() in {"x86_64", "amd64"} else "Moonshine Streaming"
    try:
        devices = list_devices()
        emit("ready", devices=devices, engine=engine, translation="NKJV")
    except Exception as exc:
        emit("ready", devices=[], engine=engine, translation="NKJV")
        emit("error", message=f"Could not list audio inputs: {exc}")

    for line in sys.stdin:
        try:
            command = json.loads(line)
            action = command.get("action")
            if action == "refresh-devices":
                emit("devices", devices=list_devices())
            elif action == "start":
                start_listening(
                    int(command["deviceId"]), command.get("translation", "NKJV"),
                    int(command.get("suggestionCount", 3)),
                    float(command.get("refreshSeconds", 3)),
                    int(command.get("contextSeconds", 30)),
                )
            elif action == "prepare":
                threading.Thread(
                    target=prepare_runtime,
                    args=(command.get("translation", "NKJV"),),
                    name="devar-prepare",
                    daemon=True,
                ).start()
            elif action == "set-bible-directory":
                directory = Path(command["path"]).expanduser()
                if not directory.is_dir():
                    raise FileNotFoundError("The selected Bible data folder is not available.")
                os.environ["DEVAR_BIBLE_DIR"] = str(directory)
                selected_translation = command.get("translation", "NKJV")

                def prepare_after_selection():
                    try:
                        while _preparing:
                            time.sleep(0.1)
                        load_bible(selected_translation)
                        if _transcriber is None and _whisper_model is None:
                            prepare_runtime(selected_translation)
                            return
                        if platform.machine().lower() not in {"x86_64", "amd64"}:
                            threading.Thread(
                                target=prepare_semantic_search,
                                args=(selected_translation,),
                                name="devar-semantic-index",
                                daemon=True,
                            ).start()
                        emit("state", state="prepared")
                    except Exception as exc:
                        emit("state", state="error")
                        emit("error", message=str(exc))

                threading.Thread(
                    target=prepare_after_selection,
                    name="devar-prepare-selected-bible",
                    daemon=True,
                ).start()
            elif action == "pause":
                stop_listening("paused")
            elif action == "stop":
                stop_listening()
                emit("suggestions", suggestions=[], transcript="")
                emit("transcript", text="", final=True)
            elif action == "quit":
                stop_listening()
                if _transcriber is not None:
                    _transcriber.close()
                break
        except Exception as exc:
            emit("error", message=str(exc))


if __name__ == "__main__":
    main()
