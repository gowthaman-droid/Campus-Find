import 'package:intl/intl.dart';

import 'constants.dart';

/// Turns dates, scores and phone numbers into text for the screens.
class Fmt {
  Fmt._();

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');
  static final DateFormat _timeFormat = DateFormat('h:mm a');

  static String date(DateTime value) => _dateFormat.format(value.toLocal());

  static String time(DateTime value) => _timeFormat.format(value.toLocal());

  static String dateTime(DateTime value) => '${date(value)}, ${time(value)}';

  /// "just now", "5 min ago", "3 h ago", "2 d ago", otherwise the date.
  static String timeAgo(DateTime value, {DateTime? now}) {
    final difference = (now ?? DateTime.now()).difference(value);
    if (difference.isNegative || difference.inSeconds < 45) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} h ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} d ago';
    }
    return date(value);
  }

  static String score(int value) => '$value%';

  /// Words that go with a match score.
  static String scoreLabel(int value) {
    if (value >= AppConstants.strongMatchThreshold) {
      return 'Strong match';
    }
    if (value >= AppConstants.matchThreshold) {
      return 'Possible match';
    }
    return 'Weak match';
  }

  /// Keeps digits and a leading "+", removing spaces, dashes and brackets.
  static String normalizePhone(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s\-()]'), '');
    return cleaned.trim();
  }

  /// "Asha Kumar" -> "AK"
  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// "Black wallet" -> "Black wallet", "" -> "Unnamed item".
  static String itemTitle(String name) {
    final text = name.trim();
    return text.isEmpty ? 'Unnamed item' : text;
  }
}
