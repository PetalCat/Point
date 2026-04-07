#!/bin/bash
# Rebuild the APK and push to the app registry
set -e

APK_DIR="/Users/parker/Developer/GlobalMap/apk-server"
VERSION_FILE="$APK_DIR/version.json"
REGISTRY_HOST="10.10.10.14"
REGISTRY_PORT="8484"

# Read current build number or start at 1
if [ -f "$VERSION_FILE" ]; then
    BUILD=$(python3 -c "import json;print(json.load(open('$VERSION_FILE'))['build'])")
    BUILD=$((BUILD + 1))
else
    BUILD=1
fi

VERSION="0.1.$BUILD"
DATE=$(date '+%Y-%m-%d %H:%M')

cd /Users/parker/Developer/GlobalMap/point

# Sync pubspec version with build number
sed -i '' "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml

echo "Building Point v$VERSION (build $BUILD)..."
flutter build apk --debug 2>&1 | tail -3

APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
cp "$APK_PATH" "$APK_DIR/point.apk"

# Write local version.json
cat > "$VERSION_FILE" << EOF
{
  "version": "$VERSION",
  "build": $BUILD,
  "date": "$DATE",
  "apk_url": "http://$REGISTRY_HOST:$REGISTRY_PORT/apps/point/download/point.apk"
}
EOF

# Push to Docker registry
echo "Pushing to registry at $REGISTRY_HOST..."
CONTAINER=$(ssh docker@$REGISTRY_HOST "docker ps -q --filter name=app-registry" 2>/dev/null)
if [ -n "$CONTAINER" ]; then
    scp -q "$APK_DIR/point.apk" docker@$REGISTRY_HOST:/home/docker/point.apk
    ssh docker@$REGISTRY_HOST "docker cp /home/docker/point.apk $CONTAINER:/data/apps/point/point.apk && rm /home/docker/point.apk"
    ssh docker@$REGISTRY_HOST "docker exec $CONTAINER sh -c 'cat > /data/apps/point/meta.json << METAEOF
{
  \"id\": \"point\",
  \"name\": \"Point\",
  \"version\": \"$VERSION\",
  \"size\": $(wc -c < "$APK_DIR/point.apk" | tr -d ' '),
  \"updated\": \"$DATE\",
  \"download_url\": \"/apps/point/download/point.apk\"
}
METAEOF'"
    echo "Pushed to registry: v$VERSION"
else
    echo "Registry container not found, skipped push"
fi

echo "Done: v$VERSION ($DATE)"
