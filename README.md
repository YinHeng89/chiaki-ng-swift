# chiaki-ng-swift

Native macOS client built with Swift, SwiftUI, Metal, SDL3, FFmpeg, and the chiaki-ng core (chiaki-ng-core).

## Requirements

- macOS 26 or newer on Apple silicon
- Xcode 27 with the macOS 27 SDK
- Homebrew
- Git SSH access to the core submodule's repository (see `.gitmodules`)

Select the Xcode toolchain before building:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## First build

From the repository root:

```sh
git submodule update --init --recursive
make deps
make app
```

The signed development bundle is written to:

```text
.build/chiaki-ng.app
```

`make deps` installs the Homebrew packages used by the Makefile and resolves Swift packages. FFmpeg 9.0.2, OpenSSL 3.6.4, and curl 8.22.0 are downloaded from pinned source archives, verified with SHA-256, and built locally for arm64 macOS 26. Their libraries and license notices are bundled into the app. `make deps-github` fetches the same dependencies prebuilt instead of compiling them. App users do not need Homebrew.

## Build and run

```sh
make
make app
make run
make release
```

| Command | Result |
| --- | --- |
| `make` | Builds and tests the native core, then builds the Swift executable. |
| `make app` | Builds and signs the debug app without opening it. |
| `make run` | Builds, signs, and opens the debug app. |
| `make release` | Builds and signs an optimized app. |

To choose the configuration explicitly:

```sh
make CONFIGURATION=debug app
make CONFIGURATION=release app
```

Kakusan, which lets invited players join a live play session, is built by default. `CHIAKI_KAKUSAN=0` leaves it
out of the native core and the app, hides every Kakusan screen and entry point, drops the `.kakusan` document type
from the bundle and skips the Kakusan tests:

```sh
make CHIAKI_KAKUSAN=0 app
CHIAKI_KAKUSAN=0 make test
```

The build uses `CHIAKI_CODE_SIGN_IDENTITY` when set, then `.local-signing/identity`, and otherwise uses ad hoc signing.

## Starting a stream from the command line or a link

```sh
chiaki-ng.app/Contents/MacOS/ChiakiNG --list
chiaki-ng.app/Contents/MacOS/ChiakiNG --stream "Living Room" --zoom --exit-app-on-stream-exit
open "chiaki-ng://stream/<console id or name>?mode=fullscreen&exit=1"
```

`--list` prints each registered console with its name, id and address. `--stream` takes a console
name, id, hardware id or address and starts it through the same Play step as the library. A local
stream first looks for the console on the network like Connect at launch, waking it from rest mode
when needed, so a link works while the console sleeps.
`--fullscreen`, `--zoom` and `--stretch` start the stream full screen with that picture fit, and
`--remote` uses Play remotely. `--exit-app-on-stream-exit` quits chiaki-ng when the stream ends; on
its own it applies to any console stream. Links accept `mode` (`window`, `fullscreen`, `zoom` or
`stretch`), `exit` (`1` or `0`) and `route` (`local` or `remote`). If a requested stream can't start,
chiaki-ng explains why in a card. When the request asked to exit, it logs the reason and quits instead,
unless another stream is already starting or playing.

## Running against another data folder

```sh
chiaki-ng.app/Contents/MacOS/ChiakiNG --user-data ~/Desktop/chiaki-copy
chiaki-ng.app/Contents/MacOS/ChiakiNG --user-data ~/Desktop/chiaki-copy --list
```

`--user-data <dir>` (or `--user-data=<dir>`) opens the database (`profiles.sqlite`) and the `Catalog`
folder in `<dir>` instead of `~/Library/Application Support/io.github.chiaki-ng.chiaki-ng` (or
`io.github.chiaki-ng.chiaki-ng.debug` for a debug build). Copy both there first to try a
build, or a migration, against a copy of your data. Logs, caches and the Keychain key stay where they
always are, and every other option works as before.

## Tests

```sh
make test
make test HEADLESS=1
```

`make test` checks the core API notes, builds and tests the native core, runs every Swift test target, the SQLite
schema checks and the native video checks. `HEADLESS=1` skips Swift tests that open real windows, for machines
without a window server. Tests never touch the live application data.

Individual checks are available when iterating:

```sh
make test-core
make test-swift
make test-storage
make test-video-metadata
make test-video-state
make native-video-probe
```

To run one Swift suite without the rest:

```sh
CHIAKI_HEADLESS_TESTS=1 swift test --filter ChiakiFeaturesTests
```

## iOS

The portable targets also build for iOS 26:

```sh
make core-ios
make ios-build
make ios-run
```

`IOS_PLATFORM=ios` builds for devices instead of the simulator, `IOS_DEVICE` picks a simulator or a connected
device for `make ios-run` and `make ios-device`, and `make ios-ipa` signs a development `.ipa`.

## Playback core

Local, PSN remote, PS Cloud and PS Now playback all run on libchiaking (`lib/chiaki-ng-core`). The bridge in `lib/bridge` feeds its encoded video to the app's VideoToolbox decoder, decodes Opus audio itself, and forwards controller input, PIN entry, controller passcodes and haptic PCM. Registration, PSN sign-in tokens, console wake-up and the cloud catalog also use libchiaking, and the legacy chiaki-ng core is no longer built or linked. Two PSN requests still leave the app directly: the web sign-in page runs in a web view, and account avatar images are downloaded over HTTPS by the app.

For playback failures, the 4xxx diagnostic codes identify the stage: 40xx for handle creation, 43xx for start, 44xx for state query, 45xx for a failed state, 46xx for pumping, 47xx for stop, and 48xx for app-side media failures. The final digits carry the underlying result where available. The app log is at `~/Library/Logs/io.github.chiaki-ng.chiaki-ng/chiaki.log`, or under `io.github.chiaki-ng.chiaki-ng.debug` for a debug build.

## Formatting, linting and documentation

```sh
make lint-deps
make format
make lint
make lint-docs
make analyze-c
```

`make lint` runs SwiftLint, the C formatting check, the core API notes check and `make lint-docs`.
`make lint-docs` fails when a non-private Swift declaration lacks a `///` DocC comment, builds every target's
`.docc` catalog with warnings as errors, and runs the core's header documentation lint.

## Clean build

```sh
make clean
make app
```

`make clean` removes compiler output while preserving application data and the local signing identity. Run `make help` for the complete target list.

## Credits

The cloud entitlement and visibility logic is ported from [CloudPad-Android](https://github.com/Chazq2023/CloudPad-Android).

## License

chiaki-ng is licensed under the GNU Affero General Public License, version 3 or (at your option) any later version, with additional permissions for linking with OpenSSL and for distribution through application stores such as the Apple App Store. See [LICENSE](LICENSE).

## Contributing

Contributions are welcome. Before your first pull request is merged, CLA Assistant will ask you to sign the [chiaki-ng Contributor License Agreement](https://gist.github.com/streetpea/7ff632ca45180761deb851e7d738e6da). It lets the project keep chiaki-ng under the AGPL with the same OpenSSL and application store permissions, and nothing else.
