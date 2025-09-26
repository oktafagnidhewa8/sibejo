plugins {
    id("com.android.application")
    id("com.google.gms.google-services") // FlutterFire
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

/* ====== IMPORT JAVA TYPES ====== */
import java.util.Properties
import java.io.FileInputStream

/* ====== LOAD key.properties (jika ada) ====== */
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { fis ->
            this.load(fis) // <-- pakai this.load supaya jelas referensinya
        }
    }
}

android {
    namespace = "id.sibejo.sibejo_rescue"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Disarankan untuk Flutter terbaru
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "id.sibejo.sibejo_rescue"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword") ?: ""
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false   // ⬅️ matikan
        }
    }
}

flutter {
    source = "../.."
}
