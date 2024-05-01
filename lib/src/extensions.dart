

extension NullableStringExtensions<E> on String? {
  /// Returns `true` if this string is `null` or empty.
  bool get isNullOrEmpty {
    return this?.isEmpty ?? true;
  }

  /// Returns `true` if this string is not `null` and not empty.
  bool get isNotNullNorEmpty {
    return this?.isNotEmpty ?? false;
  }
}

extension StringExtension on String {
  List<String> controlledSplit(
      String separator, {
        int max = 1,
        bool includeSeparator = false,
      }) {
    String string = this;
    List<String> result = [];

    if (separator.isEmpty) {
      result.add(string);
      return result;
    }

    while (true) {
      var index = string.indexOf(separator, 0);
      if (index == -1 || (max > 0 && result.length >= max)) {
        result.add(string);
        break;
      }

      result.add(string.substring(0, index));
      if (includeSeparator) {
        result.add(separator);
      }
      string = string.substring(index + separator.length);
    }
    return result;
  }
}