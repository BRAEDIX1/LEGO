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

    // >>> 3C (D13): dois ambientes no mesmo código.
    // prod    = app oficial, igual ao de sempre (com.example.lego, "lego").
    // homolog = app de TESTE (com.example.lego.teste, "LEGO TESTE"), que convive
    //           com o oficial no mesmo aparelho e fala só com o projeto lego-teste
    //           (google-services.json em src/homolog/).
    // O sabor não pode se chamar "teste": o AGP proíbe nomes que começam com
    // "test" (B59). O pacote e o projeto continuam ".teste" / "lego-teste".
    // Sem versionNameSuffix: a versão precisa continuar X.Y.Z (3B).
    flavorDimensions += "ambiente"
    productFlavors {
        create("prod") {
            dimension = "ambiente"
            resValue("string", "app_name", "lego")
        }
        create("homolog") {
            dimension = "ambiente"
            applicationIdSuffix = ".teste"
            resValue("string", "app_name", "LEGO TESTE")
        }
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
