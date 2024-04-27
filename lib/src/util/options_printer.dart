

import 'dart:math';

import '../log.dart';

class OptionsPrinter {

  Map<String,String> options = {};
  int maxLength = 1;

  void add(String option, String defaultValue) {
    if (option.length > maxLength) {
      maxLength = option.length;
    }
    options[option] = defaultValue;
  }

  void print() {
    int column = maxLength + 10;
    options.forEach((key, value) {
      String spacer = ' ' * (column - key.length);
      Log.info(' $key$spacer$value');
    });
  }

}