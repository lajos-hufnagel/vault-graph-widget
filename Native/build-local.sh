#!/bin/sh
set -eu
native_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$native_dir/LocalBuild"
/usr/bin/python3 - "$native_dir/LocalBuild/Widget.entitlements" "$native_dir/LocalBuild/vaults.json" "$@" <<'CONFIG'
import json, plistlib, sys
from pathlib import Path
if len(sys.argv) > 3:
    paths = [Path(value).expanduser().resolve() for value in sys.argv[3:]]
else:
    registry = Path.home() / 'Library/Application Support/obsidian/obsidian.json'
    registered = json.loads(registry.read_text()).get('vaults', {}) if registry.exists() else {}
    paths = [Path(v['path']).resolve() for v in registered.values() if 'path' in v]
paths = list(dict.fromkeys(str(p) for p in paths if p.is_dir()))
root = Path.home() / 'Library/Mobile Documents/iCloud~md~obsidian/Documents'
roots = [str(root.resolve())] if root.is_dir() and len(sys.argv) == 3 else []
registry_path = str(Path.home() / 'Library/Application Support/obsidian/obsidian.json')
if not paths: raise SystemExit('Kein Vault gefunden. Vault-Pfade als Argumente angeben.')
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'com.apple.security.app-sandbox': True,
                  'com.apple.security.temporary-exception.files.absolute-path.read-only': [p + '/' for p in dict.fromkeys(paths + roots)] + [registry_path]}, f)
Path(sys.argv[2]).write_text(json.dumps({'VaultGraphVaultPaths': paths, 'VaultGraphVaultRoots': roots, 'VaultGraphRegistryPath': registry_path}))
CONFIG
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "$native_dir/VaultGraph.xcodeproj" -scheme VaultGraph -configuration Debug -derivedDataPath "$native_dir/LocalBuild" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS="$native_dir/LocalBuild/Widget.entitlements" SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG LOCAL_WIDGET' CURRENT_PROJECT_VERSION=17 MARKETING_VERSION=0.17 ENABLE_DEBUG_DYLIB=NO build
app_path="$native_dir/LocalBuild/Build/Products/Debug/VaultGraph.app"
widget_path="$app_path/Contents/PlugIns/VaultGraphWidget.appex"
/usr/bin/python3 - "$widget_path/Contents/Info.plist" "$app_path/Contents/Info.plist" "$native_dir/LocalBuild/vaults.json" <<'CONFIG'
import json, plistlib, sys
from pathlib import Path
for filename, extra in [(sys.argv[1], json.loads(Path(sys.argv[3]).read_text())), (sys.argv[2], {'LSUIElement': True})]:
    with open(filename, 'rb') as f: data = plistlib.load(f)
    data.pop("VaultGraphVaultPath", None)
    data.update(extra)
    with open(filename, 'wb') as f: plistlib.dump(data, f)
CONFIG
/usr/bin/codesign --force --sign - --entitlements "$native_dir/LocalBuild/Widget.entitlements" "$widget_path"
/usr/bin/codesign --force --sign - "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
