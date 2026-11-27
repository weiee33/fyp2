const newPasswordLengthHint = 'Use 12–128 characters';

String? validateNewPassword(String? value) {
  final length = value?.length ?? 0;
  return length >= 12 && length <= 128 ? null : newPasswordLengthHint;
}

void requireNewPassword(String password) {
  final error = validateNewPassword(password);
  if (error != null) throw FormatException(error);
}
