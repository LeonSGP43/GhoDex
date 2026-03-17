<!-- LOGO -->
<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Logo" width="128">
  <br>GhoDex
</h1>
  <p align="center">
    Fast, native, feature-rich terminal emulator forked from Ghostty.
    <br />
    <a href="#about">About</a>
    ·
    <a href="#upgrade-highlights">Upgrade Highlights</a>
    ·
    <a href="#download">Download</a>
    ·
    <a href="#project-origin">Project Origin</a>
    ·
    <a href="CONTRIBUTING.md">Contributing</a>
    ·
    <a href="HACKING.md">Developing</a>
  </p>
</p>

## About

GhoDex is a personal fork of Ghostty that keeps the upstream terminal core
while adding workflow upgrades for day-to-day development on macOS.

Like upstream, the goal is still speed, native UX, and rich terminal features
without forcing tradeoffs between those pillars.

This repository is in a phased rebrand:

- User-facing docs and project branding are migrating to `GhoDex`.
- Runtime compatibility identifiers such as `ghostty`, `libghostty`, and
  `com.leongong.ghodex` are intentionally retained for now.

## Upgrade Highlights

Recent fork-specific upgrades include:

- Added an AI Terminal Manager settings panel and learning workflow for
  terminal-to-knowledge capture.
- Added a heartbeat task queue with configurable interval/concurrency and
  a dedicated settings tab.
- Hardened update/localization tests to be language-agnostic.
- Added release governance basics (`VERSION`, `CHANGELOG.md`, SemVer flow).

## Download

- Fork releases: <https://github.com/LeonSGP43/GhoDex/releases>
- Upstream releases: <https://github.com/LeonSGP43/GhoDex/releases>

## Documentation

