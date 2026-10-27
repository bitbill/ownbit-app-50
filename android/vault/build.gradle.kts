plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

/*
 * Key storage: the OBV2 vault format (scrypt + AES-256-GCM, device binding through an Android Keystore HMAC key), the
 * wallet secret vault on top of it, and biometric quick send (an auth-per-use Class 3 Keystore key that wraps the wallet
 * password).
 */
android {
    namespace = "io.ownbit.core.vault"
}

dependencies {
    implementation(project(":common"))
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.serialization.json)
    api(libs.bouncycastle)
    // BiometricManager (capability detection); the prompt itself belongs to the host app's UI.
    implementation(libs.androidx.biometric)
    // libsodium.so (all ABIs) for native scrypt, bound through JNA (SodiumScryptEngine); lazysodium's Java API is unused.
    implementation(libs.lazysodium.android) { exclude(group = "net.java.dev.jna") }
    implementation(libs.jna) { artifact { type = "aar" } }

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.mockk)

    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.kotlinx.coroutines.test)
}
