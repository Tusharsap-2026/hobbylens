/// Bangladeshi mobile numbers: 01[3-9]XXXXXXXX. Accepts Bangla digits and common separators.
/// Returns the number as +8801XXXXXXXXX, or null when it is not a valid mobile number.
String? normaliseBdMobile(String input) {
  const bangla = '০১২৩৪৫৬৭৮৯';
  final buffer = StringBuffer();
  for (final ch in input.split('')) {
    final i = bangla.indexOf(ch);
    if (i >= 0) {
      buffer.write(i);
    } else if (RegExp(r'\d').hasMatch(ch)) {
      buffer.write(ch);
    }
  }
  var n = buffer.toString();
  if (n.startsWith('00880')) n = n.substring(2);
  if (n.startsWith('01') && n.length == 11) n = '88$n';
  if (!RegExp(r'^8801[3-9]\d{8}$').hasMatch(n)) return null;
  return '+$n';
}
