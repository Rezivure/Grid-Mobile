import 'countries.dart';

class NumberTooLongException implements Exception {}

class NumberTooShortException implements Exception {}

class InvalidCharactersException implements Exception {}

class PhoneNumber {
  String countryISOCode;
  String countryCode;
  String number;

  PhoneNumber({
    required this.countryISOCode,
    required this.countryCode,
    required this.number,
  });

  factory PhoneNumber.fromCompleteNumber({required String completeNumber}) {
    if (completeNumber == "") {
      return PhoneNumber(countryISOCode: "", countryCode: "", number: "");
    }
    try {
      String number;
      Country country = getCountry(completeNumber);
      if (completeNumber.startsWith('+')) {
        number = completeNumber
            .substring(1 + country.dialCode.length + country.regionCode.length);
      } else {
        number = completeNumber
            .substring(country.dialCode.length + country.regionCode.length);
      }
      return PhoneNumber(
        countryISOCode: country.code,
        countryCode: country.dialCode + country.regionCode,
        number: number,
      );
    } on InvalidCharactersException {
      return PhoneNumber(
        countryISOCode: "",
        countryCode: "",
        number: completeNumber,
      );
      // ignore: unused_catch_clause
    } on Exception catch (e) {
      return PhoneNumber(
        countryISOCode: "",
        countryCode: "",
        number: completeNumber,
      );
    }
  }

  bool isValidNumber() {
    Country country = getCountry(completeNumber);
    if (number.length < country.minLength) {
      return false;
    }

    if (number.length > country.maxLength) {
      return false;
    }
    return true;
  }

  String get completeNumber {
    return countryCode + number;
  }

  static Country getCountry(String phoneNumber) {
    if (phoneNumber == "") {
      return countries.firstWhere((country) => country.code == "IN");
    }

    final validPhoneNumber = RegExp(r'^[+0-9]*[0-9]*$');

    if (!validPhoneNumber.hasMatch(phoneNumber)) {
      return countries.firstWhere((element) => element.code == "IN");
    }

    if (phoneNumber.startsWith('+')) {
      return countries.firstWhere(
        (country) => phoneNumber
            .substring(1)
            .startsWith(country.dialCode + country.regionCode),
      );
    }
    return countries.firstWhere(
      (country) =>
          phoneNumber.startsWith(country.dialCode + country.regionCode),
    );
  }

  String get getOriginalValue => number;

  @override
  String toString() =>
      'PhoneNumber(countryISOCode: $countryISOCode, countryCode: $countryCode, number: $number)';
}
