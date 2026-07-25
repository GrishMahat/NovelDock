#!/bin/bash
set -e

FLUTTER_VERSION="3.29.2"
ANDROID_SDK_ROOT="/usr/lib/android-sdk"

# Install Flutter if not present
if ! command -v flutter &>/dev/null; then
  echo "Installing Flutter $FLUTTER_VERSION..."
  git clone --depth 1 -b "stable" https://github.com/flutter/flutter.git /opt/flutter
fi

export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"
echo 'export PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH"' >> ~/.bashrc
echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" >> ~/.bashrc
echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" >> ~/.bashrc

# Accept Android licenses
yes | $ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager --licenses 2>/dev/null || true

# Flutter config
flutter config --android-sdk "$ANDROID_SDK_ROOT" --no-analytics 2>/dev/null || true

# Verify
echo ""
echo "=== Verification ==="
flutter --version 2>/dev/null | head -3
echo ""
echo "Android SDK: $(ls $ANDROID_SDK_ROOT/platforms/ 2>/dev/null | tr '\n' ' ')"
echo ""
echo "Done. Open a new terminal or run 'source ~/.bashrc' to refresh PATH."
