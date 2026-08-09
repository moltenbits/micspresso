# Micspresso ☕️🎙️

> AirPods microphone acting tired? Give it a boost with Micspresso!

[![CI](https://github.com/moltenbits/micspresso/actions/workflows/ci.yml/badge.svg)](https://github.com/moltenbits/micspresso/actions/workflows/ci.yml)

Micspresso is a macOS menu bar app that keeps your microphone *warm* so it's
instantly ready when you start talking.

## The problem

Bluetooth headsets — AirPods especially — drop their microphone link into a
power-saving state whenever no app is capturing. The next time an app engages
the mic (dictation, push-to-talk, a voice assistant, an AI coding tool), the
headset has to renegotiate its call-audio link first. That takes one to two
seconds, and your first few words fall on deaf ears.

If you dictate a lot, that delay — and the clipped first words — gets old
fast.

## The fix

Micspresso holds your Bluetooth mic open with a no-op Core Audio client.
The device sees an active capture session, so it never powers down its mic
link — and the moment a real app wants audio, it's already hot. Core Audio
shares input devices between clients, so dictation, calls, and recordings
all work exactly as before, just without the wake-up delay.

Only Bluetooth mics are kept awake: wired and built-in mics have no wake-up
delay, so holding them open would light the privacy indicator for nothing.
When no Bluetooth mic is connected, Micspresso simply idles.

**Micspresso never reads, stores, or transmits audio.** The capture callback
literally ignores the buffers — it counts them (to detect a dead session) and
returns.

## Install

```bash
brew install --cask moltenbits/tap/micspresso
```

Or grab `Micspresso.app` from the [latest release](https://github.com/moltenbits/micspresso/releases),
or build from source:

```bash
git clone https://github.com/moltenbits/micspresso.git
cd micspresso
make install   # builds the app bundle and copies it to /Applications
```

Launch it, allow microphone access when prompted, and look for the mic in
the menu bar — it steams while a mic is being kept awake, and cools off
when paused or idle.

## Usage

Everything lives in the menu bar menu:

- Your connected Bluetooth mics are listed at the top; the checked one is
  being kept awake. Click another to switch. With no selection, Micspresso
  follows the system default input (or the first available Bluetooth mic),
  and a disconnected pick falls back to whatever's still connected until it
  returns.
- **Pause / Resume Micspresso** — one click to get out of the way.
- **Launch at Login**

The CLI binary also answers `--version` and `--help`.

## Trade-offs (read this once)

- **The orange mic indicator stays lit.** That's accurate: the mic is open —
  being open is the entire point. Nothing is recorded.
- **Bluetooth playback quality drops while the mic is warm.** This is a
  Bluetooth protocol reality, not a Micspresso bug: while any app holds a
  Bluetooth mic, the headset sits in its call-audio profile, which caps
  playback quality. Pause Micspresso from the menu bar before a music
  session, resume when you're back to dictating.
- **Slightly higher AirPods battery drain**, for the same reason — the
  call-audio link never idles.

## How it works

- A **no-op HAL IOProc** (`AudioDeviceCreateIOProcID` + `AudioDeviceStart`)
  holds the device open. Deliberately *not* `AVCaptureSession`, whose
  teardown can deadlock against coreaudiod when a Bluetooth device vanishes
  mid-session.
- A **device monitor** enumerates connected Bluetooth mics and follows the
  system default input for auto-picking. Change events are debounced for a
  couple of seconds because a single Bluetooth handoff fires several rapid
  events — sometimes with a transient "no default input" in the middle.
- A **heartbeat watchdog** notices when IO callbacks stop flowing (a
  coreaudiod restart kills capture sessions without any notification) and
  rebuilds the session.
- **Sleep/wake aware**: the mic is released *before* sleep — tearing down
  audio on an already-dead Bluetooth link is historically where tools like
  this deadlock — and re-warmed once devices settle after wake.
- Failed starts retry with capped exponential backoff.

The decision logic lives in `MicspressoCore` behind protocol seams
(`AudioInputProviding`, `MicWarming`, `MicPermissionChecking`,
`EngineScheduling`) and is fully unit-tested; the Core Audio implementations
are thin adapters.

## Prior art

Micspresso was inspired by [macos-mic-keepwarm](https://github.com/drewburchfield/macos-mic-keepwarm),
which proved the keep-warm approach works. Micspresso does a few things
differently: a menu bar UI with pause/resume, a Bluetooth-only policy, HAL
IO instead of `AVCaptureSession`, sleep/wake handling, a signed + notarized
app bundle (stable TCC identity across upgrades), Homebrew distribution, and
a tested, componentized core.

## Development

```bash
make test            # run the unit tests
make run             # build a debug bundle and run it
make bundle-release  # release app bundle ("Micspresso Dev.app" without .env)
make lint            # swift-format lint
make help            # everything else
```

Local builds are a separate "Micspresso Dev" app (own bundle ID and TCC
records), signed with a local dev certificate when one exists so the mic
permission survives rebuilds — see
[docs/distribution.md](docs/distribution.md).

Releases are cut by pushing a `v*` tag; GitHub Actions builds, signs,
notarizes, publishes the release, and updates the Homebrew cask. See
[docs/distribution.md](docs/distribution.md).

## License

[MIT](LICENSE)
