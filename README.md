# MacPassHTTP

KeePassHTTP plugin for [MacPass](https://github.com/mstarke/MacPass)

## Dependencies

[KeePassHTTPKit](https://github.com/MacPass/KeePassHTTPKit)

[MacPass Source](https://github.com/mstarke/MacPass)

## Installation

### Using a precompiled version

Download the latest release from the [Releases page](https://github.com/MacPass/MacPassHTTP/releases), extract, and copy the resulting file to the MacPass plugin folder at `~/Library/Application Support/MacPass/`. Restart MacPass if you're already running it.

### Building from source

The dependencies and the MacPass plugin SDK predate current Xcode, so a plain
`carthage bootstrap` + `xcodebuild` no longer works out of the box. Two helper
scripts encapsulate the required workarounds (explained in the notes below):

* `build.sh` — **full build**: builds MacPass's dependencies, MacPassHTTP's
  dependencies, then compiles and installs the plugin.
* `build-deps.sh` — just MacPassHTTP's own Carthage dependencies.

#### Quick build (recommended)

```bash
git clone https://github.com/MacPass/MacPassHTTP
git clone https://github.com/mstarke/MacPass          # sibling checkout, see layout below
cd MacPassHTTP
./build.sh
```

This installs the plugin to `~/Library/Application Support/MacPass/MacPassHTTP.mpplugin`
(arm64; restart MacPass to load it). The build is arm64-only, matching MacPass
running natively on Apple Silicon.

#### Manual steps

* Clone the repository
```bash
git clone https://github.com/MacPass/MacPassHTTP
cd MacPassHTTP
```
* Install [Carthage](https://github.com/Carthage/Carthage#installing-carthage)
* Fetch and build dependencies for MacPassHTTP
```bash
./build-deps.sh
```

  > **Note:** Use `./build-deps.sh` instead of calling `carthage bootstrap` directly.
  > The pinned dependencies (GCDWebServer 3.4.1, JSONModel, KeePassHTTPKit) date from
  > ~2019 and need two workarounds on modern Xcode, both handled by the script:
  >
  > 1. **Deployment targets** (macOS 10.7 / iOS 8.0) are below what modern Xcode
  >    supports, so linking fails with `SDK does not contain 'libarclite'` (Apple
  >    removed `libarclite_*.a` in Xcode 14.3+). The script injects
  >    `carthage-deployment-target.xcconfig` via `XCODE_XCCONFIG_FILE`, raising the
  >    targets to the supported minimums and pinning `ARCHS = arm64`.
  > 2. **Duplicate schemes:** GCDWebServer and JSONModel each ship several shared
  >    schemes that build a framework with the *same* product name (e.g. both
  >    `JSONModel` and `JSONModel-mac` produce `JSONModel.framework`). Carthage
  >    builds them in parallel and they race to write the same path in
  >    `Carthage/Build/Mac`, so you intermittently get an iOS framework
  >    (`building for macOS, but linking in dylib built for iOS`) or an arm64-only
  >    iOS slice where the macOS framework should be. The script splits the build
  >    into `checkout → prune → build`, deleting the duplicate non-macOS schemes so
  >    exactly one scheme per framework remains.
  >
  > The build is arm64-only (matches MacPass running natively on Apple Silicon).
  > The script forwards arguments to `carthage`, e.g. `./build-deps.sh update`.
  > Editing the dependency Xcode projects directly does not stick — `carthage`
  > re-checks-out and overwrites them on every run, which is why the fixes live in
  > the script and xcconfig.
* Clone MacPass (as a sibling directory) and build the dependencies the plugin
  needs. On modern Xcode the non-macOS schemes must be pruned first, and
  TransformerKit fails to compile (removed Darwin `xlocale` module) but isn't
  needed by the plugin, so build only the required dependencies:
```bash
cd ..
git clone https://github.com/mstarke/MacPass
cd MacPass
git submodule update --init --recursive
carthage checkout
# remove iOS/tvOS/watchOS schemes so Carthage doesn't race same-named frameworks
find Carthage/Checkouts -path "*/xcshareddata/xcschemes/*.xcscheme" \
  \( -iname "*iOS*" -o -iname "*tvOS*" -o -iname "*watchOS*" \) -delete
XCODE_XCCONFIG_FILE="$(pwd)/../MacPassHTTP/carthage-deployment-target.xcconfig" \
  carthage build HNHUi KeePassKit KissXML --platform macOS
```
  (`build.sh` does all of the above for you.)

* If your folder structure isn't like the following, you need to adjust the ````HEADER_SEARCH_PATHS```` to point to the MacPass folder
````
└─ Folder
   ├─ MacPass
   └─ MacPassHTTP
````

* Change back to the MacPassHTTP folder, compile and install. The plugin's own
  deployment target (10.10) is too low for modern Xcode, it must build arm64 to
  match the dependencies, and it needs MacPass's built frameworks on the
  framework search path:
```bash
cd ../MacPassHTTP
XCODE_XCCONFIG_FILE="$(pwd)/carthage-deployment-target.xcconfig" xcodebuild \
  -scheme MacPassHTTP -configuration Release \
  MACOSX_DEPLOYMENT_TARGET=10.13 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  "FRAMEWORK_SEARCH_PATHS=\$(inherited) \$(PROJECT_DIR)/../MacPass/Carthage/Build/Mac" \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES
```
  After the build, KeePassHTTPKit's own dependencies (GCDWebServers, JSONModel)
  must be embedded into the installed plugin so it can load — `build.sh` does
  this automatically. Again, prefer `./build.sh` over running these by hand.

The plugin is installed automatically to MacPass's plugin folder:
````~/Library/Application Support/MacPass/MacPassHTTP.mpplugin````
Restart MacPass to load it.

## License

The MIT License (MIT)

Copyright (c) 2015-2017 Michael Starke, HicknHack Software GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Additinal Licenses

### KeePassHTTPKit

The MIT License (MIT)

Copyright (c) 2014 James Hurst<br>
Copyright (c) 2015-2017 Michael Starke, HicknHack Software GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
