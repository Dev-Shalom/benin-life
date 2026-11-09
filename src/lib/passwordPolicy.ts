// Password rules for NEW passwords (sign up, choose a new password). Sign-in never uses this: existing players keep logging in
// with the password they already have. The server enforces the length too (auth minimum_password_length, docs/SECURITY.md).

export const MIN_PASSWORD_LENGTH = 8;

/** A few very common passwords. Compared in lower case. */
const COMMON = new Set([
  '123456789', 'password', 'qwerty123', '11111111', 'abcdefgh', 'iloveyou', '12345678', '87654321', 'password1', 'benincity',
]);

/** Plain-words reason the password is not allowed, or null when it is fine. */
export function passwordProblem(pw: string): string | null {
  if (pw.length < MIN_PASSWORD_LENGTH) return `Your password needs at least ${MIN_PASSWORD_LENGTH} characters.`;
  if (/^[0-9]+$/.test(pw)) return 'Your password cannot be only numbers. Add some letters.';
  if (COMMON.has(pw.toLowerCase())) return 'That password is too easy to guess. Pick something harder.';
  return null;
}
