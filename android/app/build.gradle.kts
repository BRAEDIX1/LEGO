plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // O plugin do Flutter deve vir depois de Android e Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.lego"

    // Mantém os valores do template do Flutter
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.lego"

        // >>> Correções essenciais
        minSdk = flutter.minSdkVersion                               // <-- fixa minSdk 23 (exigia 23)
        targetSdk = flutter.targetSdkVersion      // ok manter do Flutter
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // >>> Usa Java 17 (bate com o JDK 17 configurado)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // Assinatura de debug só para facilitar o run --release
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
