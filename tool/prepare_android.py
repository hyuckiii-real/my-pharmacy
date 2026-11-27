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
if "xmlns:tools=" not in manifest:
    manifest = manifest.replace(
        "<manifest ",
        '<manifest xmlns:tools="http://schemas.android.com/tools" ',
        1,
    )

if "MlKitInitProvider" not in manifest:
    mlkit_provider = """        <provider
            android:name="com.google.mlkit.common.internal.MlKitInitProvider"
            android:authorities="${applicationId}.mlkitinitprovider"
            android:exported="false"
            android:initOrder="99"
            tools:node="merge" />
"""
    manifest = manifest.replace(
        "    </application>",
        mlkit_provider + "    </application>",
        1,
    )

if "MlKitComponentDiscoveryService" not in manifest:
    mlkit_discovery_service = """        <service
            android:name="com.google.mlkit.common.internal.MlKitComponentDiscoveryService"
            android:directBootAware="true"
            android:exported="false"
            tools:node="merge">
            <meta-data
                android:name="com.google.firebase.components:com.google.mlkit.common.internal.CommonComponentRegistrar"
                android:value="com.google.firebase.components.ComponentRegistrar" />
            <meta-data
                android:name="com.google.firebase.components:com.google.mlkit.vision.common.internal.VisionCommonRegistrar"
                android:value="com.google.firebase.components.ComponentRegistrar" />
            <meta-data
                android:name="com.google.firebase.components:com.google.mlkit.vision.text.internal.TextRegistrar"
                android:value="com.google.firebase.components.ComponentRegistrar" />
        </service>
"""
    manifest = manifest.replace(
        "    </application>",
        mlkit_discovery_service + "    </application>",
        1,
    )

# ML Kit's bundled recognizer also relies on Android component discovery.
# Keep the no-argument registrar constructors for R8 full mode builds.
data_transport = """        <service
            android:name="com.google.android.datatransport.runtime.backends.TransportBackendDiscovery"
            android:exported="false">
            <meta-data
                android:name="backend:com.google.android.datatransport.cct.CctBackendFactory"
                android:value="cct" />
        </service>
        <uses-library
            android:name="com.google.mlkit.text-recognition"
            android:required="false" />
"""
if "TransportBackendDiscovery" not in manifest:
    manifest = manifest.replace(
        "    </application>",
        data_transport + "    </application>",
        1,
    )
manifest_path.write_text(manifest, encoding="utf-8")

proguard_path = Path("android/app/proguard-rules.pro")
proguard_rules = """# ML Kit discovers these registrars reflectively. Preserve their public no-arg constructors.
-dontwarn com.google.firebase.components.Component$Instantiation
-dontwarn com.google.firebase.components.Component$ComponentType
-keep class * implements com.google.firebase.components.ComponentRegistrar { void <init>(); }
-keep,allowshrinking interface com.google.firebase.components.ComponentRegistrar
"""
proguard_path.write_text(proguard_rules, encoding="utf-8")

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

for script in ("chinese", "devanagari", "japanese", "korean"):
    dependency_name = f"com.google.mlkit:text-recognition-{script}:16.0.1"
    if dependency_name not in gradle and "dependencies {" in gradle:
        dependency = f'    implementation("{dependency_name}")\n'
        gradle = gradle.replace(
            "dependencies {",
            "dependencies {\n" + dependency,
            1,
        )

# Ensure release builds load the registrar keep rules when shrinking is enabled.
if "proguard-rules.pro" not in gradle:
    build_types_index = gradle.find("buildTypes {")
    release_index = gradle.find("release {", build_types_index)
    if build_types_index >= 0 and release_index >= 0:
        insert_at = release_index + len("release {")
        gradle = (
            gradle[:insert_at]
            + '\n            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
            + gradle[insert_at:]
        )
    else:
        print("Warning: could not attach ML Kit R8 rules to the release build type.")

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
