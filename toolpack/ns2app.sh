#!/bin/bash

NANO_APP="/Applications/NanoSharp.app"

if [ ! -d "$NANO_APP" ]; then
    osascript -e 'display dialog "Error: NanoSharp.app was not found in /Applications." buttons {"OK"} default button 1 with icon stop'
    exit 1
fi

NS_FILE=$(osascript -e 'POSIX path of (choose file with prompt "Select your .ns file:")' 2>/dev/null)
if [ -z "$NS_FILE" ]; then
    osascript -e 'display dialog "No file selected. Exiting." buttons {"OK"} default button 1 with icon caution'
    exit 1
fi

BASENAME=$(basename "$NS_FILE" .ns)
DIRNAME=$(dirname "$NS_FILE")

APP_NAME=$(osascript -e 'text returned of (display dialog "Enter the name for the new .app:" default answer "'"$BASENAME"'" with title "App Name")' 2>/dev/null)
if [ -z "$APP_NAME" ]; then
    APP_NAME="$BASENAME"
fi

DEFAULT_ID="com.user.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
BUNDLE_ID=$(osascript -e 'text returned of (display dialog "Enter the Bundle Identifier:" default answer "'"$DEFAULT_ID"'" with title "Bundle Identifier")' 2>/dev/null)
if [ -z "$BUNDLE_ID" ]; then
    BUNDLE_ID="$DEFAULT_ID"
fi

TARGET_APP="$DIRNAME/$APP_NAME.app"

mkdir -p "$TARGET_APP/Contents/MacOS"
mkdir -p "$TARGET_APP/Contents/Resources"

RUNNER_PATH="$TARGET_APP/Contents/MacOS/runner"
cat << EOF > "$RUNNER_PATH"
#!/bin/bash
open -a "$NANO_APP" "$NS_FILE"
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

# 9. GUI Success Notification
osascript -e 'display dialog "Successfully created: '"$APP_NAME"'.app" buttons {"OK"} default button 1 with icon note'
