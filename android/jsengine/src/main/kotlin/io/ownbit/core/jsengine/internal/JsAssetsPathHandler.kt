// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.internal

import android.content.Context
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import java.io.ByteArrayInputStream
import java.io.IOException

/**
 * Serves `assets/js/<path>` for `https://appassets.androidplatform.net/js/<path>` and nothing else.
 *
 * Unlike the stock `AssetsPathHandler` it pins the charset to UTF-8 (the bundles embed the non-ASCII
 * BIP39 word lists), refuses path traversal, and answers 404 instead of `null` so a missing asset can
 * never fall through to the network.
 */
internal class JsAssetsPathHandler(context: Context) : WebViewAssetLoader.PathHandler {

    private val assets = context.applicationContext.assets

    override fun handle(path: String): WebResourceResponse {
        if (!isSafe(path)) return notFound()
        val mimeType = mimeTypeOf(path) ?: return notFound()
        return try {
            WebResourceResponse(mimeType, UTF_8, assets.open("$ASSET_ROOT/$path"))
        } catch (e: IOException) {
            notFound()
        }
    }

    internal companion object {
        const val ASSET_ROOT = "js"
        private const val UTF_8 = "utf-8"

        fun isSafe(path: String): Boolean =
            path.isNotEmpty() &&
                !path.startsWith("/") &&
                !path.contains('\\') &&
                path.split('/').none { it.isEmpty() || it == "." || it == ".." }

        fun mimeTypeOf(path: String): String? = when (path.substringAfterLast('.', "").lowercase()) {
            "html" -> "text/html"
            "js" -> "text/javascript"
            "json" -> "application/json"
            "wasm" -> "application/wasm"
            else -> null
        }

        fun notFound(): WebResourceResponse = WebResourceResponse(
            "text/plain",
            UTF_8,
            404,
            "Not Found",
            emptyMap(),
            ByteArrayInputStream(ByteArray(0)),
        )
    }
}
