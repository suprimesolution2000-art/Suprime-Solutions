import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateDisplayFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');

  static String format(DateTime? date) {
    if (date == null) return '';
    return _dateFormat.format(date);
  }

  static String formatDisplay(DateTime? date) {
    if (date == null) return '';
    return _dateDisplayFormat.format(date);
  }

  static String formatDateTime(DateTime? date) {
    if (date == null) return '';
    return '${_dateDisplayFormat.format(date)}, ${_timeFormat.format(date)}';
  }

  static DateTime? tryParse(String? str) {
    if (str == null || str.isEmpty) return null;
    try {
      return DateTime.parse(str);
    } catch (_) {
      try {
        return _dateFormat.parse(str);
      } catch (_) {
        return null;
      }
    }
  }
}
