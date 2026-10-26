//  JSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Base class of every chain bridge. Ownbit derives keys and signs with bundled JavaScript libraries (bitcoinjs, ethers,
//  TronWeb, solana-web3, stellar-base, ripple-lib, tonweb, …). A bridge evaluates one of those bundles in one of two engines:
//
//  · JSContext (JavaScriptCore): `callJS`. The bundle file is evaluated once, lazily, on the bridge's own serial queue;
//    every call runs on that queue and answers on the main queue.
//  · Hidden WKWebView: `callWeb` / `callWebAwaitingMessage`. Used where the bundle needs a browser environment (for
//    example `window.crypto.getRandomValues` for mnemonic generation or signature nonces) or reports results
//    asynchronously through `window.webkit.messageHandlers.<name>`. The app's HTML shell (e.g. `btc_index.html`) is loaded
//    from `JSBridge.resourceBundle`; it references the bundle next to it. Everything runs on the main queue.
//
//  Results are delivered on the main queue, exactly once per call (success or failure).
//  Nothing is logged: call strings contain seeds / private keys / passphrases and results contain keys and transactions.
//  This file has no network code. The web view is not granted universal access from file URLs, and navigations away from
//  the local page are refused.

import Foundation
import JavaScriptCore
import WebKit
import UIKit

public class JSBridge: NSObject {

    public enum JSError: Error, Equatable {
        /// The JS bundle (or its HTML shell) is not in `JSBridge.resourceBundle`, or the page failed to load.
        case JSDidNotLoaded
        /// The JS call returned `undefined` (it threw) or a result of an unexpected shape.
        case resultError
        /// An asynchronous (message-channel) call is already in flight on this bridge; one at a time, as in the app.
        case busy
        /// No message arrived from an asynchronous call within `JSBridge.asyncResultTimeout`.
        case timeout
        /// The bundle reported an error on its `error` message channel (the message text from JS).
        case scriptError(String)
    }

    /// Where the host app bundled the package's `js/` files. Default `.main`.
    /// Files are looked up by the app's file names: flat (as the app bundles them), then in `<bridge directory>/`, then in
    /// `js/<bridge directory>/` (folder references, or the repository's `js/` directory in tests).
    public static var resourceBundle: Bundle = .main

    /// Maximum wait for the result message of an asynchronous web call (the app waited forever).
    public static var asyncResultTimeout: TimeInterval = 60

    /// Default of `TronJSBridge.provider` / `SolanaJSBridge.provider` (the node URL those bundles take as first argument;
    /// TronWeb won't construct without a syntactically valid one, Solana's Connection likewise). Every TRX / SOL
    /// function in this package derives / signs without contacting the node, so the default works offline. Loopback,
    /// never a real server; the host sets its own node URL if it wants the app's exact setup.
    public static let offlineProviderPlaceholder = "http://127.0.0.1"

    /// Message passed to `JSBridgeValidAddressProtocol` failures when the address is invalid (the app showed a localized
    /// UI string here).
    public static let invalidAddressMessage = "invalid address"

    struct Resource {
        let name: String
        let ext: String
        let directory: String
    }

    static func resourceURL(_ resource: Resource) -> URL? {
        let bundle = resourceBundle
        return bundle.url(forResource: resource.name, withExtension: resource.ext)
            ?? bundle.url(forResource: resource.name, withExtension: resource.ext, subdirectory: resource.directory)
            ?? bundle.url(forResource: resource.name, withExtension: resource.ext, subdirectory: "js/" + resource.directory)
    }

    override init() {
        super.init()
    }

    // MARK: - JSContext engine

    /// The bundle evaluated in this bridge's JSContext (subclasses override). Nil = this bridge has no JSContext.
    var contextScript: Resource? { return nil }

    /// Define `window` as the global object before evaluating the bundle. The app ran the Stellar bundle in the JSContext
    /// of a UIWebView, where `window` exists (stellar-base then uses tweetnacl); a plain JSContext plus this alias is the
    /// same for every kept function (they derive and sign deterministically; no randomness, no DOM).
    var contextNeedsWindow: Bool { return false }

    private let contextQueue = DispatchQueue(label: "io.ownbit.core.jscontext")
    private var jsContext: JSContext?   // contextQueue only

