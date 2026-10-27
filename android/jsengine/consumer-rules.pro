# :jsengine needs no keep rules: no addJavascriptInterface / @JavascriptInterface, no reflection, no
# @Serializable classes (the wire protocol is parsed as JsonElement). Results come back through
# WebViewCompat.addWebMessageListener: Chromium calls androidx.webkit's WebMessageListenerAdapter through the
# org.chromium.support_lib_boundary interfaces, which androidx.webkit's own consumer rules keep; our listener is a
# plain Kotlin lambda called by that adapter. The JS bundles live in assets/js/ and are never touched by R8.
