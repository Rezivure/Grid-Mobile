import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class ProfilePictureEncryption {
  static const int KEY_SIZE = 32; // 256 bits
  static const int IV_SIZE = 16; // 128 bits

  /// Generates a new encryption key
  static String generateEncryptionKey() {
    final key = Key.fromSecureRandom(KEY_SIZE);
    return base64.encode(key.bytes);
  }

  /// Generates a new IV
  static String generateIV() {
    final iv = IV.fromSecureRandom(IV_SIZE);
    return base64.encode(iv.bytes);
  }

  /// Encrypts a file and returns the encrypted bytes
  static Future<Uint8List> encryptFile(File file, String keyBase64, String ivBase64) async {
    try {
      // Read file bytes
      final bytes = await file.readAsBytes();
      
      // Decode key and IV
      final key = Key(base64.decode(keyBase64));
      final iv = IV(base64.decode(ivBase64));
      
      // Create encrypter
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      // Encrypt the bytes
      final encrypted = encrypter.encryptBytes(bytes, iv: iv);
      
      return encrypted.bytes;
    } catch (e) {
      throw Exception('Failed to encrypt file: $e');
    }
  }

  /// Decrypts bytes and returns the decrypted data
  static Uint8List? decryptBytes(Uint8List encryptedBytes, String keyBase64, String ivBase64) {
    try {
      // Decode key and IV
      final key = Key(base64.decode(keyBase64));
      final iv = IV(base64.decode(ivBase64));
      
      // Create encrypter
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      
      // Create encrypted object from bytes
      final encrypted = Encrypted(encryptedBytes);
      
      // Decrypt the bytes
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
      
      return Uint8List.fromList(decrypted);
    } catch (e) {
      return null;
    }
  }

  /// Generates a hash of the encryption key for verification
  static String generateKeyHash(String keyBase64) {
    final bytes = utf8.encode(keyBase64);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Creates encrypted profile picture metadata
  static Map<String, dynamic> createMetadata({
    required String encryptionKey,
    required String iv,
    required String url,
    required String filename,
  }) {
    return {
      'version': '1.0',
      'algorithm': 'AES-256-CBC',
      'key': encryptionKey,
      'iv': iv,
      'url': url,
      'filename': filename,
      'uploadedAt': DateTime.now().toIso8601String(),
    };
  }
}