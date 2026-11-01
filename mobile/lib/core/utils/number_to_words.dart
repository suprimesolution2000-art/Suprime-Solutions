class NumberToWords {
  static const List<String> _units = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen'
  ];

  static const List<String> _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety'
  ];

  static String _convertTwoDigits(int n) {
    if (n < 20) return _units[n];
    final unit = n % 10;
    return '${_tens[n ~/ 10]}${unit != 0 ? ' ${_units[unit]}' : ''}';
  }

  static String _convertThreeDigits(int n) {
    var str = '';
    final hundred = n ~/ 100;
    final rest = n % 100;
    if (hundred > 0) str += '${_units[hundred]} Hundred';
    if (rest > 0) str += '${str.isNotEmpty ? ' ' : ''}${_convertTwoDigits(rest)}';
    return str;
  }

  static String convert(double amount) {
    if (amount == 0) return 'Rupees Zero Only';

    final rounded = (amount * 100).round() / 100;
    final rupees = rounded.floor();
    final paise = ((rounded - rupees) * 100).round();

    var words = '';

    final crores = rupees ~/ 10000000;
    var remainder = rupees % 10000000;

    final lakhs = remainder ~/ 100000;
    remainder %= 100000;

    final thousands = remainder ~/ 1000;
    remainder %= 1000;

    if (crores > 0) words += '${_convertThreeDigits(crores)} Crore ';
    if (lakhs > 0) words += '${_convertThreeDigits(lakhs)} Lakh ';
    if (thousands > 0) words += '${_convertThreeDigits(thousands)} Thousand ';
    if (remainder > 0) words += '${_convertThreeDigits(remainder)} ';

    words = words.trim();
    var result = words.isNotEmpty ? 'Rupees $words' : 'Rupees Zero';

    if (paise > 0) {
      result += ' and ${_convertTwoDigits(paise)} Paise';
    }

    return '$result Only';
  }
}
