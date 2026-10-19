# Devar for Windows

The Windows companion is a native .NET 8 desktop tray app. It uses the shared
local Python bridge for audio capture and scripture search. Windows captures the
selected microphone or connected soundboard input; the first Windows release
uses Whisper.cpp on CPU. It does not capture audio playing in other apps.

## Build a portable package

Requirements: Windows 10 version 2004 or later (or Windows 11), .NET 8 SDK,
Python 3.12, and a licensed Bible JSON folder. From the repository root, run:

```powershell
apps\desktop\windows\build.ps1
```

This creates `apps\desktop\dist\Devar-Windows-x64.zip`. Extract it and run
`Devar.exe`. The tray icon offers Open, Start listening, Stop listening, and
Quit. Choose the folder containing Bible files such as `nkjv.json` when first
prompted. Devar keeps the folder choice in the current Windows user profile.

The package is unsigned. Windows SmartScreen may show a first-run warning until
the app has a trusted publisher signature. The helper installs Whisper.cpp's
`tiny.en` model under `%LOCALAPPDATA%\Devar\WhisperModels` during first setup;
subsequent starts use the local copy. The app does not include Bible text.

To run the UI from source while developing, install the Windows Python
requirements and Devar Engine, then run:

```powershell
python -m pip install -r apps\desktop\requirements.txt
python -m pip install "devar-engine>=0.1.1,<0.2.0"
dotnet run --project apps\desktop\windows\Devar.Windows\Devar.Windows.csproj
```

For a release, run `build.ps1` on a Windows x64 host and test microphone access,
model setup, transcript updates, exact-reference suggestions, copy actions, tray
controls, and launch/quit behavior on a clean Windows 10/11 machine.
