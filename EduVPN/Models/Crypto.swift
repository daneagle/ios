//
//  Crypto.swift
//  EduVPN
//
//  Created by Jeroen Leenarts on 24/07/2019.
//  Copyright © 2019 SURFNet. All rights reserved.
//

import Foundation
import os.log

enum CryptoError: Error {
    case keyCreationFailed
}

class Crypto {
    private static let keyName = "disk_storage_key"

    private static func makeAndStoreKey(name: String) throws -> SecKey {
        guard let access =
            SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                            SecAccessControlCreateFlags.privateKeyUsage,
                                            nil) else {
                                                throw CryptoError.keyCreationFailed
        }
        var attributes = [String: Any]()
        if Device.hasSecureEnclave {
            attributes[kSecAttrKeyType as String] = kSecAttrKeyTypeEC
            attributes[kSecAttrKeySizeInBits as String] = 256
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        } else {
            attributes[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
            attributes[kSecAttrKeySizeInBits as String] = 4096
        }

        let tag = name.data(using: .utf8) ?? Data()
        attributes[kSecPrivateKeyAttrs as String] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: tag,
            kSecAttrAccessControl as String: access
        ]

        var error: Unmanaged<CFError>?
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)

        if let error = error {
            throw error.takeRetainedValue() as Error
        }

        guard let unwrappedPrivateKey = privateKey else {
            throw CryptoError.keyCreationFailed
        }

        return unwrappedPrivateKey
    }

    private static func loadKey(name: String) -> SecKey? {
        let tag = name
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: tag,
            kSecAttrKeyType as String: (Device.hasSecureEnclave ? kSecAttrKeyTypeEC: kSecAttrKeyTypeRSA),
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        return (item as! SecKey) // swiftlint:disable:this force_cast
    }

    static func encrypt(data clearTextData: Data) throws -> Data? {
        let key = try loadKey(name: keyName) ?? makeAndStoreKey(name: keyName)

        guard let publicKey = SecKeyCopyPublicKey(key) else {
            // Can't get public key
            return nil
        }
        let algorithm: SecKeyAlgorithm = Device.hasSecureEnclave ? .eciesEncryptionCofactorVariableIVX963SHA256AESGCM: .rsaEncryptionOAEPSHA512AESGCM
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            os_log("Can't encrypt. Algorith not supported.", log: Log.crypto, type: .error)
            return nil
        }
        var error: Unmanaged<CFError>?
        let cipherTextData = SecKeyCreateEncryptedData(publicKey, algorithm,
                                                       clearTextData as CFData,
                                                       &error) as Data?
        if let error = error {
            os_log("Can't encrypt. %{public}@", log: Log.crypto, type: .error, (error.takeRetainedValue() as Error).localizedDescription)
            return nil
        }
        guard cipherTextData != nil else {
            os_log("Can't encrypt. No resulting cipherTextData", log: Log.crypto, type: .error)
            return nil
        }

        os_log("Encrypted data.", log: Log.crypto, type: .info)
        return cipherTextData
    }

    static func decrypt(data cipherTextData: Data) -> Data? {
        guard let key = loadKey(name: keyName) else { return nil }

        let algorithm: SecKeyAlgorithm = Device.hasSecureEnclave ? .eciesEncryptionCofactorVariableIVX963SHA256AESGCM: .rsaEncryptionOAEPSHA512AESGCM
        guard SecKeyIsAlgorithmSupported(key, .decrypt, algorithm) else {
            os_log("Can't decrypt. Algorith not supported.", log: Log.crypto, type: .error)
            return nil
        }

        var error: Unmanaged<CFError>?
        let clearTextData = SecKeyCreateDecryptedData(key,
                                                      algorithm,
                                                      cipherTextData as CFData,
                                                      &error) as Data?
        if let error = error {
            os_log("Can't decrypt. %{public}@", log: Log.crypto, type: .error, (error.takeRetainedValue() as Error).localizedDescription)
            return nil
        }
        guard clearTextData != nil else {
            os_log("Can't decrypt. No resulting cleartextData.", log: Log.crypto, type: .error)
            return nil
        }
        os_log("Decrypted data.", log: Log.crypto, type: .info)
        return clearTextData
    }
}
