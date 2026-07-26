# Building standalone executables

To run from source, use `./run.sh` — you don't need any of this. This document
is about producing a single binary someone else can double-click.

## How it works, and the one hard constraint

SBCL builds executables by **dumping a memory image**: you load the system,
then call `sb-ext:save-lisp-and-die`, and SBCL writes the entire heap out with
a runtime prepended. The result is large — 54 MB raw, **13 MB with core
compression enabled** — but has no Lisp-side dependencies at all.

The constraint that shapes everything below: **SBCL cannot cross-compile an
image.** A dumped image contains the live heap of the machine that dumped it,
so a Windows `.exe` must be produced *on* Windows. There is no `--target` flag
and no way around it from macOS.

The native raylib library is a separate matter. CFFI `dlopen`s it at *startup*,
not at build time — verified with `otool -L`, which shows no raylib entry in
the executable's load commands. So the binary alone is not self-contained: the
target machine needs `libraylib.dylib` / `raylib.dll` findable at runtime. See
[Bundling raylib](#bundling-raylib).

## The build script

`build.lisp` in the project root does the work. It picks its output name by
platform and only requests compression when the running SBCL advertises
support, so the same script works on both targets:

```lisp
(sb-ext:save-lisp-and-die
 #+win32 "open-fluidsim.exe" #-win32 "open-fluidsim"
 :executable t
 :toplevel #'entry
 #+sb-core-compression :compression #+sb-core-compression t)
```

## macOS

*Verified on macOS 26.5, Apple Silicon, SBCL 2.6.6, raylib 6.0.*

```sh
brew install sbcl raylib
cd ~/common-lisp/Open-FluidSim
sbcl --noinform --disable-debugger --non-interactive --load build.lisp
./open-fluidsim
```

Produces a **13 MB `Mach-O 64-bit executable arm64`** — natively Apple Silicon,
no Rosetta involved. Confirmed to launch and open its window.

If your SBCL lacks core compression the `#+sb-core-compression` reader
conditionals skip it automatically and you get a 54 MB binary instead.

### Making a .app bundle

A bare Unix executable works but won't behave like a Mac application. Minimum
viable bundle:

```sh
APP="Open FluidSim.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp open-fluidsim "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Open FluidSim</string>
  <key>CFBundleExecutable</key>        <string>open-fluidsim</string>
  <key>CFBundleIdentifier</key>        <string>com.brooksg44.open-fluidsim</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST
```

### Distributing to other Macs

Gatekeeper will refuse an unsigned bundle downloaded from anywhere. To ship it
you need an Apple Developer account, then:

```sh
codesign --force --deep --options runtime \
         --sign "Developer ID Application: YOUR NAME (TEAMID)" "Open FluidSim.app"
ditto -c -k --keepParent "Open FluidSim.app" OpenFluidSim.zip
xcrun notarytool submit OpenFluidSim.zip --apple-id you@example.com \
      --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
xcrun stapler staple "Open FluidSim.app"
```

Untested here — no signing identity on this machine. Without it, recipients
must right-click → Open, or run `xattr -dr com.apple.quarantine` themselves.

## Windows

**Not yet attempted.** Written from the constraints, not from a successful run
— treat it as a starting point.

Because the image must be dumped on Windows, there are two realistic routes.

### Route A: GitHub Actions (recommended)

No local Windows machine required, and it produces a downloadable artifact you
can unzip and run in Parallels exactly the way you ran the itch.io build.

`.github/workflows/build.yml`:

```yaml
name: build
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install SBCL
        run: choco install sbcl --no-progress -y

      - name: Install Quicklisp
        shell: pwsh
        run: |
          Invoke-WebRequest https://beta.quicklisp.org/quicklisp.lisp -OutFile quicklisp.lisp
          sbcl --non-interactive --load quicklisp.lisp `
               --eval '(quicklisp-quickstart:install)'

      - name: Fetch raylib DLL
        shell: pwsh
        run: |
          $v = "5.5"
          Invoke-WebRequest "https://github.com/raysan5/raylib/releases/download/$v/raylib-$v`_win64_msvc16.zip" -OutFile raylib.zip
          Expand-Archive raylib.zip -DestinationPath raylib
          Copy-Item (Get-ChildItem -Recurse -Filter raylib.dll raylib).FullName .

      - name: Build
        run: sbcl --noinform --disable-debugger --non-interactive --load build.lisp

      - uses: actions/upload-artifact@v4
        with:
          name: open-fluidsim-windows
          path: |
            open-fluidsim.exe
            raylib.dll
```

Points to check on the first run:

- **raylib version.** Homebrew gave us 6.0 on macOS; the workflow above pins a
  5.x release because that is what raylib publishes prebuilt MSVC binaries for.
  The bindings work against both, but keep the DLL version deliberate rather
  than accidental.
- **CFFI finding the DLL.** Windows searches the executable's directory, so
  `raylib.dll` sitting next to `open-fluidsim.exe` should suffice. If not, set
  `cffi:*foreign-library-directories*` in `build.lisp` before quickloading.
- **Threading.** SBCL on Windows supports threads but is less exercised than on
  Unix. The core doesn't spawn any; this only matters if that changes.

### Route B: build inside Parallels

Your Parallels Windows 11 is ARM, and SBCL ships x86-64 Windows binaries, so
SBCL would run under Windows' x64 emulation — the same emulation that already
runs the itch.io build. Workable, and slow. Route A is less friction.

## Bundling raylib

Neither platform's binary is self-contained, because CFFI loads the native
library at startup. Options, cheapest first:

1. **Ship the library alongside.** `raylib.dll` next to the `.exe`; on macOS
   `libraylib.dylib` in `Contents/Frameworks/` with an `@executable_path`
   install name set via `install_name_tool`.
2. **Use `deploy`.** Shinmera's library exists precisely for this: it copies
   foreign libraries into the output and rewrites the load paths. It replaces
   `save-lisp-and-die` with an ASDF `deploy-op`, which means adding
   `:defsystem-depends-on (:deploy)`, `:build-operation "deploy-op"` and
   `:entry-point` to the `open-fluidsim/ui` system. Not wired up yet.
3. **Require the user to install it.** Fine for developers (`brew install
   raylib`), not for a teaching tool aimed at students.

Option 2 is the right answer for real distribution; option 1 is enough to test
on another machine.

## Size

The image is mostly SBCL heap, not application code. Measured here:

| | size |
|---|---|
| raw image | 54 MB |
| with core compression | 13 MB |

Compression costs a little startup time while the image decompresses. Don't
expect a small binary either way — that is the tradeoff for the executable
having no dependency on a Lisp installation.
