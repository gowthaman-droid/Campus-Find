import 'constants.dart';

/// Form validators. Each one returns an error sentence, or null when the
/// value is fine - exactly what `TextFormField(validator: ...)` expects.
class Validators {
  Validators._();

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9]{7,15}$');

  /// Value must not be empty.
  static String? Function(String?) notEmpty(String label) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return '$label is required';
      }
      return null;
    };
  }

  /// Value is required and must have between [min] and [max] characters.
  static String? Function(String?) lengthBetween(
    String label,
    int min,
    int max,
  ) {
    return (String? value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) {
        return '$label is required';
      }
      if (text.length < min) {
        return '$label must be at least $min characters';
      }
      if (text.length > max) {
        return '$label must be at most $max characters';
      }
      return null;
    };
  }

  /// Value may be empty, but if present must be at most [max] characters.
  static String? Function(String?) optionalMax(String label, int max) {
    return (String? value) {
      final text = value?.trim() ?? '';
      if (text.length > max) {
        return '$label must be at most $max characters';
      }
      return null;
    };
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'E-mail is required';
    }
    if (!_emailPattern.hasMatch(text)) {
      return 'Enter a valid e-mail address';
    }
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Password is required';
    }
    if (text.length < AppConstants.passwordMin) {
      return 'Password must be at least ${AppConstants.passwordMin} characters';
    }
    return null;
  }

  /// [original] reads the first password field when the check runs.
  static String? Function(String?) confirmPassword(String Function() original) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return 'Please repeat the password';
      }
      if (value != original()) {
        return 'Passwords do not match';
      }
      return null;
    };
  }

  static String? fullName(String? value) {
    return lengthBetween(
      'Full name',
      AppConstants.personNameMin,
      AppConstants.personNameMax,
    )(value);
  }

  static String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) {
      return 'Phone number is required';
    }
    if (!_phonePattern.hasMatch(digits)) {
      return 'Enter a valid phone number (7 to 15 digits)';
    }
    return null;
  }

  static String? itemName(String? value) {
    return lengthBetween(
      'Item name',
      AppConstants.itemNameMin,
      AppConstants.itemNameMax,
    )(value);
  }

  static String? description(String? value) {
    return lengthBetween(
      'Description',
      AppConstants.descriptionMinUi,
      AppConstants.descriptionMax,
    )(value);
  }

  static String? claimMessage(String? value) {
    return lengthBetween(
      'Message',
      AppConstants.claimMessageMin,
      AppConstants.claimMessageMax,
    )(value);
  }

  static String? verificationDetails(String? value) {
    return lengthBetween(
      'Proof of ownership',
      AppConstants.verificationMin,
      AppConstants.verificationMax,
    )(value);
  }

  /// Used by dropdowns (category, campus area).
  static String? Function(String?) choice(String label) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return 'Please choose a $label';
      }
      return null;
    };
  }
}