    /// On `contextQueue`. Nil (and nothing cached, so a later call retries) when the bundle can't be read.
    private func loadedContext() -> JSContext? {
        if let context = jsContext {
            return context
        }
        guard let script = contextScript, let url = JSBridge.resourceURL(script),
              let data = try? Data(contentsOf: url), let source = String(data: data, encoding: .utf8),
              let context = JSContext() else {
            return nil
        }
        // Never print JS exceptions: the exception text contains the whole call source, which may contain a seed.
        context.exceptionHandler = { _, _ in }
        if contextNeedsWindow {
            context.evaluateScript("var window = this;")
        }
        context.evaluateScript(source)
        jsContext = context
        return context
    }

    /// Evaluates `method` in the JSContext. `undefined` (the call threw, or returned nothing) → `failure(.resultError)`.
    func callJS(method: String, success: @escaping (_ object: JSValue) -> Void, failure: @escaping (_ error: Error) -> Void) {
        contextQueue.async {
            guard let context = self.loadedContext() else {
                DispatchQueue.main.async { failure(JSError.JSDidNotLoaded) }
                return
            }
            let value = context.evaluateScript(method)
            DispatchQueue.main.async {
                if let value = value, !value.isUndefined {
                    success(value)
                } else {
                    failure(JSError.resultError)
                }
            }
        }
    }

    // MARK: - WKWebView engine

    /// The HTML shell loaded into this bridge's web view (subclasses override). Nil = this bridge has no web view.
    var webPage: Resource? { return nil }

    /// `window.webkit.messageHandlers.<name>` channels the page posts results to.
    var webMessageNames: [String] { return [] }

    private enum WebState { case idle, loading, ready }

    private var webView: WKWebView?                     // main queue only (as everything below)
    private var webState = WebState.idle
    private var webWaiters: [() -> Void] = []
    private lazy var webDelegate = JSBridgeWebDelegate(owner: self)

    private final class PendingMessage {
        let completion: (Result<(name: String, body: String), Error>) -> Void
        var timer: DispatchWorkItem?
        init(completion: @escaping (Result<(name: String, body: String), Error>) -> Void) {
            self.completion = completion
        }
    }
    private var pendingMessage: PendingMessage?

    private func ensureWebView() -> WKWebView {
        if let webView = webView {
            return webView
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        for name in webMessageNames {
            controller.add(webDelegate, name: name)
        }
        config.userContentController = controller
        // 1×1, almost transparent, not interactive, and (when the host has a window) inserted at the very bottom of the
        // key window: a web view outside any window, or hidden, counts as an invisible page and WebKit may suspend its
        // content process (the app's fix for signing calls that never came back).
        let wk = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wk.alpha = 0.01
        wk.isUserInteractionEnabled = false
        wk.navigationDelegate = webDelegate
        webView = wk
        return wk
    }

    private func attachToWindowIfNeeded() {
        guard let wk = webView, wk.superview == nil, let window = JSBridge.hostWindow() else { return }
        window.insertSubview(wk, at: 0)
    }

    /// The host app's key window, if this process is an app (not an extension or a unit-test runner).
    private static func hostWindow() -> UIWindow? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }

    /// Main queue. `finished` runs once the page is ready, or failed to load (the caller then reports `.JSDidNotLoaded`).
    private func loadWeb(_ finished: @escaping () -> Void) {
        switch webState {
        case .ready:
            attachToWindowIfNeeded()
            finished()
            return
        case .loading:
            webWaiters.append(finished)
            return
        case .idle:
            break
        }
        webWaiters.append(finished)
        guard let page = webPage, let url = JSBridge.resourceURL(page) else {
            flushWebWaiters()
            return
        }
        webState = .loading
        let wk = ensureWebView()
        attachToWindowIfNeeded()
        wk.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func flushWebWaiters() {
        let waiters = webWaiters
        webWaiters.removeAll()
        waiters.forEach { $0() }
    }

    /// Loads the page now (first load of a big bundle takes a few seconds).
    func preloadWeb() {
        DispatchQueue.main.async {
            self.loadWeb { }
        }
    }

    /// Evaluates `method` in the web view and returns its (serializable) value.
    func callWeb(method: String, success: @escaping (_ object: Any?) -> Void, failure: @escaping (_ error: Error) -> Void) {
        DispatchQueue.main.async {
            self.loadWeb {
                guard self.webState == .ready, let wk = self.webView else {
                    failure(JSError.JSDidNotLoaded)
                    return
                }
                wk.evaluateJavaScript(method) { result, error in
                    if let error = error {
                        failure(error)
                    } else {
                        success(result)
                    }
                }
            }
        }
    }

    /// Calls a JS function whose real result arrives on a message channel (an `async` function that posts
    /// `window.webkit.messageHandlers.<name>.postMessage(...)`). `"; 0"` is appended so the evaluation itself returns a
    /// serializable value instead of a Promise; a synchronous JS exception still fails the call. The first message on any
    /// of `webMessageNames` completes it: `error` → `.scriptError(body)`, any other channel → `(name, body)`.
    func callWebAwaitingMessage(method: String, completion: @escaping (_ result: Result<(name: String, body: String), Error>) -> Void) {
        DispatchQueue.main.async {
            guard self.pendingMessage == nil else {
                completion(.failure(JSError.busy))
                return
            }
            let pending = PendingMessage(completion: completion)
            self.pendingMessage = pending
            self.loadWeb {
                guard self.pendingMessage === pending else { return }
                guard self.webState == .ready, let wk = self.webView else {
                    self.finish(pending, .failure(JSError.JSDidNotLoaded))
                    return
                }
                // The clock starts once the page is ready (the first load of a big bundle can take a while).
                // finish(_:_:) ignores a call that already completed, so the timer may hold `pending` until it fires.
                let timer = DispatchWorkItem {
                    self.finish(pending, .failure(JSError.timeout))
                }
                pending.timer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + JSBridge.asyncResultTimeout, execute: timer)
                wk.evaluateJavaScript(method + "; 0") { _, error in
                    if let error = error {
                        self.finish(pending, .failure(error))
                    }
                }
            }
        }
    }

