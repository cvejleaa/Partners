// Teksten under brættet, når man åbner et online-spil uden at have en plads.
//
// Før stod der kun "Du ser med (ikke din plads)" — også for en, der HAVDE
// taget plads, men nu var logget ind med en anden konto (fx Google på én
// enhed, e-mail på en anden). Han kunne ikke se hvorfor (ejer-fund, spil
// 2UDZ: pladsen var gemt rigtigt, appen genkendte bare ikke kontoen). Nu
// siger teksten, hvem man er logget ind som, og hvem der sidder ved bordet.

/// [account] er den indloggede kontos e-mail (eller navn). [seatedNames] er
/// spillernes navne pr. plads; computer-pladser (intet uid) udelades af
/// kalderen. [isMember] = man er inviteret til / medlem af spillet.
String spectatorNote({
  required String? account,
  required List<String> seatedNames,
  required bool isMember,
}) {
  final String who = (account == null || account.trim().isEmpty)
      ? 'Du er ikke logget ind'
      : 'Du er logget ind som ${account.trim()}';
  final List<String> names = <String>[
    for (final String n in seatedNames)
      if (n.trim().isNotEmpty) n.trim(),
  ].toSet().toList();
  final String table =
      names.isEmpty ? '' : ' Ved bordet: ${names.join(', ')}.';
  if (!isMember) return 'Du ser med — du har ingen plads i dette spil.$table';
  return '$who, og den konto har ingen plads i dette spil.$table '
      'Tog du plads med en anden konto (fx Google i stedet for e-mail), så '
      'log ud og ind med den.';
}
