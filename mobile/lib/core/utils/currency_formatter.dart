import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(double? amount) {
    if (amount == null) return '₹0.00';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(amount);
  }

  static String formatWithoutSymbol(double? amount) {
    if (amount == null) return '0.00';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '',
      decimalDigits: 2,
    ).format(amount).trim();
  }

  static String formatCompact(double? amount) {
    if (amount == null) return '₹0';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(amount);
  }

  static String formatPlain(double? amount) {
    if (amount == null) return '0.00';
    return amount.toStringAsFixed(2);
  }
}
