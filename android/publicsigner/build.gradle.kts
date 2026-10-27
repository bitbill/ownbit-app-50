plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

/*
 * The cold-wallet public protocol around the pinned engine (js/pubsigner-lib-bridge/signer.js, reached only through
 * :jsengine's PublicSignerJsBridge): the request / answer models, Ownbit's independent Kotlin checks before and after
 * the engine signs (PSBT, BC-UR, EVM / TRON / Solana payloads), the signed-outpoint memory, TronLink requests, and the
 * signing policy. No network code, no UI.
 */
android {
    namespace = "io.ownbit.core.publicsigner"
}

// The golden engine vectors are the iOS package's public-protocol fixtures (same bytes): served to the JVM tests as
// resources under pubsigner/ (TokenPocket's under pubsigner/tokenpocket/), without keeping a second copy here.
val fixtures = rootProject.layout.projectDirectory.dir("../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures")
val syncPublicProtocolFixtures = tasks.register<Sync>("syncPublicProtocolFixtures") {
    from(fixtures) {
        include("vectors.json", "native-vectors.json", "public-plan-vectors.json", "evm-public-ui.json", "keystone-tron-public.json", "engine_vocabulary.json")
        into("pubsigner")
    }
    from(fixtures) {
        include("tp-v1.json")
        into("pubsigner/tokenpocket")
    }
    into(layout.buildDirectory.dir("generated/fixtures"))
}
android.sourceSets.getByName("test").resources.srcDir(layout.buildDirectory.dir("generated/fixtures"))
tasks.matching { it.name.endsWith("UnitTestJavaRes") }.configureEach { dependsOn(syncPublicProtocolFixtures) }

dependencies {
    implementation(project(":common"))
    api(project(":jsengine"))
    // EvmTxCodec / TRON codecs (independent pre / post checks).
    api(project(":signing"))
    api(project(":vault"))
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockk)
}
