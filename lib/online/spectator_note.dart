// Teksten under brættet, når man åbner et online-spil uden at have en plads.
//
// Før stod der kun "Du ser med (ikke din plads)" — også for en, der HAVDE
// taget plads, men nu var logget ind med en anden konto (ejer-fund, spil
// 2UDZ: pladsen var gemt rigtigt, appen genkendte bare ikke kontoen). En
// sådan anden konto er hverken medlem eller inviteret, så konto-hintet
// afhænger af om ens eget NAVN står ved bordet, ikke af medlemskab (QC-fund).
// Og en inviteret, der aldrig tog plads (spil 2UDZ, ejer-fund), får at vide
// netop det — ikke et hint om en anden konto. Rækkefølgen: eget navn ved
// bordet (anden konto) > inviteret uden plads > almindelig tilskuer.

String spectatorNote({
  required String? account,
  required String? myName,
  required String? myUid,
  required List<String> seatedNames,
  bool invited = false,
}) {
  final String who = (account == null || account.trim().isEmpty)
      ? 'Du er ikke logget ind'
      : 'Du er logget ind som ${account.trim()}';
  final String id = (myUid == null || myUid.length < 6)
      ? ''
      : ' (konto-id …${myUid.substring(myUid.length - 6)})';
  final List<String> names = <String>[
    for (final String n in seatedNames)
      if (n.trim().isNotEmpty) n.trim(),
  ].toSet().toList();
  final String table =
      names.isEmpty ? '' : ' Ved bordet: ${names.join(', ')}.';
  final String me = (myName ?? '').trim();
  final bool nameAtTable = me.isNotEmpty && names.contains(me);
  final String hint = nameAtTable
      ? ' "$me" sidder ved bordet — men med en ANDEN konto. Log ud, og log '
          'ind med den, du tog plads med (fx Google i stedet for e-mail).'
      : ('');
  return '$who$id og har ingen plads i dette spil.$table$hint';
}
