//  ScryptTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import XCTest
@testable import OwnbitCore

final class VaultScryptTests: XCTestCase {

    /// RFC 7914 section 12 test vectors 1-3, through CLibscrypt. (Vector 4, N = 2^20, needs 1 GiB and is skipped.)
    func testRFC7914Vectors() {
        let vectors: [(String, String, Int, Int, Int, String)] = [
            ("", "", 16, 1, 1,
             "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906"),
            ("password", "NaCl", 1024, 8, 16,
             "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"),
            ("pleaseletmein", "SodiumChloride", 16384, 8, 1,
             "7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887"),
        ]
        for (password, salt, n, r, p, expected) in vectors {
            let dk = Scrypt.derive(password: password, salt: Data(salt.utf8), dkLen: 64, n: n, r: r, p: p)
            XCTAssertEqual(dk?.hexString, expected, "N=\(n)")
        }
    }

    /// The vault's own parameters (N = 32768, r = 8, p = 1, dkLen = 32). Expected value from Python
    /// `hashlib.scrypt(b"ownbit vault kat", salt=bytes(range(16)), n=32768, r=8, p=1, dklen=32)`.
    func testVaultParameters() {
        let dk = Scrypt.derive(password: VaultFixtures.password, salt: VaultFixtures.salt, dkLen: 32,
                               n: 32768, r: 8, p: 1)
        XCTAssertEqual(dk?.hexString, "846d26b6a6bb429ddbd63c50584bfa4cbef87b28ca022aae7ad0f347c7a1c7f4")
    }

    func testPasswordIsUTF8() {
        let a = Scrypt.derive(password: "密码é", salt: Data([1, 2, 3]), dkLen: 32, n: 16, r: 1, p: 1)
        let b = Scrypt.derive(password: String(decoding: Array("密码é".utf8), as: UTF8.self), salt: Data([1, 2, 3]),
                              dkLen: 32, n: 16, r: 1, p: 1)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testInvalidParametersReturnNil() {
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 0, n: 16, r: 1, p: 1))
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 32, n: 0, r: 1, p: 1))
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 32, n: 16, r: 0, p: 1))
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 32, n: 16, r: 1, p: 0))
        // libscrypt rejects N that is not a power of two greater than 1
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 32, n: 1000, r: 1, p: 1))
        XCTAssertNil(Scrypt.derive(password: "x", salt: Data(), dkLen: 32, n: 1, r: 1, p: 1))
    }
}

final class VaultSupportHelpersTests: XCTestCase {

    func testSHA256() {
        XCTAssertEqual("".sha256(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual("abc".sha256(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual("助记词 🔑".sha256(), "a723985b557e63cd7925b4fb6d3600a2de3fb629ef6785be7978ca123115852b")
    }

    func testHexRoundTrip() {
        let bytes = Data([0x00, 0x01, 0x7f, 0x80, 0xab, 0xff])
        XCTAssertEqual(bytes.hexString, "00017f80abff")
        XCTAssertEqual(Data(hexString: "00017f80abff"), bytes)
        XCTAssertEqual(Data(hexString: "00017F80ABFF"), bytes)
        XCTAssertEqual(Data(hexString: "0x00017f80abff"), bytes)
        XCTAssertEqual(Data(hexString: "0X00017f80abff"), bytes)
        XCTAssertEqual(Data(hexString: ""), Data())
        XCTAssertEqual(Data(hexString: "0x"), Data())
        XCTAssertEqual(Data().hexString, "")
    }

    func testHexRejectsInvalid() {
        XCTAssertNil(Data(hexString: "abc"))      // odd length
        XCTAssertNil(Data(hexString: "zz"))
        XCTAssertNil(Data(hexString: "+f"))
        XCTAssertNil(Data(hexString: "0 "))
        XCTAssertNil(Data(hexString: "0x0"))
        XCTAssertNil(Data(hexString: "é0"))
    }

    func testSecureRandom() {
        XCTAssertEqual(SecureRandom.bytes(0), Data())
        let a = SecureRandom.bytes(32)
        let b = SecureRandom.bytes(32)
        XCTAssertEqual(a.count, 32)
        XCTAssertEqual(b.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(SecureRandom.bytes(7).count, 7)
    }
}
