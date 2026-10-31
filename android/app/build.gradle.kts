plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cnefan.ds_bar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.cnefan.ds_bar"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    buildTypes {
        release {
            // 正式发布请替换为自己的签名配置；当前沿用 debug 签名以便本地安装。
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.work:work-runtime:2.10.5")

    testImplementation("junit:junit:4.13.2")
    // JVM 单测里替代 Android 的 org.json 桩实现。
    testImplementation("org.json:json:20240303")
    // 真实 inflate 通知布局，把「布局能否被 RemoteViews 加载」变成可回归的测试。
    testImplementation("org.robolectric:robolectric:4.11.1")
    testImplementation("androidx.test:core:1.6.1")
}

// Robolectric 需要 includeAndroidResources，而它会与 Flutter 的资产合并任务
// 产生隐式依赖冲突（Gradle 9 会直接报错）。显式声明依赖即可。
tasks.matching { it.name.startsWith("package") && it.name.contains("UnitTestForUnitTest") }
    .configureEach {
        dependsOn(tasks.matching { it.name.startsWith("copyFlutterAssets") })
    }
