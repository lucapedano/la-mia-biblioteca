String? normalizeIsbn(String input) {
  final isbn = input.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();

  if (isbn.length == 13 &&
      (isbn.startsWith('978') || isbn.startsWith('979')) &&
      RegExp(r'^\d{13}$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
    }
    return (sum + int.parse(isbn[12])) % 10 == 0 ? isbn : null;
  }

  if (isbn.length == 10 &&
      RegExp(r'^\d{9}[\dX]$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final digit = isbn[i] == 'X' ? 10 : int.parse(isbn[i]);
      sum += digit * (10 - i);
    }
    return sum % 11 == 0 ? isbn : null;
  }

  return null;
}
