// Ownbit core (Android) — shared configuration of the library modules.
// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            compileSdk = 36
            defaultConfig {
                minSdk = 26
                testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
                consumerProguardFiles("consumer-rules.pro")
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            packaging {
                resources {
                    // Duplicate metadata of BouncyCastle and other jars in the instrumented-test APKs.
                    excludes += setOf(
                        "/META-INF/{AL2.0,LGPL2.1}",
                        "/META-INF/INDEX.LIST",
                        "/META-INF/DEPENDENCIES",
                        "/META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                    )
                }
            }
            testOptions {
                unitTests.isIncludeAndroidResources = true
                unitTests.isReturnDefaultValues = true
            }
            lint {
                abortOnError = true
                // Library modules: these checks are about app packaging / translations, not about this code.
                disable += setOf("GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
            }
        }
    }
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
            freeCompilerArgs.add("-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi")
        }
    }
    tasks.withType<Test>().configureEach {
        // MockK's inline agent attaches in-process (JDK 21).
        jvmArgs("-Djdk.attach.allowAttachSelf=true", "-XX:+EnableDynamicAgentLoading")
    }
}
