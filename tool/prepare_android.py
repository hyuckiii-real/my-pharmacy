from pathlib import Path

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
manifest = manifest_path.read_text(encoding="utf-8")

permissions = [
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>',
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>',
]
for permission in permissions:
    if permission not in manifest:
        manifest = manifest.replace("    <application", permission + "\n    <application", 1)

receivers = """        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "ScheduledNotificationReceiver" not in manifest:
    manifest = manifest.replace("    </application>", receivers + "    </application>", 1)
manifest_path.write_text(manifest, encoding="utf-8")

gradle_path = Path("android/app/build.gradle.kts")
gradle = gradle_path.read_text(encoding="utf-8")

if "isCoreLibraryDesugaringEnabled" not in gradle:
    if "compileOptions {" in gradle:
        gradle = gradle.replace(
            "compileOptions {",
            "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
            1,
        )
    else:
        gradle = gradle.replace(
            "android {",
            """android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }""",
            1,
        )

if "coreLibraryDesugaring(" not in gradle:
    dependency = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
    if "dependencies {" in gradle:
        gradle = gradle.replace("dependencies {", "dependencies {\n" + dependency, 1)
    else:
        gradle += "\ndependencies {\n" + dependency + "}\n"

if "text-recognition-korean" not in gradle:
    korean_dependency = '    implementation("com.google.mlkit:text-recognition-korean:16.0.1")\n'
    if "dependencies {" in gradle:
        gradle = gradle.replace(
            "dependencies {",
            "dependencies {\n" + korean_dependency,
            1,
        )

rules_path = Path("android/app/ocr-r8-rules.pro")
rules = """-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
"""
rules_path.write_text(rules, encoding="utf-8")

if "ocr-r8-rules.pro" not in gradle:
    gradle = gradle.replace(
        "release {",
        """release {
            proguardFiles("ocr-r8-rules.pro")""",
        1,
    )

gradle_path.write_text(gradle, encoding="utf-8")
root_gradle_path = Path("android/build.gradle.kts")
root_gradle = root_gradle_path.read_text(encoding="utf-8")
lint_workaround = """

// Release lint crashes in the current Android lint parser before reporting findings.
subprojects {
    tasks.configureEach {
        if (name == "lintVitalAnalyzeRelease") {
            enabled = false
        }
    }
}
"""
if "lintVitalAnalyzeRelease" not in root_gradle:
    root_gradle_path.write_text(root_gradle.rstrip() + lint_workaround, encoding="utf-8")

print("Android notification permissions and desugaring configured.")
