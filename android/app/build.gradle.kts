import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Release signing: nothing secret lives in git. Values come from environment variables
// (CLASSDAY_KEYSTORE_FILE / CLASSDAY_STORE_PASSWORD / CLASSDAY_KEY_ALIAS / CLASSDAY_KEY_PASSWORD),
// falling back to a local-only, git-ignored android/keystore/signing.properties
// (keys: storeFile, storePassword, keyAlias, keyPassword). Without either, release stays unsigned.
val localSigning = Properties().apply {
    val f = rootProject.file("keystore/signing.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(env: String, key: String): String =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: localSigning.getProperty(key, "").trim()
val keystoreFile = signingValue("CLASSDAY_KEYSTORE_FILE", "storeFile")
    .let { if (it.isBlank()) rootProject.file("keystore/release.jks") else file(it) }
val keystorePassword = signingValue("CLASSDAY_STORE_PASSWORD", "storePassword")
val keyAliasName = signingValue("CLASSDAY_KEY_ALIAS", "keyAlias").ifBlank { "classday" }
val keyPasswordValue = signingValue("CLASSDAY_KEY_PASSWORD", "keyPassword").ifBlank { keystorePassword }
val canSignRelease = keystoreFile.exists() && keystorePassword.isNotBlank()

android {
    namespace = "com.classday.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.classday.app"
        minSdk = 26
        targetSdk = 37
        versionCode = 21005
        versionName = "2.10.5"
        vectorDrawables.useSupportLibrary = true
        // 只发给真机：x86/x86_64 只为模拟器编译，却各带一份 10MB 的 ML Kit OCR .so。
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            if (canSignRelease) {
                storeFile = keystoreFile
                storePassword = keystorePassword
                keyAlias = keyAliasName
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // 2.9.7：开启 R8 与资源裁剪。此前四个 dex 解压 52 MiB，是包体的另一半。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (canSignRelease) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "/META-INF/DEPENDENCIES"
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = false
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    // 只用 Icons.AutoMirrored.Filled.ArrowBack 与 Icons.Filled.Add，两者都在 icons-core 里；
    // 2.9.7 用 icons-core 取代了 material-icons-extended（整包图标集，dex 里最大的一块依赖）。
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.glance:glance-material3:1.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.zxing:core:3.5.3")
    // 2.9.7：browser 与 security-crypto 只被已下线的 Fénix 登录用到，随它一起移除。

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
