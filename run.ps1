<#
.SYNOPSIS
Run Open-FluidSim from source on Windows, the way run.sh does on Unix.

.DESCRIPTION
Runs from source and builds nothing. For standalone executables see
BUILDING.md.

Windows needs three things Unix gets from a package manager, so this script
locates them and fails with an explanation rather than a backtrace:

  raylib.dll        the native library CFFI opens at startup
  cl-raylib         not in Quicklisp, so it lives in local-projects
  libffi + gcc      cl-raylib depends on cffi-libffi, whose build step
                    compiles a C stub against <ffi.h>. MSYS2 supplies both,
                    and its bin directory goes on PATH for the child SBCL.

Run with -Setup once to fetch the first two.

.PARAMETER Test
Run the FiveAM suite and exit non-zero on failure. Needs none of the above:
the core system is deliberately free of foreign dependencies.

.PARAMETER Repl
Load the UI system and stay at the SBCL prompt. Call (open-fluidsim.ui:run)
to open the window, and you keep the REPL after it closes.

.PARAMETER Setup
Clone cl-raylib into Quicklisp's local-projects and download raylib.dll into
the project root, skipping whatever is already there.

.PARAMETER Check
Diagnostic. Opens a window for one second without touching the mouse and
reports whether raylib's button predicates are telling the truth. See
ui/raylib-bool.lisp for what this is watching for.

.EXAMPLE
.\run.ps1 -Setup
.\run.ps1
.\run.ps1 -Test
#>

