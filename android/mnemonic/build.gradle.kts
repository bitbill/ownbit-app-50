plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

/*
 * Mnemonic generation and validation, BIP39 passphrase rules, and the key part of creating an HD wallet (seed, public
 * keys, sealed envelopes). The BIP39 word lists are the published js/bitcoinjs-lib-bridge/mnemonic_words.txt, packaged
 * as the asset bip39/mnemonic_words.txt at build time (no copy is kept in this module).
 */
android {
    namespace = "io.ownbit.core.mnemonic"
}

/** Copies the published word-list file into a generated assets directory (`bip39/mnemonic_words.txt`). */
abstract class CopyBip39Wordlists : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val wordlists: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val dir = outputDir.get().dir("bip39").asFile
        dir.mkdirs()
        wordlists.get().asFile.copyTo(File(dir, "mnemonic_words.txt"), overwrite = true)
    }
}

val copyBip39Wordlists = tasks.register<CopyBip39Wordlists>("copyBip39Wordlists") {
    wordlists.set(rootProject.layout.projectDirectory.file("../js/bitcoinjs-lib-bridge/mnemonic_words.txt"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copyBip39Wordlists, CopyBip39Wordlists::outputDir)
    }
}

dependencies {
    implementation(project(":common"))
    api(project(":jsengine"))
    api(project(":vault"))
    api(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.kotlinx.serialization.json)
}
