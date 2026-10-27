// Ownbit core (Android): mnemonic generation, key storage, key derivation and signing.
// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ownbit-core-android"

include(":common")
include(":vault")
include(":jsengine")
include(":mnemonic")
include(":signing")
include(":publicsigner")
