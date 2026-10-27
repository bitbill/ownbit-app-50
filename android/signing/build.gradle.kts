plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

/*
 * Transaction signing through the JS bundles (UTXO chains, EVM, TRON, SOL, TON, XRP, XLM, FIL, STX, ADA, multisig) and
 * the native checks around it: strict reading of what a UTXO bundle signs, verification of the signed UTXO transaction,
 * EVM / TRON transaction codecs and the TRON pre-sign verifier. No fee / UTXO / nonce fetching, no broadcasting.
 */
android {
    namespace = "io.ownbit.core.signing"
}

dependencies {
    api(project(":jsengine"))
    // UnlockedSecrets (signing keys come from WalletSecretAccess.withUnlocked) and the hash helpers.
    api(project(":vault"))
    api(libs.kotlinx.serialization.json)
    api(libs.bouncycastle)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockk)
}
