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

if "text-recognition-chinese" not in gradle:
    chinese_dependency = '    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")\n'
    if "dependencies {" in gradle:
        gradle = gradle.replace(
            "dependencies {",
            "dependencies {\n" + chinese_dependency,
            1,
        )

gradle_path.write_text(gradle, encoding="utf-8")
print("Android notification permissions and desugaring configured.")
