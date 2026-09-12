#!/bin/bash
set -e

# Usage: ./ns2app.sh <script.ns> [AppName] [BundleID]

SCRIPT_PATH="$1"
if [ -z "$SCRIPT_PATH" ] || [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Valid .ns script path required." >&2
    echo "Usage: $0 <script.ns> [AppName] [BundleID]" >&2
    exit 1
fi

BASENAME=$(basename "$SCRIPT_PATH" .ns)
APP_NAME="${2:-$BASENAME}"

SAFE_USER=$(whoami | tr '[:upper:]' '[:lower:]' | tr -d ' ')
SAFE_APP=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
DEFAULT_ID="com.$SAFE_USER.$SAFE_APP"

BUNDLE_ID="${3:-$DEFAULT_ID}"
TARGET_APP="$APP_NAME.app"

NANO_APP="/Applications/NanoSharp.app"
if [ ! -d "$NANO_APP" ]; then
    echo "Warning: You need to put NanoSharp.app in /Applications." >&2
fi

mkdir -p "$TARGET_APP/Contents/MacOS"
mkdir -p "$TARGET_APP/Contents/Resources"

cp "$SCRIPT_PATH" "$TARGET_APP/Contents/Resources/script.ns"

RUNNER_PATH="$TARGET_APP/Contents/MacOS/runner"
cat << 'EOF' > "$RUNNER_PATH"
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FILE="$DIR/../Resources/script.ns"
NANO_APP="/Applications/NanoSharp.app"

if [ -d "$NANO_APP" ]; then
    open -a "$NANO_APP" "$SCRIPT_FILE"
else
    echo "Error: NanoSharp not found. Install NanoSharp to run this application." >&2
    exit 1
fi
EOF

chmod +x "$RUNNER_PATH"

cat << EOF > "$TARGET_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>runner</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "Successfully created standalone app: $TARGET_APP with Bundle ID: $BUNDLE_ID"
