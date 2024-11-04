import 'package:encrypt/encrypt.dart' as encrypt;

String encryptText(String text, String encryptionKey, encrypt.IV iv) {
  final key = encrypt.Key.fromBase64(encryptionKey);
  final encrypter = encrypt.Encrypter(encrypt.AES(key));
  return encrypter.encrypt(text, iv: iv).base64;
}

String decryptText(String encryptedText, String encryptionKey, String ivString) {
  final key = encrypt.Key.fromBase64(encryptionKey);
  final iv = encrypt.IV.fromBase64(ivString);
  final encrypter = encrypt.Encrypter(encrypt.AES(key));
  return encrypter.decrypt64(encryptedText, iv: iv);
}
