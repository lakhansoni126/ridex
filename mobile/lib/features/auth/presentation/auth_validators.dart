/// Client-side validation mirroring the API rules, so users get instant
/// feedback instead of a round trip.
library;

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _usernameRe = RegExp(r'^[a-z0-9_.]{3,32}$');

String? validateEmail(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return 'Enter your email';
  if (value.length > 320 || !_emailRe.hasMatch(value)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? validateUsername(String? v) {
  final value = (v ?? '').trim().toLowerCase();
  if (value.length < 3) return 'At least 3 characters';
  if (value.length > 32) return 'At most 32 characters';
  if (!_usernameRe.hasMatch(value)) {
    return 'Letters, numbers, dots and underscores only';
  }
  return null;
}

String? validatePassword(String? v) {
  final value = v ?? '';
  if (value.length < 8) return 'At least 8 characters';
  if (value.length > 128) return 'At most 128 characters';
  return null;
}

String? validateDisplayName(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return 'Enter your name';
  if (value.length > 60) return 'At most 60 characters';
  return null;
}
