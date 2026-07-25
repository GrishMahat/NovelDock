#!/bin/bash
set -e

FLUTTER_VERSION="3.29.2"

# Detect Android SDK location
ANDROID_SDK_ROOT=""
for candidate in "$HOME/Android/Sdk" /usr/lib/android-sdk /opt/android-sdk /usr/local/android-sdk; do
  if [ -d "$candidate/cmdline-tools/latest/bin" ] || [ -d "$candidate/platforms" ]; then
    ANDROID_SDK_ROOT="$candidate"
    break
  fi
done

if [ -z "$ANDROID_SDK_ROOT" ]; then
  echo "WARNING: No Android SDK found. Install it or set ANDROID_HOME manually."
fi

# Install Flutter if not present
if ! command -v flutter &>/dev/null; then
  echo "Installing Flutter $FLUTTER_VERSION..."
  git clone --depth 1 -b "stable" https://github.com/flutter/flutter.git /opt/flutter
fi

export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
grep -q 'flutter/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"' >> ~/.bashrc

if [ -n "$ANDROID_SDK_ROOT" ]; then
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  grep -q 'ANDROID_HOME' ~/.bashrc 2>/dev/null || {
    echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" >> ~/.bashrc
    echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" >> ~/.bashrc
  }

  # Accept Android licenses
  SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
  if [ -f "$SDKMANAGER" ]; then
    yes | "$SDKMANAGER" --licenses 2>/dev/null || true
  fi

  flutter config --android-sdk "$ANDROID_SDK_ROOT" --no-analytics 2>/dev/null || true
fi

# Verify
echo ""
echo "=== Verification ==="
flutter --version 2>/dev/null | head -3

if [ -n "$ANDROID_SDK_ROOT" ]; then
  echo "Android SDK: $ANDROID_SDK_ROOT"
  ls "$ANDROID_SDK_ROOT/platforms/" 2>/dev/null | tr '\n' ' '
  echo ""
fi
echo ""
echo "Done. Open a new terminal or run 'source ~/.bashrc' to refresh PATH."
