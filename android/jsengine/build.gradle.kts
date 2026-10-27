plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

/*
 * The JavaScript engine (one hidden, hardened System WebView page per bundle; arguments always as JSON data) and the
 * typed chain bridges: mnemonic generation and validation, key / address derivation, message signing, and the
 * public-protocol signer. The bundles themselves are the files in ../js (see README.md for the asset layout).
 */
android {
    namespace = "io.ownbit.core.jsengine"
}

dependencies {
    implementation(project(":common"))
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.serialization.json)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.lifecycle.process)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    // WebViewJsEngine request / callback correlation on the JVM (the WebView and androidx.webkit statics are mocked).
    testImplementation(libs.mockk)
}
