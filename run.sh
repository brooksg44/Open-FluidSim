#!/bin/sh
# Run Open-FluidSim from source, or run its test suite.
#
#   ./run.sh          open the simulator window
#   ./run.sh --test   run the FiveAM suite, exit non-zero on failure
#
# This runs from source and does not build anything. For standalone
# executables see BUILDING.md.

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
QUICKLISP="${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}"
MODE=run

usage() {
    cat <<EOF
usage: run.sh [--test] [--help]

  (no option)  open the simulator window
  --test, -t   run the test suite and exit
  --help, -h   show this message

environment:
  QUICKLISP_SETUP  path to quicklisp's setup.lisp
                   (default: \$HOME/quicklisp/setup.lisp)

  OPEN_FLUIDSIM_CIRCUITS
                   where S saves and L looks first
                   (default: ~/Documents/Open-FluidSim on macOS,
                   ~/.local/share/open-fluidsim elsewhere)

The examples in circuits/ are always loadable by name whichever of those is
set: the L prompt searches your own directory first and this checkout after.
EOF
}

case "${1:-}" in
    -t|--test) MODE=test ;;
    -h|--help) usage; exit 0 ;;
    "")        ;;
    *)         echo "run.sh: unknown option '$1'" >&2; usage >&2; exit 2 ;;
esac

if ! command -v sbcl >/dev/null 2>&1; then
    echo "run.sh: sbcl not found on PATH." >&2
    echo "  macOS:  brew install sbcl" >&2
    exit 1
fi

if [ ! -f "$QUICKLISP" ]; then
    echo "run.sh: quicklisp not found at $QUICKLISP" >&2
    echo "  install it from https://www.quicklisp.org/, or set QUICKLISP_SETUP" >&2
    exit 1
fi

# The UI needs the native raylib library. The core and the tests do not, so
# only warn when we are actually about to open a window.
if [ "$MODE" = run ]; then
    found=no
    for candidate in /opt/homebrew/lib/libraylib.* /usr/local/lib/libraylib.* \
                     /usr/lib/libraylib.* /usr/lib64/libraylib.*; do
        # Unmatched globs stay literal, so test for existence rather than
        # trusting the expansion. Use if, not &&, or set -e kills the loop.
        if [ -e "$candidate" ]; then
            found=yes
            break
        fi
    done
    if [ "$found" = no ]; then
        echo "run.sh: warning - libraylib not found in the usual places." >&2
        echo "  macOS:  brew install raylib" >&2
        echo "  Debian: apt install libraylib-dev" >&2
        echo "  continuing anyway; CFFI may still find it." >&2
    fi
fi

if [ "$MODE" = test ]; then
    exec sbcl --noinform --disable-debugger --non-interactive \
        --eval "(load \"$QUICKLISP\")" \
        --eval "(push #p\"$HERE/\" asdf:*central-registry*)" \
        --eval '(ql:quickload :open-fluidsim/tests :silent t)' \
        --eval '(sb-ext:exit
                 :code (if (fiveam:run! (quote open-fluidsim/tests::open-fluidsim)) 0 1))'
else
    exec sbcl --noinform --disable-debugger \
        --eval "(load \"$QUICKLISP\")" \
        --eval "(push #p\"$HERE/\" asdf:*central-registry*)" \
        --eval '(ql:quickload :open-fluidsim/ui :silent t)' \
        --eval '(open-fluidsim.ui:run)' \
        --quit
fi
