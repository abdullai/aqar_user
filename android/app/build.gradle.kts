plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // ✅ إضافة إضافة خدمات جوجل (Firebase)
    id("com.google.gms.google-services") 
}

android {
    namespace = "com.example.aqar_user"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // تفعيل ميزة Desugaring لحل مشكلة التنبيهات
        isCoreLibraryDesugaringEnabled = true
        
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.aqar_user"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // تفعيل MultiDex لدعم المكتبات الكبيرة
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // ملاحظة: تأكد من إعداد توقيع النسخة النهائية لاحقاً
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ إضافة مكتبات Firebase الأساسية
    // استخدام الـ BoM يضمن توافق الإصدارات تلقائياً
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")

    // إضافة المكتبة المطلوبة لعمل الـ Desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}