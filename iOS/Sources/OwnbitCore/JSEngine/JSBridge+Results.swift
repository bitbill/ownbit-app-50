//  JSBridge+Results.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The result shapes the bridges check, shared. Where the app silently dropped a malformed result (no callback at all),
//  these call `failure(.resultError)`, so every call completes exactly once.

import Foundation
import JavaScriptCore

extension JSBridge {

    // MARK: JSContext

    /// A non-empty string.
    func callJSNonEmptyString(_ method: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJS(method: method, success: { result in
            guard let s = result.toString(), !s.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    /// An array whose first `count` elements are strings.
    func callJSStrings(_ method: String, count: Int, success: @escaping ([String]) -> Void, failure: @escaping (Error) -> Void) {
        callJS(method: method, success: { result in
            guard let r = JSBridge.strings(result.toArray(), count: count) else {
                failure(JSError.resultError)
                return
            }
            success(r)
        }, failure: failure)
    }

    /// A non-empty array of strings (signatures, addresses).
    func callJSStringArray(_ method: String, success: @escaping ([String]) -> Void, failure: @escaping (Error) -> Void) {
        callJS(method: method, success: { result in
            guard let a = JSBridge.stringArray(result.toArray()) else {
                failure(JSError.resultError)
                return
            }
            success(a)
        }, failure: failure)
    }

    /// `JSBridgeValidAddressProtocol` on a JSContext bundle: `method` returns a boolean.
    func callJSValidate(_ method: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJS(method: method, success: { result in
            if result.toBool() {
                success()
            } else {
                failure(JSBridge.invalidAddressMessage)
            }
        }, failure: { error in
            failure(error.localizedDescription)
        })
    }

    // MARK: Web view

    func callWebNonEmptyString(_ method: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callWeb(method: method, success: { result in
            guard let s = result as? String, !s.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    func callWebStrings(_ method: String, count: Int, success: @escaping ([String]) -> Void, failure: @escaping (Error) -> Void) {
        callWeb(method: method, success: { result in
            guard let r = JSBridge.strings(result as? [Any], count: count) else {
                failure(JSError.resultError)
                return
            }
            success(r)
        }, failure: failure)
    }

    func callWebStringArray(_ method: String, success: @escaping ([String]) -> Void, failure: @escaping (Error) -> Void) {
        callWeb(method: method, success: { result in
            guard let a = JSBridge.stringArray(result as? [Any]) else {
                failure(JSError.resultError)
                return
            }
            success(a)
        }, failure: failure)
    }

    /// `JSBridgeValidAddressProtocol` on a web bundle: `method` returns a boolean.
    func callWebValidate(_ method: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWeb(method: method, success: { result in
            let isValid = (result as? Bool) ?? (result as? NSNumber)?.boolValue ?? false
            if isValid {
                success()
            } else {
                failure(JSBridge.invalidAddressMessage)
            }
        }, failure: { error in
            failure(error.localizedDescription)
        })
    }

    /// An asynchronous call whose result arrives on one of `channels` (any other channel → `.resultError`).
    func callWebForMessage(_ method: String, channels: Set<String>, success: @escaping (_ name: String, _ body: String) -> Void, failure: @escaping (Error) -> Void) {
        callWebAwaitingMessage(method: method) { result in
            switch result {
            case .success(let message) where channels.contains(message.name):
                success(message.name, message.body)
            case .success:
                failure(JSError.resultError)
            case .failure(let error):
                failure(error)
            }
        }
    }
}
