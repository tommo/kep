import XCTest
@testable import MindoModel

final class NoteEncryptionTests: XCTestCase {

    func testRoundTripsThroughEncryptDecrypt() {
        let plain = "Sensitive launch plan — do not share."
        let cipher = NoteEncryption.encrypt(plaintext: plain, password: "hunter2")
        XCTAssertNotEqual(cipher, plain)
        XCTAssertTrue(NoteEncryption.looksEncrypted(cipher))
        XCTAssertEqual(NoteEncryption.decrypt(cipher, password: "hunter2"), plain)
    }

    func testWrongPasswordReturnsNil() {
        let cipher = NoteEncryption.encrypt(plaintext: "x", password: "right")
        XCTAssertNil(NoteEncryption.decrypt(cipher, password: "wrong"))
    }

    func testRandomNonceMakesEachCallDistinct() {
        let a = NoteEncryption.encrypt(plaintext: "same", password: "k")
        let b = NoteEncryption.encrypt(plaintext: "same", password: "k")
        XCTAssertNotEqual(a, b, "encrypt should never repeat its output for the same input")
    }

    func testNonEncryptedTextIsRecognized() {
        XCTAssertFalse(NoteEncryption.looksEncrypted("plain note"))
        XCTAssertFalse(NoteEncryption.looksEncrypted(""))
    }

    func testCorruptCiphertextReturnsNilWithoutThrowing() {
        XCTAssertNil(NoteEncryption.decrypt("MINDO-ENC:v1:not:base64:garbage", password: "k"))
        XCTAssertNil(NoteEncryption.decrypt("not encrypted at all", password: "k"))
    }

    func testHandlesUnicodePlaintext() {
        let plain = "你好 🌟 Café — テスト"
        let cipher = NoteEncryption.encrypt(plaintext: plain, password: "p")
        XCTAssertEqual(NoteEncryption.decrypt(cipher, password: "p"), plain)
    }
}
