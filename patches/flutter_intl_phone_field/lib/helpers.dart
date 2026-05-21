import 'package:flutter/material.dart';
import 'package:flutter_intl_phone_field/countries.dart';

bool isNumeric(String s) =>
    s.isNotEmpty && int.tryParse(s.replaceAll("+", "")) != null;

String removeDiacritics(String str) {
  var withDia =
      'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
  var withoutDia =
      'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

  for (int i = 0; i < withDia.length; i++) {
    str = str.replaceAll(withDia[i], withoutDia[i]);
  }

  return str;
}

extension CountryExtensions on List<Country> {
  List<Country> stringSearch(String search) {
    search = removeDiacritics(search.toLowerCase());
    return where(
      (country) => isNumeric(search) || search.startsWith("+")
          ? country.dialCode.contains(search)
          : removeDiacritics(country.name.replaceAll("+", "").toLowerCase())
                  .contains(search) ||
              country.nameTranslations.values.any((element) =>
                  removeDiacritics(element.toLowerCase()).contains(search)),
    ).toList();
  }
}

extension RemoveCountryCode on String {
  // remove country code from the initial number value
  String removeCountryCode(
    String? countryCode,
    Country selectedCountry,
    List<Country> countryList,
  ) {
    String number = this;
    debugPrint("number: $number");
    if (countryCode == null && number.startsWith('+')) {
      number = number.substring(1);
      // parse initial value
      selectedCountry = countries.firstWhere(
          (country) => number.startsWith(country.fullCountryCode),
          orElse: () => countryList.first);
      debugPrint("selectedCountry: $selectedCountry");
      // remove country code from the initial number value
      number = number.replaceFirst(
          RegExp("^${selectedCountry.fullCountryCode}"), "");
      return number;
    } else {
      selectedCountry = countryList.firstWhere(
          (item) => item.code == (countryCode ?? 'IN'),
          orElse: () => countryList.first);

      // remove country code from the initial number value
      if (number.startsWith('+')) {
        number = number.replaceFirst(
            RegExp("^\\+${selectedCountry.fullCountryCode}"), "");
      } else {
        number = number.replaceFirst(
            RegExp("^${selectedCountry.fullCountryCode}"), "");
      }
      return number;
    }
  }
}
