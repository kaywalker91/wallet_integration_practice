import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pinenacl/tweetnacl.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Parameters for decryption operation in isolate
class _DecryptParams {
  const _DecryptParams({
    required this.encryptedData,
    required this.nonce,
    required this.privateKey,
    required this.theirPublicKey,
  });

  final Uint8List encryptedData;
  final Uint8List nonce;
  final Uint8List privateKey;
  final Uint8List theirPublicKey;
}

/// Result from decryption operation
class DecryptResult {
  const DecryptResult._({
    this.decryptedString,
    this.error,
  });

  factory DecryptResult.success(String decryptedString) =>
      DecryptResult._(decryptedString: decryptedString);

  factory DecryptResult.failure(String error) => DecryptResult._(error: error);

  final String? decryptedString;
  final String? error;

  bool get isSuccess => error == null && decryptedString != null;
}

/// Parameters for batch Base58 decoding
class _Base58BatchParams {
  const _Base58BatchParams(this.inputs);
  final List<String> inputs;
}

/// Isolate-based crypto operations for Phantom wallet
///
/// Offloads heavy cryptographic operations to background isolates
/// to prevent main thread blocking and UI jank (108 frames skipped issue).
///
/// When [AppConstants.useIsolateCrypto] is false, operations run on
/// main thread as fallback.
class CryptoIsolate {
  CryptoIsolate._();

  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Decrypt Phantom response payload using X25519 box
  ///
  /// Runs TweetNaCl.crypto_box_open() in a background isolate
  /// to prevent main thread blocking (~200-400ms).
  ///
  /// Falls back to synchronous execution when isolate crypto is disabled.
  static Future<DecryptResult> decryptPhantomPayload({
    required Uint8List encryptedData,
    required Uint8List nonce,
    required Uint8List privateKey,
    required Uint8List theirPublicKey,
  }) async {
    // Feature flag check - fallback to sync if disabled
    if (!AppConstants.useIsolateCrypto) {
      return _decryptSync(
        encryptedData: encryptedData,
        nonce: nonce,
        privateKey: privateKey,
        theirPublicKey: theirPublicKey,
      );
    }

    try {
      final params = _DecryptParams(
        encryptedData: encryptedData,
        nonce: nonce,
        privateKey: privateKey,
        theirPublicKey: theirPublicKey,
      );

      final result = await Isolate.run(() => _decryptInIsolate(params));
      return result;
    } catch (e) {
      AppLogger.e('CryptoIsolate.decryptPhantomPayload failed', e);
      return DecryptResult.failure('Decryption failed: $e');
    }
  }

  /// Synchronous decryption fallback (runs on main thread)
  static DecryptResult _decryptSync({
    required Uint8List encryptedData,
    required Uint8List nonce,
    required Uint8List privateKey,
    required Uint8List theirPublicKey,
  }) {
    try {
      // Manual padding for TweetNaCl low-level API
      // boxzerobytes = 16 (prepended to ciphertext), zerobytes = 32 (stripped from plaintext)
      const boxZeroBytesLength = 16;
      const zeroBytesLength = 32;

      final c = Uint8List(boxZeroBytesLength + encryptedData.length);
      c.setRange(boxZeroBytesLength, c.length, encryptedData);

      final m = Uint8List(c.length);

      // Call crypto_box_open
      TweetNaCl.crypto_box_open(
        m,
        c,
        c.length,
        nonce,
        theirPublicKey,
        privateKey,
      );

      // Result is in m, starting at offset 32 (zeroBytesLength)
      final messageBytes = m.sublist(zeroBytesLength);

      // Trim trailing null bytes
      var endIndex = messageBytes.length;
      while (endIndex > 0 && messageBytes[endIndex - 1] == 0) {
        endIndex--;
      }
      final trimmedBytes = messageBytes.sublist(0, endIndex);

      return DecryptResult.success(utf8.decode(trimmedBytes));
    } catch (e) {
      return DecryptResult.failure('Decryption failed: $e');
    }
  }

  /// Isolate entry point for decryption
  static DecryptResult _decryptInIsolate(_DecryptParams params) {
    try {
      const boxZeroBytesLength = 16;
      const zeroBytesLength = 32;

      final c = Uint8List(boxZeroBytesLength + params.encryptedData.length);
      c.setRange(boxZeroBytesLength, c.length, params.encryptedData);

      final m = Uint8List(c.length);

      TweetNaCl.crypto_box_open(
        m,
        c,
        c.length,
        params.nonce,
        params.theirPublicKey,
        params.privateKey,
      );

      final messageBytes = m.sublist(zeroBytesLength);

      var endIndex = messageBytes.length;
      while (endIndex > 0 && messageBytes[endIndex - 1] == 0) {
        endIndex--;
      }
      final trimmedBytes = messageBytes.sublist(0, endIndex);

      return DecryptResult.success(utf8.decode(trimmedBytes));
    } catch (e) {
      return DecryptResult.failure('Decryption failed: $e');
    }
  }