    private func finish(_ pending: PendingMessage, _ result: Result<(name: String, body: String), Error>) {
        guard pendingMessage === pending else { return }
        pendingMessage = nil
        pending.timer?.cancel()
        pending.completion(result)
    }

    // MARK: Web delegate callbacks (main queue)

    fileprivate func webDidFinish() {
        webState = .ready
        flushWebWaiters()
    }

    fileprivate func webDidFail() {
        webState = .idle
        flushWebWaiters()
        if let pending = pendingMessage {
            finish(pending, .failure(JSError.JSDidNotLoaded))
        }
    }

    /// The content process crashed: everything in flight is gone. Reload; calls wait for the reload.
    fileprivate func webProcessDidTerminate(_ webView: WKWebView) {
        webState = .loading
        if let pending = pendingMessage {
            finish(pending, .failure(JSError.JSDidNotLoaded))
        }
        webView.reload()
    }

    fileprivate func webDidReceive(name: String, body: Any) {
        guard let pending = pendingMessage else { return }
        let text = (body as? String) ?? "\(body)"
        if name == "error" {
            finish(pending, .failure(JSError.scriptError(text)))
        } else {
            finish(pending, .success((name: name, body: text)))
        }
    }

    // MARK: - Result helpers

    /// The first `count` elements as strings (empty strings allowed), or nil.
    static func strings(_ array: [Any]?, count: Int) -> [String]? {
        guard let array = array, array.count >= count else { return nil }
        let out = array.prefix(count).compactMap { $0 as? String }
        return out.count == count ? out : nil
    }

    /// The whole array as strings, or nil (the app: `arr as? [String]`).
    static func stringArray(_ array: [Any]?) -> [String]? {
        guard let array = array, !array.isEmpty else { return nil }
        return array as? [String]
    }
}

/// WebKit delegates for `JSBridge`, kept out of the public class. Holds the bridge weakly (the user content controller
/// retains its handlers).
private final class JSBridgeWebDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    weak var owner: JSBridge?

    init(owner: JSBridge) {
        self.owner = owner
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.webDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        owner?.webDidFail()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.webDidFail()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        owner?.webProcessDidTerminate(webView)
    }

    /// Only the local HTML shell may be shown in the web view.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.isFileURL == true || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.webDidReceive(name: message.name, body: message.body)
    }
}

// MARK: - Protocols kept from the app

/// Address validation. `failure` gets `JSBridge.invalidAddressMessage` for an invalid address, or the JS error's
/// description when the call itself failed.
public protocol JSBridgeValidAddressProtocol {
    func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void)
}

/// UTXO-style bridges that derive account xpubs and addresses (the app's `BILCoinMultipleAddressGeneratorProtocol`).
public protocol BILCoinMultipleAddressGeneratorProtocol {
    func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void)
    func getXPublicKeys(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void)
    func getAddresses(xpub: String, fromIndex: Int64, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void)
    func getAddress(from publicKey: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void)
}