- This repository: [`README.md`](./README.md), [`HACKING.md`](./HACKING.md),
  [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- Upstream docs baseline: <https://github.com/LeonSGP43/GhoDex#readme>

## Project Origin

GhoDex originates from [Ghostty](https://github.com/ghostty-org/ghostty).
This project keeps the original MIT license and upstream attribution intact.
Huge thanks to Mitchell Hashimoto and all Ghostty contributors.
See [`ORIGIN.md`](./ORIGIN.md) for the attribution record.

## Contributing and Developing

If you have ideas or changes for GhoDex, start with
["Contributing"](CONTRIBUTING.md), then read ["Developing"](HACKING.md)
for technical details.

## Roadmap and Status

The high-level ambitious plan for the project, in order:

|  #  | Step                                                      | Status |
| :-: | --------------------------------------------------------- | :----: |
|  1  | Standards-compliant terminal emulation                    |   ✅   |
|  2  | Competitive performance                                   |   ✅   |
|  3  | Basic customizability -- fonts, bg colors, etc.           |   ✅   |
|  4  | Richer windowing features -- multi-window, tabbing, panes |   ✅   |
|  5  | Native Platform Experiences (i.e. Mac Preference Panel)   |   ⚠️   |
|  6  | Cross-platform `libghostty` for Embeddable Terminals      |   ⚠️   |
|  7  | Windows Terminals (including PowerShell, Cmd, WSL)        |   ❌   |
|  N  | Fancy features (to be expanded upon later)                |   ❌   |

Additional details for each step in the big roadmap below:

#### Standards-Compliant Terminal Emulation

GhoDex implements enough control sequences to be used by hundreds of
testers daily for over the past year. Further, we've done a
[comprehensive xterm audit](https://github.com/ghostty-org/ghostty/issues/632)
comparing GhoDex's behavior to xterm and building a set of conformance
test cases.

We believe GhoDex is one of the most compliant terminal emulators available.

Terminal behavior is partially a de jure standard
(i.e. [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/))
but mostly a de facto standard as defined by popular terminal emulators
worldwide. GhoDex takes the approach that our behavior is defined by
(1) standards, if available, (2) xterm, if the feature exists, (3)
other popular terminals, in that order. This defines what the GhoDex project
views as a "standard."

#### Competitive Performance

We need better benchmarks to continuously verify this, but GhoDex is
generally in the same performance category as the other highest performing
terminal emulators.

For rendering, we have a multi-renderer architecture that uses OpenGL on
Linux and Metal on macOS. As far as I'm aware, we're the only terminal
emulator other than iTerm that uses Metal directly. And we're the only
terminal emulator that has a Metal renderer that supports ligatures (iTerm
uses a CPU renderer if ligatures are enabled). We can maintain around 60fps
under heavy load and much more generally -- though the terminal is
usually rendering much lower due to little screen changes.

For IO, we have a dedicated IO thread that maintains very little jitter
under heavy IO load (i.e. `cat <big file>.txt`). On benchmarks for IO,
we're usually within a small margin of other fast terminal emulators.
For example, reading a dump of plain text is 4x faster compared to iTerm and
Kitty, and 2x faster than Terminal.app. Alacritty is very fast but we're still
around the same speed (give or take) and our app experience is much more
feature rich.

> [!NOTE]
> Despite being _very fast_, there is a lot of room for improvement here.

#### Richer Windowing Features

The Mac and Linux (build with GTK) apps support multi-window, tabbing, and
splits.

#### Native Platform Experiences

GhoDex is a cross-platform terminal emulator but we don't aim for a
least-common-denominator experience. There is a large, shared core written
in Zig but we do a lot of platform-native things:

- The macOS app is a true SwiftUI-based application with all the things you
  would expect such as real windowing, menu bars, a settings GUI, etc.
- macOS uses a true Metal renderer with CoreText for font discovery.
- The Linux app is built with GTK.

There are more improvements to be made. The macOS settings window is still
a work-in-progress. Similar improvements will follow with Linux.

#### Cross-platform `libghostty` for Embeddable Terminals

In addition to being a standalone terminal emulator, GhoDex is a
C-compatible library for embedding a fast, feature-rich terminal emulator
in any 3rd party project. This library is called `libghostty`.

Due to the scope of this project, we're breaking libghostty down into
separate actually libraries, starting with `libghostty-vt`. The goal of
this project is to focus on parsing terminal sequences and maintaining
terminal state. This is covered in more detail in this
[blog post](https://mitchellh.com/writing/libghostty-is-coming).

`libghostty-vt` is already available and usable today for Zig and C and
is compatible for macOS, Linux, Windows, and WebAssembly. At the time of
writing this, the API isn't stable yet and we haven't tagged an official
release, but the core logic is well proven (since GhoDex uses it) and
we're working hard on it now.

The ultimate goal is not hypothetical! The macOS app is a `libghostty` consumer.
The macOS app is a native Swift app developed in Xcode and `main()` is
within Swift. The Swift app links to `libghostty` and uses the C API to
render terminals.

## Crash Reports

GhoDex has a built-in crash reporter that will generate and save crash
reports to disk. The crash reports are saved to the `$XDG_STATE_HOME/ghostty/crash`
directory. If `$XDG_STATE_HOME` is not set, the default is `~/.local/state`.
**Crash reports are _not_ automatically sent anywhere off your machine.**

Crash reports are only generated the next time GhoDex is started after a
crash. If GhoDex crashes and you want to generate a crash report, you must
restart GhoDex at least once. You should see a message in the log that a
crash report was generated.

> [!NOTE]
>
> Use the `ghodex +crash-report` CLI command to get a list of available crash
> reports. A future version of GhoDex will make the contents of the crash
> reports more easily viewable through the CLI and GUI.

Crash reports end in the `.ghosttycrash` extension. The crash reports are in
[Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/). You can
upload these to your own Sentry account to view their contents, but the format
is also publicly documented so any other available tools can also be used.
The `ghodex +crash-report` CLI command can be used to list any crash reports.
A future version of GhoDex will show you the contents of the crash report
directly in the terminal.

To send the crash report to the GhoDex project, you can use the following
CLI command using the [Sentry CLI](https://docs.sentry.io/cli/installation/):

```shell-session
SENTRY_DSN=https://e914ee84fd895c4fe324afa3e53dac76@o4507352570920960.ingest.us.sentry.io/4507850923638784 sentry-cli send-envelope --raw <path to ghostty crash>
```

> [!WARNING]
>
> The crash report can contain sensitive information. The report doesn't
> purposely contain sensitive information, but it does contain the full
> stack memory of each thread at the time of the crash. This information
> is used to rebuild the stack trace but can also contain sensitive data
> depending on when the crash occurred.

## Versioning

This project follows Semantic Versioning (`MAJOR.MINOR.PATCH`).
The current version is stored in [`VERSION`](./VERSION), and release history is
tracked in [`CHANGELOG.md`](./CHANGELOG.md).

## End Note

GhoDex is built on top of Ghostty.
Thank you to Mitchell Hashimoto and every upstream contributor for the
foundation this project stands on.
