import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clave con la que se firma, si la hay. No está en el repositorio: la pone quien compila, en
// android/key.properties o —en CI— desde un secreto. Sin ella se firma con la de depuración, que
// Gradle se inventa nueva en cada máquina.
val clavePropiedades = Properties()
val clave = rootProject.file("key.properties")
if (clave.exists()) {
    clave.inputStream().use { clavePropiedades.load(it) }
}

android {
    namespace = "es.warorgan.warorgan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "es.warorgan.warorgan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (clavePropiedades.containsKey("storeFile")) {
            create("propia") {
                storeFile = file(clavePropiedades["storeFile"] as String)
                storePassword = clavePropiedades["storePassword"] as String
                keyAlias = clavePropiedades["keyAlias"] as String
                keyPassword = clavePropiedades["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Con clave propia si la hay. Sin ella, Gradle firma con una de depuración que se
            // genera nueva en cada máquina: dos compilaciones firman distinto y Android se niega a
            // instalar la segunda encima de la primera («conflicto con un paquete»), obligando a
            // desinstalar y perdiendo las listas guardadas.
            signingConfig = if (clavePropiedades.containsKey("storeFile")) {
                signingConfigs.getByName("propia")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
