// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import io.ownbit.core.jsengine.bridge.JsBridge
import io.ownbit.core.jsengine.internal.JsProtocol
import kotlinx.serialization.json.JsonArray
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.lang.reflect.Modifier
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Strings from a dApp, a QR code, a server or the user reach a JS bundle only as **data** ([JsArgs], `JSON.parse`d by
 * the host shim) and never become JS source. (Splicing such strings into JS source would let a crafted message rewrite
 * the resident bridge, or turn a `personal_sign` of `\x30\x78…` into a blind hash signature.) This source scan keeps it
 * that way. It reads the Kotlin / Java `src/main` sources of every module of this project:
 *
 * 1. `evaluateJavascript(` is called once, in `WebViewJsEngine.kt`, with the statement of [JsProtocol.invokeScript]
 *    (function path validated, the request JSON embedded only as an escaped string literal);
 * 2. no `javascript:` URL and no `addJavascriptInterface(` anywhere;
 * 3. [JsBridge.encodeMessageForJs] is unchanged and `EthereumJsBridge` applies it in both message functions (keep it:
 *    the signed bytes equal iOS);
 * 4. every engine call (`.call(` / `.callForEvent(`) passes a plain function path (identifier segments; `$name`
 *    templates of internal names only) and its arguments as `JsArgs.of(…)`, `JsArgs.NONE` or a `JsonArray` value;
 * 5. string literals that look like JS (`bridge.` / `window.` / `__ownbitHost`) are plain function paths, except the
 *    one invoke prefix in `JsProtocol.kt`;
 * 6. `XlmJsSigner`, `AdaJsSigner`, `XrpJsSigner` (addresses, memos, seeds, tx / UTXO JSON) call their bundle only with
 *    `JsArgs.of(…)` and interpolate nothing but the enum function-name suffix;
 * 7. [JsEngine] has no API that takes JS source;
 * 8. public protocol: `JsBundle.PUBLIC_SIGNER` / `PUBLIC_SIGNER_PAIRING` are named only by `PublicSignerJsBridge.kt`
 *    (plus their declaration and `PublicSignerException`'s default page label); the bridge makes exactly one engine
 *    call, to the literal `"BitSignerEngine.dispatch"` with `JsArgs.of(<request>)`; `"operation"` is only ever
 *    `PublicSignerOp.wire`, the wire names live only in `PublicSignerOp.kt`, and the engine operations outside the
 *    allowlist are named nowhere; `seed` is put only by `derivePublicIndex` / `signPlanTask`; every pairing export sends
 *    `deviceName` = `"Ownbit"`.
 *
 * The scanner itself is checked against small samples (comments, raw strings, templates) so it cannot pass vacuously.
 */
class JsCallSiteGuardTest {

    private val root: File? = generateSequence(File("").absoluteFile) { it.parentFile }
        .firstOrNull { File(it, "settings.gradle.kts").isFile && File(it, "jsengine").isDirectory }

    private val sources: List<KtSource> by lazy {
        val repo = root ?: return@lazy emptyList()
        val dirs = repo.listFiles().orEmpty().filter { File(it, "build.gradle.kts").isFile }.map { File(it, "src/main") }
        dirs.filter { it.isDirectory }.flatMap { dir ->
            dir.walkTopDown()
                .onEnter { it.name != "build" }
                .filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                .map { KtSource(it.relativeTo(repo).invariantSeparatorsPath, it.readText()) }
                .toList()
        }
    }

    private fun repoSources(): List<KtSource> {
        assumeTrue("repository sources not found above ${File("").absolutePath}", root != null)
        assertTrue(sources.size > 80, "only ${sources.size} main sources found — did the layout change?")
        return sources
    }

    private fun source(path: String): KtSource =
        repoSources().singleOrNull { it.path == path } ?: throw AssertionError("$path not found")

    @Test
    fun `evaluateJavascript is called only by WebViewJsEngine, with the escaped invoke statement`() {
        val calls = repoSources().flatMap { src -> src.codeMatches(EVALUATE).map { "${src.path}:${src.line(it.range.first)}" } }
        assertEquals(1, calls.size, "evaluateJavascript( call sites: $calls")
        assertTrue(calls.single().startsWith("$WEBVIEW_ENGINE:"), calls.single())

        val engine = source(WEBVIEW_ENGINE)
        assertTrue(engine.flatCode.contains("view.evaluateJavascript(script)"), "WebViewJsEngine must evaluate the invoke statement only")
        assertEquals(1, Regex("""\bval script = JsProtocol\.invokeScript\(id, function, args\)""").findAll(engine.flatCode).count())
        val protocol = source(JS_PROTOCOL)
        assertTrue(protocol.flatCode.contains("require(isValidFunctionPath(function))"))
        assertTrue(protocol.flatCode.contains("return \"window.__ownbitHost.invoke(\" + jsStringLiteral(request) + \");0\""))
        // What rule 4 relies on: a function path can never carry code, it is refused before any script exists.
        for (path in listOf("bridge.f('x')", "bridge.f;evil()", "bridge.f x", "bridge['f']", "bridge.__proto__.f", "")) {
            assertFailsWith<IllegalArgumentException>(path) { JsProtocol.invokeScript(1, path, JsArgs.NONE) }
        }
    }

    @Test
    fun `no javascript URL and no JavaScript interface anywhere`() {
        val findings = repoSources().flatMap { src ->
            src.codeMatches(JS_INTERFACE).map { "${src.path}:${src.line(it.range.first)} addJavascriptInterface" } +
                src.literals.filter { it.constant.contains("javascript:", ignoreCase = true) }
                    .map { "${src.path}:${src.line(it.start)} \"javascript:\" literal" }
        }
        assertTrue(findings.isEmpty(), findings.joinToString("\n"))
    }

    @Test
    fun `encodeMessageForJs is kept unchanged and used by both EthereumJsBridge message functions`() {
        val bridge = source("jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/JsBridge.kt")
        assertTrue(
            bridge.flatCode.contains(
                """fun encodeMessageForJs(message: String): String = message.replace("\"", "_QUOTE_OWNBIT_").replace("\n", "_NEWLINE_OWNBIT_")""",
            ),
            "encodeMessageForJs changed (keep it, iOS signs the same bytes)",
        )
        assertEquals("a_QUOTE_OWNBIT_b_NEWLINE_OWNBIT_c \\x30\\x78 \r '", JsBridge.encodeMessageForJs("a\"b\nc \\x30\\x78 \r '"))

        val ethereum = source("jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/EthereumJsBridge.kt")
        for ((function, bundleFunction) in listOf("signMessage" to "signEthereumMessage", "recoverMessageSigner" to "getMessageSignAddress")) {
            val body = ethereum.functionText(function)
            assertTrue(body.contains("\"$bundleFunction\", encodeMessageForJs(message)"), "$function: $body")
        }
    }

    @Test
    fun `every bundle call passes a plain function path and JsArgs data`() {
        val sites = repoSources().filter { it.usesJsEngine }.flatMap { it.engineCalls() }
        assertTrue(sites.size >= 30, "only ${sites.size} engine call sites found — did the scanner break?")
        val violations = sites.mapNotNull { site -> site.violation()?.let { "${site.where}: $it\n    ${site.text}" } }
        assertTrue(violations.isEmpty(), "JS calls must pass data only through JsArgs:\n" + violations.joinToString("\n"))
    }

    @Test
    fun `string literals that look like JS are plain function paths`() {
        val findings = repoSources().filter { it.path != JS_PROTOCOL }.flatMap { src ->
            src.literals.filter { JS_LOOKING.containsMatchIn(it.constant) && !it.isFunctionPath() }
                .map { "${src.path}:${src.line(it.start)} ${src.text.substring(it.start, it.end)}" }
        }
        assertTrue(findings.isEmpty(), "JS source built in Kotlin (use JsArgs):\n" + findings.joinToString("\n"))
        // The single place a statement is composed.
        assertEquals(
            listOf("window.__ownbitHost.invoke(", ");0"),
            source(JS_PROTOCOL).literals.map { it.constant }.filter { it.contains("window.") || it == ");0" },
        )
    }

    @Test
    fun `XLM, ADA and XRP signers pass every value through JsArgs`() {
        val expected = mapOf(
            "signing/src/main/kotlin/io/ownbit/core/chain/xlm/XlmJsSigner.kt" to 3,
            "signing/src/main/kotlin/io/ownbit/core/chain/ada/AdaJsSigner.kt" to 1,
            "signing/src/main/kotlin/io/ownbit/core/chain/xrp/XrpJsSigner.kt" to 3,
        )
        for ((path, minCalls) in expected) {
            val src = source(path)
            val calls = src.engineCalls()
            assertTrue(calls.size >= minCalls, "$path: ${calls.size} engine calls")
            for (call in calls) {
                assertTrue(call.args.getOrNull(1)?.startsWith("JsArgs.of(") == true, "${call.where}: arguments not via JsArgs.of: ${call.text}")
                assertTrue('$' !in call.args[0], "${call.where}: interpolated function path: ${call.text}")
            }
            // No value is ever spliced into a string: the only template is the XLM enum function-name suffix.
            val templates = src.literals.flatMap { it.templates }.toSet()
            assertTrue(templates.all { it == "type.jsSuffix" }, "$path interpolates $templates")
        }
    }

    @Test
    fun `rule 8 - only PublicSignerJsBridge reaches the public signer pages`() {
        val references = repoSources().filter { it.path != JS_BUNDLE }.flatMap { src ->
            src.codeMatches(PUBLIC_SIGNER_ENTRY).map { "${src.path}:${src.line(it.range.first)}" }
        }
        val outsideBridge = references.filterNot { it.startsWith("$PUBLIC_SIGNER_BRIDGE:") }
        assertTrue(references.any { it.startsWith("$PUBLIC_SIGNER_BRIDGE:") }, "the bridge must name its pages")
        assertTrue(
            outsideBridge.all { it.startsWith("$PUBLIC_SIGNER_EXCEPTION:") },
            "JsBundle.PUBLIC_SIGNER* outside PublicSignerJsBridge.kt:\n" + outsideBridge.joinToString("\n"),
        )
        // The exception only uses it as the default page label of a refusal.
        val exception = source(PUBLIC_SIGNER_EXCEPTION)
        assertEquals(1, exception.codeMatches(PUBLIC_SIGNER_ENTRY).count())
        assertTrue(exception.flatCode.contains("override val bundle: JsBundle = JsBundle.PUBLIC_SIGNER,"))

        // No other way to name the pages or the engine: the asset id, the enum names and the engine global as literals.
        val literals = repoSources().flatMap { src -> src.literals.map { src.path to it.constant } }
        val engineNames = literals.filter { (_, c) -> c.startsWith("BitSignerEngine") || c == "pubsigner" || c.startsWith("PUBLIC_SIGNER") }
        assertEquals(
            setOf(
                JS_BUNDLE to "pubsigner",
                JS_BUNDLE to "BitSignerEngine",
                PUBLIC_SIGNER_BRIDGE to "BitSignerEngine.dispatch",
            ),
            engineNames.toSet(),
            "engine / page names as string literals",
        )
    }

    @Test
    fun `rule 8 - the bridge calls only BitSignerEngine dispatch with an allow-listed operation`() {
        val bridge = source(PUBLIC_SIGNER_BRIDGE)
        val calls = bridge.engineCalls()
        assertEquals(1, calls.size, "engine calls in the bridge: ${calls.map { it.text }}")
        val call = calls.single()
        assertEquals(listOf("\"BitSignerEngine.dispatch\"", "JsArgs.of(json)"), call.args, call.text)
        assertTrue(bridge.code.contains(".call(") && !bridge.code.contains(".callForEvent("))
        // The request: {"operation": op.wire, …} built from the enum; nothing else names an operation.
        assertTrue(bridge.flatCode.contains("private suspend fun dispatch(bundle: JsBundle, op: PublicSignerOp, params: JsonObjectBuilder.() -> Unit): JsonObject"))
        assertTrue(bridge.flatCode.contains("""val request = buildJsonObject { put("operation", op.wire) params() }"""))
        assertTrue(bridge.flatCode.contains("val json = request.toString()"))
        assertEquals(1, bridge.literals.count { it.constant == "operation" }, "\"operation\" literals in the bridge")

        val op = source(PUBLIC_SIGNER_OP)
        val wires = op.literals.map { it.constant }
        assertEquals(PUBLIC_SIGNER_WIRES, wires, "PublicSignerOp wire names")
        val wireLiterals = repoSources().filter { it.path != PUBLIC_SIGNER_OP }.flatMap { src ->
            src.literals.filter { it.constant in setOf("derivePublicIndex", "signPlanTask", "derivePublicAddresses", "createPublicPairing", "resolveSigningPlan", "encodeResponse", "decodePayload", "scanBegin", "scanAdd") }
                .map { "${src.path}:${src.line(it.start)} ${it.constant}" }
        }
        assertTrue(wireLiterals.isEmpty(), "public-signer operation names outside PublicSignerOp.kt:\n" + wireLiterals.joinToString("\n"))
        val excluded = repoSources().flatMap { src ->
            src.literals.filter { it.constant in EXCLUDED_ENGINE_OPS }.map { "${src.path}:${src.line(it.start)} ${it.constant}" }
        }
        assertTrue(excluded.isEmpty(), "excluded engine operations named in main code:\n" + excluded.joinToString("\n"))
        val bridgeWords = bridge.literals.map { it.constant }.toSet()
        for (word in listOf("mnemonic", "validateMnemonic", "sign", "execute", "review", "capabilities", "passphrase")) {
            assertTrue(word !in bridgeWords, "the bridge names \"$word\"")
        }
    }

    @Test
    fun `rule 8 - the seed only in the two secret operations, Ownbit as the export device name`() {
        val bridge = source(PUBLIC_SIGNER_BRIDGE)
        val seedPuts = Regex("""put\("seed", String\(seedHex\)\)""").findAll(bridge.flatCode).count()
        assertEquals(2, seedPuts, "seed puts in the bridge")
        assertEquals(2, Regex("""put\("seed"""").findAll(bridge.flatCode).count(), "no other seed parameter")
        for (function in listOf("derivePublicIndex", "signPlanTask")) {
            assertTrue(bridge.functionText(function).contains("""put("seed", String(seedHex))"""), "$function puts the seed")
        }
        for (function in listOf("capabilities", "derivePublicAddresses", "createPublicPairing", "decodePayload", "reviewAndResolve", "encodeResponse", "openScan")) {
            assertFalse(bridge.functionText(function).contains("seed", ignoreCase = true), "$function must not touch a seed")
        }
        // The engine default device name is "BitSigner"; every Ownbit export says "Ownbit".
        assertTrue(bridge.functionText("createPublicPairing").contains("""put("deviceName", DEVICE_NAME)"""))
        assertTrue(bridge.flatCode.contains("""const val DEVICE_NAME: String = "Ownbit""""))
        assertEquals(1, bridge.literals.count { it.constant == "deviceName" })
        assertTrue(bridge.literals.none { it.constant == "BitSigner" })
    }

    @Test
    fun `the engine API takes no JS source`() {
        val methods = JsEngine::class.java.declaredMethods
            .filter { Modifier.isPublic(it.modifiers) && !Modifier.isStatic(it.modifiers) && !it.isSynthetic }
            .map { it.name }.toSet()
        assertEquals(setOf("call", "callForEvent", "getBundle", "getUnsolicitedEvents"), methods)
        for (method in JsEngine::class.java.declaredMethods.filter { it.name == "call" || it.name == "callForEvent" }) {
            assertEquals(String::class.java, method.parameterTypes[0], "${method.name}: function path")
            assertEquals(JsonArray::class.java, method.parameterTypes[1], "${method.name}: JSON arguments")
        }
    }

    @Test
    fun `the scanner sees what it should`() {
        val sample = KtSource(
            "Sample.kt",
            """
            package x
            import io.ownbit.core.jsengine.JsArgs
            // view.evaluateJavascript("comment") and "bridge.f('${'$'}x')" in a comment
            /* nested /* view.evaluateJavascript(no) */ still comment */
            class A {
                suspend fun ok(fn: String, msg: String, args: JsonArray) {
                    engine.call("bridge.signTx", JsArgs.of(msg, "a,b)(", '"'))
                    engine.call("bridge.${'$'}fn", JsArgs.of(*arrayOf(msg)))
                    engine.callForEvent(BRIDGE + "preSendTx", args, JsEventSpec.of("pre"), 5)
                    engine.call(function = "bridge.${'$'}{type.jsSuffix}Tx", args = JsArgs.NONE)
                    log("value ${'$'}{msg.length} \${'$'}fn")
                }
                suspend fun bad(msg: String) {
                    engine.call("bridge.tronSignMessage('${'$'}msg')", JsArgs.NONE)
                    engine.call("bridge.f", JsonArray(listOf(JsonPrimitive(msg))))
                    engine.callForEvent(build(msg), JsArgs.of(msg), spec)
                    val js = ""${'"'}bridge.f("${'$'}msg")""${'"'}
                    view.evaluateJavascript(js, null)
                    view.loadUrl("javascript:" + js)
                }
            }
            """.trimIndent(),
        )
        // Comments are not code: only the call on line 18 counts.
        assertEquals(listOf(18), sample.codeMatches(EVALUATE).map { sample.line(it.range.first) }.toList())
        val calls = sample.engineCalls()
        assertEquals(listOf(7, 8, 9, 10, 14, 15, 16), calls.map { it.where.substringAfterLast(':').toInt() })
        assertEquals(listOf<String?>(null, null, null, null), calls.take(4).map { it.violation() })
        assertTrue(calls.drop(4).all { it.violation() != null }, calls.drop(4).joinToString("\n") { "${it.text} → ${it.violation()}" })
        assertEquals(
            listOf("bridge.signTx", "a,b)(", "bridge.", "preSendTx", "pre", "bridge.Tx", "value  \$fn"),
            sample.literals.take(7).map { it.constant },
        )
        assertEquals(
            listOf(emptyList(), emptyList(), listOf("fn"), emptyList(), emptyList(), listOf("type.jsSuffix"), listOf("msg.length")),
            sample.literals.take(7).map { it.templates },
        )
        val jsLooking = sample.literals.filter { JS_LOOKING.containsMatchIn(it.constant) && !it.isFunctionPath() }.map { it.constant }
        assertEquals(listOf("bridge.tronSignMessage('')", "bridge.f(\"\")"), jsLooking)
        assertEquals(listOf("javascript:"), sample.literals.map { it.constant }.filter { it.contains("javascript:") })
    }

    // region a small Kotlin lexer: comments, string literals (escapes, `$name` / `${…}` templates, raw strings), chars

    /** A string literal: its decoded constant [parts] (between templates) and the template expressions. */
    private class Literal(val start: Int, val end: Int, val parts: List<String>, val templates: List<String>) {
        val constant: String get() = parts.joinToString("")

        /** Only dotted identifier text, with templates of plain (member) names — never anything JS could execute. */
        fun isFunctionPath(): Boolean = parts.all { PATH_TEXT.matches(it) } && templates.all { MEMBER_CHAIN.matches(it) }
    }

    /** One `.call(` / `.callForEvent(` of a JS engine with its top-level argument texts (named prefixes removed). */
    private class EngineCall(val where: String, val text: String, val args: List<String>, val literals: List<Literal>, val offset: Int) {

        fun violation(): String? {
            val path = args.getOrNull(0) ?: return "no function path"
            val pathStart = text.indexOf(path)
            val inPath = literals.filter { it.start - offset >= pathStart && it.end - offset <= pathStart + path.length }
            if (inPath.any { !it.isFunctionPath() }) return "function path literal is not a plain path"
            var rest = path
            for (l in inPath.sortedByDescending { it.start }) {
                val s = l.start - offset - pathStart
                rest = rest.removeRange(s, l.end - offset - pathStart)
            }
            if (!PATH_EXPRESSION.matches(rest)) return "function path is computed: $path"
            val data = args.getOrNull(1) ?: return null
            if (!DATA_ARGS.matches(data)) return "arguments are not JsArgs data: $data"
            return null
        }
    }

    private class KtSource(val path: String, val text: String) {
        val literals = ArrayList<Literal>()
        private val chars = ArrayList<IntRange>()

        /** [text] with every comment blanked (offsets and line breaks kept). */
        val code: String

        /** [code] with whitespace runs collapsed (for exact-snippet checks). */
        val flatCode: String get() = code.replace(Regex("\\s+"), " ")

        val usesJsEngine: Boolean get() = text.contains("import io.ownbit.core.jsengine.") || text.contains("package io.ownbit.core.jsengine")

        private val literalMask: BooleanArray
        private val lineStarts: IntArray

        init {
            val out = StringBuilder(text)
            Lexer(text, out, literals, chars).code(0, stopAtBrace = false)
            code = out.toString()
            literalMask = BooleanArray(text.length)
            for (l in literals) for (i in l.start until l.end) literalMask[i] = true
            for (c in chars) for (i in c) if (i < text.length) literalMask[i] = true
            lineStarts = (listOf(0) + text.indices.filter { text[it] == '\n' }.map { it + 1 }).toIntArray()
        }

        fun line(offset: Int): Int = lineStarts.indexOfLast { it <= offset } + 1

        /** Matches of [regex] in code (outside comments and string literals). */
        fun codeMatches(regex: Regex): Sequence<MatchResult> = regex.findAll(code).filter { !literalMask[it.range.first] }

        /** The text of `fun [name](` up to the next `fun ` at code level. */
        fun functionText(name: String): String {
            val start = Regex("""\bfun $name\(""").find(code)?.range?.first ?: throw AssertionError("$path: no fun $name")
            val next = Regex("""\bfun \w""").findAll(code, start + 4).firstOrNull()?.range?.first ?: code.length
            return code.substring(start, next).replace(Regex("\\s+"), " ")
        }

        fun engineCalls(): List<EngineCall> = codeMatches(ENGINE_CALL).map { m ->
            val open = m.range.last
            val (args, close) = arguments(open)
            EngineCall("$path:${line(m.range.first)}", code.substring(open, close + 1), args, literals, open)
        }.toList()

        /** Top-level argument texts of the call whose `(` is at [open], and the index of its `)`. */
        private fun arguments(open: Int): Pair<List<String>, Int> {
            val args = ArrayList<String>()
            var depth = 0
            var from = open + 1
            var i = open + 1
            while (i < code.length) {
                if (literalMask[i]) { i++; continue }
                when (code[i]) {
                    '(', '[', '{' -> depth++
                    ')', ']', '}' -> if (depth == 0) {
                        code.substring(from, i).trim().takeIf { it.isNotEmpty() }?.let(args::add)
                        return args.map { it.replace(NAMED_ARGUMENT, "") } to i
                    } else depth--
                    ',' -> if (depth == 0) { args += code.substring(from, i).trim(); from = i + 1 }
                }
                i++
            }
            throw AssertionError("$path: unbalanced call at ${line(open)}")
        }
    }

    /** Blanks comments in [out] and collects [literals] and [chars]; templates' code is lexed recursively. */
    private class Lexer(
        private val s: String,
        private val out: StringBuilder,
        private val literals: MutableList<Literal>,
        private val chars: MutableList<IntRange>,
    ) {

        /** Lexes code from [from]; with [stopAtBrace] returns the index of the `}` closing a template. */
        fun code(from: Int, stopAtBrace: Boolean): Int {
            var i = from
            var depth = 0
            while (i < s.length) {
                when {
                    s.startsWith("//", i) -> i = blank(i, s.indexOf('\n', i).let { if (it < 0) s.length else it })
                    s.startsWith("/*", i) -> i = blockComment(i)
                    s.startsWith("\"\"\"", i) -> i = rawString(i)
                    s[i] == '"' -> i = string(i)
                    s[i] == '\'' -> i = char(i)
                    stopAtBrace && s[i] == '{' -> { depth++; i++ }
                    stopAtBrace && s[i] == '}' -> if (depth == 0) return i else { depth--; i++ }
                    else -> i++
                }
            }
            return s.length
        }

        private fun blank(from: Int, to: Int): Int {
            for (k in from until to) if (out[k] != '\n') out.setCharAt(k, ' ')
            return to
        }

        private fun blockComment(from: Int): Int {
            var i = from + 2
            var depth = 1
            while (i < s.length && depth > 0) {
                when {
                    s.startsWith("/*", i) -> { depth++; i += 2 }
                    s.startsWith("*/", i) -> { depth--; i += 2 }
                    else -> i++
                }
            }
            return blank(from, i)
        }

        private fun char(from: Int): Int {
            var i = from + 1
            while (i < s.length && s[i] != '\'') i += if (s[i] == '\\') 2 else 1
            chars += from..i
            return i + 1
        }

        private fun string(from: Int): Int = literal(from, from + 1, raw = false)

        private fun rawString(from: Int): Int = literal(from, from + 3, raw = true)

        private fun literal(start: Int, contentStart: Int, raw: Boolean): Int {
            val parts = ArrayList<String>()
            val templates = ArrayList<String>()
            val part = StringBuilder()
            var i = contentStart
            while (i < s.length) {
                val c = s[i]
                if (!raw && c == '\\' && i + 1 < s.length) {
                    part.append(unescape(s, i).also { i += it.second }.first)
                    continue
                }
                if (c == '"') {
                    if (!raw) { i++; break }
                    var run = 0
                    while (i + run < s.length && s[i + run] == '"') run++
                    if (run >= 3) { repeat(run - 3) { part.append('"') }; i += run; break }
                    repeat(run) { part.append('"') }
                    i += run
                    continue
                }
                if (c == '$' && i + 1 < s.length && s[i + 1] == '{') {
                    parts += part.toString(); part.clear()
                    val close = code(i + 2, stopAtBrace = true)
                    templates += s.substring(i + 2, close).trim()
                    i = close + 1
                    continue
                }
                if (c == '$' && i + 1 < s.length && (s[i + 1].isLetter() || s[i + 1] == '_')) {
                    parts += part.toString(); part.clear()
                    var j = i + 1
                    while (j < s.length && (s[j].isLetterOrDigit() || s[j] == '_')) j++
                    templates += s.substring(i + 1, j)
                    i = j
                    continue
                }
                part.append(c)
                i++
            }
            parts += part.toString()
            literals += Literal(start, i, parts, templates)
            return i
        }

        /** Decoded escape at [i] (`\"`, `\\`, `\$`, `\n`, `\t`, `\r`, `\b`, `\'`, `\uXXXX`) and its source length. */
        private fun unescape(s: String, i: Int): Pair<String, Int> = when (val e = s[i + 1]) {
            'n' -> "\n" to 2
            't' -> "\t" to 2
            'r' -> "\r" to 2
            'b' -> "\b" to 2
            'u' -> s.substring(i + 2, minOf(i + 6, s.length)).toIntOrNull(16)?.toChar()?.toString().orEmpty() to 6
            else -> e.toString() to 2
        }
    }

    // endregion

    private companion object {
        const val WEBVIEW_ENGINE = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/internal/WebViewJsEngine.kt"
        const val JS_PROTOCOL = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/internal/JsProtocol.kt"
        const val JS_BUNDLE = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/JsBundle.kt"
        const val PUBLIC_SIGNER_BRIDGE = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/PublicSignerJsBridge.kt"
        const val PUBLIC_SIGNER_OP = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/PublicSignerOp.kt"
        const val PUBLIC_SIGNER_EXCEPTION = "jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/PublicSignerException.kt"

        /** A code reference to either public-signer page entry (`JsBundle.PUBLIC_SIGNER`, an imported `PUBLIC_SIGNER_PAIRING`, …). */
        val PUBLIC_SIGNER_ENTRY = Regex("""\bPUBLIC_SIGNER(?:_PAIRING)?\b""")

        /** The 11 allow-listed operations, in enum order. */
        val PUBLIC_SIGNER_WIRES = listOf(
            "capabilities", "derivePublicAddresses", "createPublicPairing", "derivePublicIndex", "signPlanTask", "scanBegin",
            "scanAdd", "decodePayload", "review", "resolveSigningPlan", "encodeResponse",
        )

        /** Engine operations Ownbit never calls whose names are distinctive enough to ban everywhere in main code. */
        val EXCLUDED_ENGINE_OPS = setOf(
            "decodeQR", "wordlist", "deriveAccounts", "deriveBitcoinCosigner", "validateBitcoinPolicy", "encodeQR",
            "createPairing", "createWalletPairing", "deriveWalletPublic",
        )

        val EVALUATE = Regex("""\bevaluateJavascript\s*\(""")
        val JS_INTERFACE = Regex("""\baddJavascriptInterface\s*\(""")
        val ENGINE_CALL = Regex("""\.(?:call|callForEvent)\s*\(""")

        /** Text a JS function path may contain (identifier segments joined by dots). */
        val PATH_TEXT = Regex("""[A-Za-z0-9_$.]*""")

        /** A template that inserts a plain (member) name, e.g. `$fn`, `${type.jsSuffix}`. */
        val MEMBER_CHAIN = Regex("""[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*""")

        /** A function-path argument once its literals are removed: names, member access and `+` only. */
        val PATH_EXPRESSION = Regex("""[\sA-Za-z0-9_.+]*""")

        /** The arguments of a call: `JsArgs.of(…)`, `JsArgs.NONE` or a `JsonArray` value. */
        val DATA_ARGS = Regex("""JsArgs\.of\(.*\)|JsArgs\.NONE|[A-Za-z_][A-Za-z0-9_]*""", RegexOption.DOT_MATCHES_ALL)

        val NAMED_ARGUMENT = Regex("""^[A-Za-z_][A-Za-z0-9_]*\s*=(?!=)\s*""")

        /** Literal text that addresses the page's JS globals. */
        val JS_LOOKING = Regex("""\b(?:bridge|window)\.|__ownbitHost""")
    }
}
