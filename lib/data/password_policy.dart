// ─────────────────────────────────────────────────────────────────────────────
// New-password policy.
//
// Mirrors the backend rule in `backend/app/passwords.py` so the meter can warn
// before the request is sent. The server remains the authority; a field error
// from the 422 response is still shown inline when the two disagree.
// ─────────────────────────────────────────────────────────────────────────────

/// A small built-in list, deliberately not a breach corpus. Keep it in step
/// with the backend's COMMON_PASSWORDS.
const Set<String> _commonPasswords = <String>{
  '1234567890',
  '123456789',
  '12345678',
  'password',
  'password1',
  'password123',
  'password123!',
  'qwerty',
  'qwerty123',
  'qwertyuiop',
  'letmein',
  'welcome',
  'welcome1',
  'admin',
  'admin123',
  'iloveyou',
  'monkey',
  'dragon',
  'football',
  'baseball',
  'abc123',
  '111111',
  '123123',
  '000000',
  'sunshine',
  'princess',
  'trustno1',
  'master',
  'shadow',
  'superman',
  'batman',
  'starwars',
  'whatever',
  'freedom',
  'hello',
  'charlie',
  'donald',
  'passw0rd',
  'p@ssw0rd',
  '1q2w3e4r',
  'zaq12wsx',
  'tutormatch',
  'tutormatch1',
  'tutormatch123',
};

final RegExp _lower = RegExp(r'[a-z]');
final RegExp _upper = RegExp(r'[A-Z]');
final RegExp _digit = RegExp(r'\d');
final RegExp _symbol = RegExp(r'[^A-Za-z0-9\s]');
final RegExp _nameSeparators = RegExp(r"[\s\-'.]+");

class PasswordAssessment {
  const PasswordAssessment({
    required this.error,
    required this.score,
    required this.label,
  });

  /// The first rule the password breaks, phrased as an instruction. Null means
  /// the client-side policy is satisfied.
  final String? error;

  /// 0–4, used only by the meter.
  final int score;

  /// A short human label for the meter.
  final String label;

  bool get isAcceptable => error == null;
}

PasswordAssessment assessNewPassword(
  String password, {
  required String email,
  required String name,
}) {
  final String folded = password.toLowerCase();
  final String localPart = email.trim().toLowerCase().split('@').first;
  final String trimmedName = name.trim().toLowerCase();
  final List<String> nameTokens = trimmedName
      .split(_nameSeparators)
      .where((String token) => token.length >= 3)
      .toList(growable: false);

  String? error;
  if (password.length < 10) {
    error = 'Use at least 10 characters.';
  } else if (!_lower.hasMatch(password)) {
    error = 'Add a lower-case letter.';
  } else if (!_upper.hasMatch(password)) {
    error = 'Add an upper-case letter.';
  } else if (!_digit.hasMatch(password)) {
    error = 'Add a digit.';
  } else if (!_symbol.hasMatch(password)) {
    error = 'Add a symbol, such as ! or ?.';
  } else if (_commonPasswords.contains(folded)) {
    error = 'Choose a less common password.';
  } else if (localPart.length >= 3 && folded.contains(localPart)) {
    error = 'Do not use your email address in the password.';
  } else if (trimmedName.length >= 3 && folded.contains(trimmedName)) {
    error = 'Do not use your name in the password.';
  } else {
    for (final String token in nameTokens) {
      if (folded.contains(token)) {
        error = 'Do not use your name in the password.';
        break;
      }
    }
  }

  int score = 0;
  if (password.length >= 10) score++;
  if (_lower.hasMatch(password) && _upper.hasMatch(password)) score++;
  if (_digit.hasMatch(password)) score++;
  if (_symbol.hasMatch(password)) score++;

  // A password that breaks a policy rule should not read as strong just
  // because it happens to contain every character class.
  final int filled = error == null ? score : 0;

  return PasswordAssessment(
    error: error,
    score: filled,
    label: switch (filled) {
      <= 1 => 'Too weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    },
  );
}
