from pathlib import Path
import shutil, sys

root = Path(sys.argv[1]).resolve()
java_source = Path(sys.argv[2]).resolve()
manifest_path = root / "platform/app/src/main/AndroidManifest.xml"
gradle_path = root / "platform/app/build.gradle"
java_dest = root / "platform/app/src/main/java/com/maniscat2/sm64coopdx/RomPickerActivity.java"

for p in (manifest_path, gradle_path, java_source):
    if not p.is_file():
        raise SystemExit(f"Missing required file: {p}")

java_dest.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(java_source, java_dest)

manifest = manifest_path.read_text(encoding="utf-8")
manifest = manifest.replace('    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />\n', '')
manifest = manifest.replace('    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />\n', '')
manifest = manifest.replace('        android:requestLegacyExternalStorage="true"\n', '')

launcher = '''        <activity
            android:name=".RomPickerActivity"
            android:label="Mario 64 – Sélection de ROM"
            android:exported="true"
            android:screenOrientation="userLandscape"
            android:theme="@android:style/Theme.Material.NoActionBar.Fullscreen">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
        </activity>

'''
marker = '        <!-- Example of setting SDL hints from AndroidManifest.xml:'
if '.RomPickerActivity' not in manifest:
    if marker not in manifest:
        raise SystemExit('Manifest insertion marker not found')
    manifest = manifest.replace(marker, launcher + marker, 1)

activity_start = manifest.find('        <activity android:name="sm64coopdxActivity"')
if activity_start < 0:
    raise SystemExit('SDL activity not found')
activity_end = manifest.find('        </activity>', activity_start)
if activity_end < 0:
    raise SystemExit('SDL activity end not found')
activity_end += len('        </activity>')
block = manifest[activity_start:activity_end]
block = block.replace('            android:exported="true"\n', '            android:exported="false"\n', 1)
old_filter = '''            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
            </intent-filter>
'''
block = block.replace(old_filter, '', 1)
manifest = manifest[:activity_start] + block + manifest[activity_end:]
manifest_path.write_text(manifest, encoding='utf-8')

gradle = gradle_path.read_text(encoding='utf-8')
gradle = gradle.replace('versionCode 42', 'versionCode 43')
gradle = gradle.replace('versionName "1.5.1"', 'versionName "1.5.1-rompicker"')
gradle_path.write_text(gradle, encoding='utf-8')
print('ROM picker patch applied')
