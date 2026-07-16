#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 'Usage: verify-release-clean.sh <CoffeeSync.app>'
  exit 64
fi

APP="${1:A}"
RUNTIME="$APP/Contents/Resources/ShazamIO/python"
CURRENT_USER="$(id -un)"

test -d "$APP"
test -x "$RUNTIME/bin/python3.10"

if find "$RUNTIME/bin" -mindepth 1 -maxdepth 1 ! -name python3.10 -print -quit | grep -q .; then
  print -u2 'Release runtime contains a development entry point.'
  exit 1
fi

if find "$RUNTIME" \( -name __pycache__ -o -name '*.pyc' -o -name pip -o -name 'pip-*.dist-info' -o -name setuptools -o -name 'setuptools-*.dist-info' \) -print -quit | grep -q .; then
  print -u2 'Release runtime contains a cache or package-management artifact.'
  exit 1
fi

if rg -a -l -F "/Users/$CURRENT_USER" "$APP" >/dev/null; then
  print -u2 "Release app contains a local path for $CURRENT_USER."
  rg -a -l -F "/Users/$CURRENT_USER" "$APP" >&2
  exit 1
fi

if find "$APP" -name '*.dSYM' -o -name '*.debug' | grep -q .; then
  print -u2 'Release app contains a debug-symbol bundle.'
  exit 1
fi

codesign --verify --deep --strict "$APP"
print 'Release cleanliness verification passed.'
