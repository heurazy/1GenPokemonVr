-- Quest packaging regressions: the standalone build must not alter the
-- checked-in Android defaults, and its activity must replace the phone
-- launch surface instead of inheriting duplicate launcher/USB filters.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local script = read("scripts/build-quest.ps1")
T.check(script:find("[IO.File]::WriteAllText($props", 1, true) == nil,
        "Quest build does not rewrite gradle.properties")
T.check(script:find("$propsText", 1, true) == nil,
        "Quest build has no mutable gradle.properties staging copy")
T.check(script:find('"-Papp.name=1GenPokemonVR Quest"', 1, true) ~= nil,
        "Quest name is passed as an isolated Gradle project property")
T.check(script:find('"-Papp.version_name=$Version"', 1, true) ~= nil,
        "Quest version is passed as an isolated Gradle project property")
T.check(script:find('"-Papp.version_code=$code"', 1, true) ~= nil,
        "Quest version code is passed as an isolated Gradle project property")

local manifest = read("mobile/android/app/src/quest/AndroidManifest.xml")
T.check(manifest:find('tools:node="replace"', 1, true) ~= nil,
        "Quest GameActivity replaces the inherited phone activity")
T.check(manifest:find('android:exported="true"', 1, true) ~= nil,
        "replacement Quest activity remains exported")
T.check(manifest:find('android:configChanges=', 1, true) ~= nil,
        "replacement Quest activity keeps LOVE configChanges")
T.check(manifest:find('android:theme="@android:style/Theme.NoTitleBar.Fullscreen"', 1, true) ~= nil,
        "replacement Quest activity keeps the fullscreen LOVE theme")
T.check(manifest:find('tv.ouya.intent.category.GAME', 1, true) == nil,
        "Quest overlay does not publish the inherited OUYA launcher")
T.check(manifest:find('android.hardware.usb.action.USB_DEVICE_ATTACHED', 1, true) == nil,
        "Quest overlay does not publish the inherited USB launch filter")
T.check(manifest:find('tools:replace="android:glEsVersion,android:required"', 1, true) == nil,
        "Quest GLES declaration avoids a no-op manifest replacement marker")

local androidScript = read("scripts/build_android.sh")
T.check(androidScript:find("apply_android_branding", 1, true) == nil,
        "Android build does not rewrite tracked branding files")
T.check(androidScript:find('"-Papp.name=$APP_NAME"', 1, true) ~= nil,
        "Android name is passed as an isolated Gradle project property")
T.check(androidScript:find('"-Papp.application_id=$APPLICATION_ID"', 1, true) ~= nil,
        "Android application id is passed as an isolated Gradle project property")
T.check(androidScript:find('"-Papp.orientation=fullUser"', 1, true) ~= nil,
        "Android orientation is passed as an isolated Gradle project property")
T.check(androidScript:find('"-Papp.version_name=$VERSION"', 1, true) ~= nil,
        "Android release version is passed as an isolated Gradle project property")
T.check(androidScript:find('"-Papp.version_code=$VERSION_CODE"', 1, true) ~= nil,
        "Android release code is passed as an isolated Gradle project property")

local androidManifest = read("mobile/android/app/src/main/AndroidManifest.xml")
T.check(androidManifest:find('android.permission.INTERNET', 1, true) ~= nil,
        "Android package keeps network access for link play")

local properties = read("mobile/android/gradle.properties")
T.check(properties:find("app.name=1GenPokemonVR Quest", 1, true) == nil,
        "checked-in Android defaults are not contaminated by Quest branding")

T.finish("quest_packaging")
