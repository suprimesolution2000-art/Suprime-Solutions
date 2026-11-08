import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _compactFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _withoutSymbolFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '',
    decimalDigits: 2,
  );

  static String format(double? amount) {
    if (amount == null) return '₹0.00';
    return _formatter.format(amount);
  }

  static String formatWithoutSymbol(double? amount) {
    if (amount == null) return '0.00';
    return _withoutSymbolFormatter.format(amount).trim();
  }

  static String formatCompact(double? amount) {
    if (amount == null) return '₹0';
    return _compactFormatter.format(amount);
  }

  static String formatPlain(double? amount) {
    if (amount == null) return '0.00';
    return amount.toStringAsFixed(2);
  }
}
