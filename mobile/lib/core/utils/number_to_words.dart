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
    final hundred = (n ~/ 100) % 10;
    final rest = n % 100;
    if (hundred > 0 && hundred < _units.length) str += '${_units[hundred]} Hundred';
    if (rest > 0) str += '${str.isNotEmpty ? ' ' : ''}${_convertTwoDigits(rest)}';
    return str;
  }

  static String convert(double amount) {
    if (amount.isNaN || amount.isInfinite) return 'Rupees Zero Only';
    if (amount == 0) return 'Rupees Zero Only';
    if (amount < 0) return 'Minus ${convert(amount.abs())}';

    final totalPaise = (amount * 100).round();
    final rupees = totalPaise ~/ 100;
    final paise = totalPaise % 100;

    var words = '';

    final crores = rupees ~/ 10000000;
    var remainder = rupees % 10000000;

    final lakhs = remainder ~/ 100000;
    remainder %= 100000;

    final thousands = remainder ~/ 1000;
    remainder %= 1000;

    if (crores > 0) {
      if (crores < 1000) {
        words += '${_convertThreeDigits(crores)} Crore ';
      } else {
        final cThousand = crores ~/ 1000;
        final cRest = crores % 1000;
        final cRestStr = cRest > 0 ? ' ${_convertThreeDigits(cRest)}' : '';
        words += '${_convertThreeDigits(cThousand)} Thousand$cRestStr Crore ';
      }
    }
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
