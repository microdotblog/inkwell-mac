#!/bin/bash

# usage: Scripts/release.sh /path/to/Inkwell.app 1.0 5

APP_PATH="$1"
SHORT_VERSION="$2"
BUILD_VERSION="$3"

APP_NAME=$(basename "$APP_PATH" .app)
ZIP_NAME="${APP_NAME}_${SHORT_VERSION}.zip"

echo "creating archive..."

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"

echo "signing update..."

SIGNATURE=$(Shared/Sparkle/bin/sign_update -p "$ZIP_NAME")

echo "calculating length..."

LENGTH=$(stat -f%z "$ZIP_NAME")

echo ""
echo "Upload this file:"
echo "$ZIP_NAME"
echo ""

echo "Appcast enclosure:"
echo ""

cat <<EOF
<enclosure url="https://s3.amazonaws.com/micro.blog/mac/$ZIP_NAME"
           sparkle:shortVersionString="$SHORT_VERSION"
           sparkle:version="$BUILD_VERSION"
           sparkle:edSignature="$SIGNATURE"
           length="$LENGTH"
           type="application/octet-stream" />
EOF