[CmdletBinding()]
param(
    [switch]$Test,
    [switch]$Repl,
    [switch]$Setup,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
$Quicklisp = if ($env:QUICKLISP_SETUP) { $env:QUICKLISP_SETUP }
             else { Join-Path $env:USERPROFILE 'quicklisp\setup.lisp' }
$LocalProjects = Join-Path $env:USERPROFILE 'quicklisp\local-projects'
$RaylibVersion = '5.5'

# SBCL wants pathnames, so hand it forward slashes and let Windows sort it out.
function ConvertTo-LispPath([string]$p) { $p -replace '\\', '/' }

function Fail([string]$message, [string[]]$hints) {
    Write-Host "run.ps1: $message" -ForegroundColor Red
    foreach ($h in $hints) { Write-Host "  $h" -ForegroundColor DarkGray }
    exit 1
}

# --- prerequisites -------------------------------------------------------

if (-not (Get-Command sbcl -ErrorAction SilentlyContinue)) {
    Fail 'sbcl not found on PATH.' @('choco install sbcl',
                                     'or download from https://www.sbcl.org/platform-table.html')
}

if (-not (Test-Path $Quicklisp)) {
    Fail "quicklisp not found at $Quicklisp" @(
        'install it from https://www.quicklisp.org/, or set $env:QUICKLISP_SETUP')
}

# MSYS2 ships libffi's headers, its DLL and a gcc that can use them. ucrt64
# first: it is the environment MSYS2 itself now defaults to.
$MsysBin = @($env:MSYS2_ROOT, 'C:\msys64\ucrt64', 'C:\msys64\mingw64', 'C:\msys64\clang64') |
    Where-Object { $_ } |
    ForEach-Object { Join-Path $_ 'bin' } |
    Where-Object { Test-Path (Join-Path $_ 'libffi-8.dll') } |
    Select-Object -First 1

# --- setup ---------------------------------------------------------------

if ($Setup) {
    $clRaylib = Join-Path $LocalProjects 'cl-raylib'
    if (Test-Path $clRaylib) {
        Write-Host "cl-raylib already at $clRaylib"
    } else {
        New-Item -ItemType Directory -Force $LocalProjects | Out-Null
        Write-Host "Cloning cl-raylib into $clRaylib"
        git clone --depth 1 https://github.com/longlene/cl-raylib $clRaylib
    }

    $dll = Join-Path $Here 'raylib.dll'
    if (Test-Path $dll) {
        Write-Host "raylib.dll already in the project root"
    } else {
        $zip = Join-Path $env:TEMP 'raylib.zip'
        $out = Join-Path $env:TEMP "raylib-$RaylibVersion"
        $url = "https://github.com/raysan5/raylib/releases/download/$RaylibVersion/raylib-${RaylibVersion}_win64_msvc16.zip"
        Write-Host "Fetching raylib $RaylibVersion"
        Invoke-WebRequest $url -OutFile $zip
        Expand-Archive $zip -DestinationPath $out -Force
        Copy-Item (Get-ChildItem -Recurse -Filter raylib.dll $out).FullName $dll
        Write-Host "raylib.dll -> $dll"
    }

    if (-not $MsysBin) {
        Write-Host ''
        Write-Host 'MSYS2 not found. cffi-libffi cannot build without it:' -ForegroundColor Yellow
        Write-Host '  winget install MSYS2.MSYS2' -ForegroundColor DarkGray
        Write-Host '  C:\msys64\usr\bin\pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-libffi' -ForegroundColor DarkGray
    } else {
        Write-Host "MSYS2 toolchain at $MsysBin"
    }
    Write-Host ''
    Write-Host 'Setup done. Now: .\run.ps1'
    exit 0
}

# --- what each mode needs ------------------------------------------------

# The tests never open a window and never load cl-raylib, so none of the
# foreign machinery has to be present for them.
if (-not $Test) {
    if (-not (Test-Path (Join-Path $LocalProjects 'cl-raylib'))) {
        Fail 'cl-raylib is not in quicklisp/local-projects.' @('run: .\run.ps1 -Setup')
    }
    if (-not (Test-Path (Join-Path $Here 'raylib.dll'))) {
        Fail 'raylib.dll is not in the project root.' @('run: .\run.ps1 -Setup')
    }
    if (-not $MsysBin) {
        Write-Host 'run.ps1: warning - no MSYS2 libffi found; cffi-libffi may fail to build.' -ForegroundColor Yellow
        Write-Host '  run .\run.ps1 -Setup for the install commands.' -ForegroundColor DarkGray
    }
    # Windows resolves DLLs from PATH; raylib.dll sits here, libffi-8.dll there.
    $env:PATH = @($MsysBin, $Here, $env:PATH | Where-Object { $_ }) -join ';'
}

$ql = ConvertTo-LispPath $Quicklisp
$root = ConvertTo-LispPath $Here
$preamble = @("(load `"$ql`")", "(push #p`"$root/`" asdf:*central-registry*)")

# --- run -----------------------------------------------------------------

if ($Test) {
    $sbclArgs = @('--noinform', '--disable-debugger', '--non-interactive') +
            ($preamble | ForEach-Object { '--eval'; $_ }) +
            @('--eval', '(ql:quickload :open-fluidsim/tests :silent t)',
              '--eval', '(sb-ext:exit :code (if (fiveam:run! (quote open-fluidsim/tests::open-fluidsim)) 0 1))')
    & sbcl @sbclArgs
    exit $LASTEXITCODE
}

if ($Check) {
    $probe = Join-Path $env:TEMP 'ofs-check.lisp'
    # Written out rather than passed as --eval forms: the quoting survives
    # better, and the file is readable if it needs debugging.
    @'
(ql:quickload :open-fluidsim/ui :silent t)
(in-package #:open-fluidsim.ui)

;; The same predicates read both ways: as the four-byte int CFFI's :boolean
;; assumes, and as the one byte C actually returns.
(cffi:defcfun ("IsMouseButtonDown" %down-int) :int (button :int))
(cffi:defcfun ("IsMouseButtonDown" %down-byte) :unsigned-char (button :int))
(cffi:defcfun ("IsMouseButtonPressed" %pressed-int) :int (button :int))
(cffi:defcfun ("IsMouseButtonPressed" %pressed-byte) :unsigned-char (button :int))

(let* ((editor (make-editor :circuit (ofs:make-relay-demo-circuit)))
       (camera (rl:make-camera2d :offset (v:vec2 0.0 0.0) :target (v:vec2 0.0 0.0)
                                 :rotation 0.0 :zoom 3.0)))
  (rl:set-trace-log-level :log-warning)
  (rl:with-window (900 600 "check -- do not touch the mouse")
    (rl:set-target-fps 60)
    (sync-camera-to-window camera)
    (fit-view camera (editor-circuit editor))
    (let* ((target (rl:camera2d-target camera))
           (x0 (v:vx target)) (y0 (v:vy target))
           (down 0) (pressed 0))
      (dotimes (i 60)
        (sync-camera-to-window camera)
        (handle-pan-and-zoom editor camera)
        (handle-mouse editor camera)
        (handle-keys editor camera)
        (when (mouse-button-down-p :mouse-button-right) (incf down))
        (when (mouse-button-pressed-p :mouse-button-left) (incf pressed))
        (rl:with-drawing
          (rl:clear-background :raywhite)
          (rl:with-mode-2d (camera) (draw-canvas editor camera))
          (draw-palette (editor-domain editor) (editor-placing editor))
          (draw-hud editor)))
      (let ((drift (+ (abs (- (v:vx target) x0)) (abs (- (v:vy target) y0)))))
        (format t "~&== 60 idle frames, nothing touched ==~%")
        (format t "IsMouseButtonDown      raw int ~10d   low byte ~d~%"
                (%down-int 1) (%down-byte 1))
        (format t "IsMouseButtonPressed   raw int ~10d   low byte ~d~%"
                (%pressed-int 0) (%pressed-byte 0))
        (format t "right-button-down reported on ~d/60 frames (want 0)~%" down)
        (format t "left-click reported on ~d/60 frames (want 0)~%" pressed)
        (format t "camera drift ~,4f (want 0.0)~%" drift)
        (format t "selected ~s  dragging ~s (want NIL NIL)~%"
                (and (editor-selected editor) t) (and (editor-dragging editor) t))
        (format t "~&~a~%"
                (if (and (zerop down) (zerop pressed) (< drift 0.001))
                    "PASS -- input is being read correctly"
                    "FAIL -- phantom input; the editor will look stuck in a pan"))))))
'@ | ForEach-Object { [IO.File]::WriteAllText($probe, $_, (New-Object System.Text.UTF8Encoding($false))) }

    $sbclArgs = @('--noinform', '--disable-debugger', '--non-interactive') +
            ($preamble | ForEach-Object { '--eval'; $_ }) +
            @('--load', $probe)
    & sbcl @sbclArgs
    exit $LASTEXITCODE
}

if ($Repl) {
    Write-Host 'Loading open-fluidsim/ui. At the prompt: (open-fluidsim.ui:run)' -ForegroundColor DarkGray
    $sbclArgs = @('--noinform') +
            ($preamble | ForEach-Object { '--eval'; $_ }) +
            @('--eval', '(ql:quickload :open-fluidsim/ui :silent t)',
              '--eval', '(in-package #:open-fluidsim.ui)')
    & sbcl @sbclArgs
    exit $LASTEXITCODE
}

$sbclArgs = @('--noinform', '--disable-debugger') +
        ($preamble | ForEach-Object { '--eval'; $_ }) +
        @('--eval', '(ql:quickload :open-fluidsim/ui :silent t)',
          '--eval', '(open-fluidsim.ui:run)',
          '--quit')
& sbcl @sbclArgs
exit $LASTEXITCODE
