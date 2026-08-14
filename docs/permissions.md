# Microphone & Camera Permissions (TCC)

Sketches that use the microphone (`AudioAnalyzer`, via `createAudioInput()`) or a
camera (`CaptureDevice`, via `createCapture()` / `listCaptureDevices()`) trigger
macOS's privacy system, **TCC** (Transparency, Consent, and Control). This page
explains how that works for a `metaphor` sketch launched with `swift run` /
`metaphor run`, what happens when a permission is denied, and how to recover.

If you just want the short version: run your sketch once, approve the system
dialog, and it works from then on. Read on if it *doesn't* work, or if you want
to understand why the dialog mentions your terminal app instead of your sketch.

## Which app does macOS actually ask permission for?

A sketch built with `swift run` (or `metaphor run` / `metaphor watch`, which
build the same way under the hood) is a plain command-line executable — not a
signed `.app` bundle with its own `Info.plist`. metaphor's example packages and
`metaphor new` templates don't ship an `Info.plist` for this reason, so there is
no `NSMicrophoneUsageDescription` / `NSCameraUsageDescription` string for macOS
to read.

TCC still needs *something* to attribute the request to, so it walks up the
process tree to find the nearest app it recognizes — the **responsible
process**. For a binary launched from a shell inside a terminal, that's
whichever terminal app you're using: `Terminal.app`, iTerm2, the VS Code
integrated terminal, and so on. In practice this means:

- The permission dialog names your **terminal app**, not "MySketch" or
  "metaphor".
- The grant in **System Settings → Privacy & Security → Microphone / Camera**
  is recorded against that terminal app, not your sketch.
- Approving it once covers every `swift run` / `metaphor run` sketch you launch
  from that same terminal app afterwards.
- If you run sketches from more than one terminal app (say, Terminal.app for
  one project and iTerm2 for another), each needs its own grant — they're
  independent entries in Privacy & Security.
- An AI agent's terminal (Claude Code, an IDE's integrated terminal, etc.)
  counts as its own responsible process too, separate from a Terminal.app
  window you might use interactively.

This is standard macOS behavior for any command-line tool, not something
specific to metaphor — the same thing happens with, say, a Python script that
opens the microphone.

## What you'll see

**First run** (permission not yet decided): macOS shows a system dialog like
*"\<Terminal app\> would like to access the microphone / camera"*. Click Allow.
The sketch's audio/video starts working immediately — no restart needed.

**Denied or previously denied**: no dialog appears again (macOS only asks
once), and the failure is silent unless the sketch checks for it explicitly:

- `AudioAnalyzer.start()` throws `AudioAnalyzerError.microphonePermissionDenied`
  when the microphone is denied. If your sketch doesn't `try`/handle this, you
  may just see no audio reaction and no error — always wrap `try audio.start()`
  and surface failures during development.
- `CaptureDevice` created via `createCapture()` sets `isAvailable = false` and
  logs a warning (`Camera permission has been denied. Enable it in System
  Settings > Privacy & Security > Camera`) instead of throwing. Example sketches
  such as [`CameraSwitching`](../Examples/Basics/Video/CameraSwitching),
  [`FaceDetection`](../Examples/ML/FaceDetection), and
  [`PersonSegmentation`](../Examples/ML/PersonSegmentation) all check
  `isAvailable` / whether `capture` is `nil` and show "Camera not available" /
  "No camera found" on screen instead of crashing.

## Recovering from a denied permission

1. Open **System Settings → Privacy & Security → Microphone** (or **Camera**).
2. Find your terminal app in the list (Terminal, iTerm, Visual Studio Code,
   etc.) and toggle it on. If it isn't listed at all, no request has been made
   from that app yet — just run the sketch again to trigger the dialog.
3. **Quit and reopen the terminal app** (not just the sketch) after toggling
   the permission — macOS re-checks TCC state at process launch, and an
   already-running terminal process can keep the old (denied) state for its
   child processes.
4. Re-run the sketch.

### Resetting with `tccutil`

`tccutil reset <Service>` clears a TCC decision so macOS will prompt again.
Two forms exist, and they are **not** equivalent:

```bash
# Scoped: only resets this one app's decision. Prefer this.
tccutil reset Microphone com.apple.Terminal      # Terminal.app
tccutil reset Microphone com.googlecode.iterm2   # iTerm2
tccutil reset Camera com.apple.Terminal

# Unscoped: resets EVERY app's decision for this service on the whole Mac.
tccutil reset Microphone
tccutil reset Camera
```

The unscoped form is a blunt instrument — it also revokes microphone/camera
access you previously granted to Zoom, Slack, your browser, and everything
else, and every one of those apps will re-prompt on next use. Prefer the
scoped form with the terminal app's bundle identifier (find it with
`osascript -e 'id of app "Terminal"'` or `mdls -name kMDItemCFBundleIdentifier
-r /Applications/iTerm.app`, or check **System Settings → Privacy & Security**
directly — it lists exactly what's currently granted).

## Info.plist usage strings and Xcode-packaged apps

The `NSMicrophoneUsageDescription` / `NSCameraUsageDescription` Info.plist keys
that supply the custom explanation text on the permission dialog only apply to
apps that *have* an Info.plist — i.e., a proper `.app` bundle. A bare
`swift run` / `swift build` executable target has none, so macOS falls back to
its generic system wording attributed to the responsible process described
above. There is nothing to configure on the metaphor or example-package side to
change this.

If you embed a metaphor sketch inside an Xcode app target (see [SwiftPM as a
dependency](../README.en.md#swiftpm-as-a-dependency) in the main README) rather
than running it via `swift run`, the usual Xcode rules apply: add
`NSMicrophoneUsageDescription` / `NSCameraUsageDescription` to that target's
Info.plist yourself for a friendlier, sketch-specific prompt, and code-sign the
app so TCC attributes the request to it directly instead of to a terminal.

This also matters for **Continuity Camera** (using an iPhone/iPad as a webcam):
`CaptureDevice.list()` only discovers Continuity Camera devices when the
`NSCameraUseContinuityCameraDeviceType` Info.plist key is present, which — for
the same reason — a plain `swift run` executable doesn't have. Continuity
Camera shows up once you package the sketch as a proper `.app` with that key
set; built-in and external (USB) cameras work either way.

## Microphone input from an example

The tutorial's part 7 has two microphone sketches:
[`Examples/Tutorial/07-Media/01-AudioInput`](../Examples/Tutorial/07-Media/01-AudioInput)
drives a circle from `volume`, and
[`02-Spectrum`](../Examples/Tutorial/07-Media/02-Spectrum) draws the FFT
spectrum and flashes on beats. Both print the reason on screen when `start()`
throws, which is what a denied permission looks like from inside a sketch —
see [第 7 部 メディア](tutorial/07-media.md) for the walkthrough.

To start a new sketch from a template instead,
[`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli)'s `audio-reactive`
project template (`metaphor new MySketch --template audio-reactive`) wires up
`createAudioInput()` for you — the microphone TCC behavior described on this
page applies to it the same way.

## See also

- [Troubleshooting](../README.en.md#troubleshooting) in the main README for
  other common setup problems.
- [`Sources/MetaphorAudio/AudioAnalyzer.swift`](../Sources/MetaphorAudio/AudioAnalyzer.swift)
  and [`Sources/MetaphorCore/Input/CaptureDevice.swift`](../Sources/MetaphorCore/Input/CaptureDevice.swift)
  for the exact permission checks this page describes.