  /// Batch decode multiple Base58 strings in a single isolate call
  ///
  /// More efficient than multiple individual calls by reducing
  /// isolate spawn overhead (~20-50ms saved per batch).
  ///
  /// Falls back to synchronous execution when isolate crypto is disabled.
  static Future<List<Uint8List>> decodeBase58Batch(List<String> inputs) async {
    if (!AppConstants.useIsolateCrypto) {
      return inputs.map(_decodeBase58Sync).toList();
    }

    try {
      final params = _Base58BatchParams(inputs);
      return await Isolate.run(() => _decodeBase58BatchInIsolate(params));
    } catch (e) {
      AppLogger.e('CryptoIsolate.decodeBase58Batch failed', e);
      // Fallback to sync on error
      return inputs.map(_decodeBase58Sync).toList();
    }
  }

  /// Decode a single Base58 string in an isolate
  static Future<Uint8List> decodeBase58(String input) async {
    if (!AppConstants.useIsolateCrypto) {
      return _decodeBase58Sync(input);
    }

    try {
      return await Isolate.run(() => _decodeBase58Sync(input));
    } catch (e) {
      AppLogger.e('CryptoIsolate.decodeBase58 failed', e);
      return _decodeBase58Sync(input);
    }
  }

  /// Isolate entry point for batch Base58 decoding
  static List<Uint8List> _decodeBase58BatchInIsolate(_Base58BatchParams params) {
    return params.inputs.map(_decodeBase58Sync).toList();
  }

  /// Synchronous Base58 decoding
  static Uint8List _decodeBase58Sync(String input) {
    if (input.isEmpty) return Uint8List(0);

    // Count leading '1' characters (zeros)
    var leadingZeros = 0;
    for (final char in input.runes) {
      if (String.fromCharCode(char) == '1') {
        leadingZeros++;
      } else {
        break;
      }
    }

    // Convert from base58
    var num = BigInt.zero;
    for (final char in input.runes) {
      final index = _base58Alphabet.indexOf(String.fromCharCode(char));
      if (index < 0) {
        throw FormatException(
            'Invalid Base58 character: ${String.fromCharCode(char)}');
      }
      num = num * BigInt.from(58) + BigInt.from(index);
    }

    // Convert BigInt to bytes
    final bytes = <int>[];
    while (num > BigInt.zero) {
      bytes.insert(0, (num % BigInt.from(256)).toInt());
      num = num ~/ BigInt.from(256);
    }

    // Add leading zeros
    final result = Uint8List(leadingZeros + bytes.length);
    result.setRange(leadingZeros, result.length, bytes);

    return result;
  }

  /// Encode bytes to Base58 string
  ///
  /// This operation is typically fast and doesn't need isolate,
  /// but provided for consistency.
  static String encodeBase58(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // Count leading zero bytes
    var leadingZeros = 0;
    for (final byte in bytes) {
      if (byte == 0) {
        leadingZeros++;
      } else {
        break;
      }
    }

    // Convert to base58
    final result = <int>[];
    var num = BigInt.zero;
    for (final byte in bytes) {
      num = (num << 8) + BigInt.from(byte);
    }

    while (num > BigInt.zero) {
      result.insert(0, (num % BigInt.from(58)).toInt());
      num = num ~/ BigInt.from(58);
    }

    // Build result with leading '1' characters for zeros
    final encoded = StringBuffer();
    for (var i = 0; i < leadingZeros; i++) {
      encoded.write('1');
    }
    for (var i = result.length - 1; i >= 0; i--) {
      encoded.write(_base58Alphabet[result[i]]);
    }

    return encoded.toString();
  }

  /// Verify Ed25519 signature in isolate
  ///
  /// Offloads signature verification to background isolate
  /// to prevent main thread blocking.
  static Future<bool> verifySignature({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) async {
    if (!AppConstants.useIsolateCrypto) {
      return _verifySignatureSync(
        signature: signature,
        message: message,
        publicKey: publicKey,
      );
    }

    try {
      return await Isolate.run(() => _verifySignatureSync(
            signature: signature,
            message: message,
            publicKey: publicKey,
          ));
    } catch (e) {
      AppLogger.e('CryptoIsolate.verifySignature failed', e);
      return false;
    }
  }

  /// Synchronous signature verification
  static bool _verifySignatureSync({
    required Uint8List signature,
    required Uint8List message,
    required Uint8List publicKey,
  }) {
    try {
      // Build signed message format: signature (64 bytes) + message
      final signedMessage = Uint8List(signature.length + message.length);
      signedMessage.setRange(0, signature.length, signature);
      signedMessage.setRange(signature.length, signedMessage.length, message);

      final openedMessage = Uint8List(signedMessage.length);

      final result = TweetNaCl.crypto_sign_open(
        openedMessage,
        -1, // dummy (not used)
        signedMessage,
        0, // offset
        signedMessage.length,
        publicKey,
      );

      return result >= 0;
    } catch (e) {
      return false;
    }
  }
}
