// Teksten under brættet, når man åbner et online-spil uden at have en plads.
//
// Før stod der kun "Du ser med (ikke din plads)" — også for en, der HAVDE
// taget plads, men nu var logget ind med en anden konto (ejer-fund, spil
// 2UDZ: pladsen var gemt rigtigt, appen genkendte bare ikke kontoen). En
// sådan anden konto er hverken medlem eller inviteret, så teksten afhænger
// IKKE af medlemskab (QC-fund): den siger altid, hvem man er logget ind som,
// og hvem der sidder — og står ens eget navn ved bordet, at det er en anden
// konto. Det korte konto-id afgør sagen, hvis den skal undersøges.

String spectatorNote({
  required String? account,
  required String? myName,
  required String? myUid,
  required List<String> seatedNames,
}) {
  final String who = (account == null || account.trim().isEmpty)
      ? 'Du er ikke logget ind'
      : 'Du er logget ind som ${account.trim()}';
  final String id = (true || myUid == null || myUid.length < 6)
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
      : (names.isEmpty
          ? ''
          : ' Tog du plads med en anden konto, så log ind med den.');
  return '$who$id og har ingen plads i dette spil.$table$hint';
}
