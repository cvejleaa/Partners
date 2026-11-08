// Hvem må slette et online-spil, og hvor svært skal det være? Den ENE regel —
// lobbyens og spilskærmens "⋮"-menu læser den. Serveren har sin egen
// (firestore.rules: allow delete), og den må aldrig være mere gavmild end
// denne.

/// Hvordan et spil kan slettes af den, der ser det.
enum DeleteMode {
  /// Kan ikke slettes herfra (ikke vært/admin, eller spillet er afsluttet —
  /// et afsluttet spil bærer alle deltageres statistik).
  none,

  /// En lobby: intet er spillet endnu — en almindelig bekræftelse.
  simple,

  /// Et spil i gang: man skal skrive spillets kode for at slette. Et tryk
  /// ved et uheld må ikke kunne koste fire spillere deres parti (ejer-fund:
  /// sletteknappen var for let at ramme).
  typeCode,
}

/// Genkendt POSITIVT på status: kun 'lobby' og 'playing' kan slettes; alt
/// andet ('over', manglende, skævt) giver [DeleteMode.none].
DeleteMode deleteModeFor({
  required String? hostUid,
  required String? myUid,
  required bool isAdmin,
  required String? status,
}) {
  final bool mayDelete = isAdmin || myUid != null;
  if (!mayDelete) return DeleteMode.none;
  switch (status) {
    case 'lobby':
      return DeleteMode.simple;
    case 'playing':
      return DeleteMode.typeCode;
    default:
      return DeleteMode.none;
  }
}

/// Har brugeren skrevet spillets kode? Mellemrum og store/små bogstaver er
/// ligegyldige.
bool deleteCodeMatches(String typed, String code) =>
    typed.trim().toUpperCase() == code.trim().toUpperCase();

/// De MENNESKER (ud over én selv), der mister partiet — til advarslen.
/// Navne fra spil-doc'et; AI-pladser (intet uid) og ens egne pladser udelades,
/// og en Duo-spiller nævnes én gang.
List<String> playersWhoLoseTheGame(
    List<dynamic> names, List<dynamic> uids, String? myUid) {
  final List<String> out = <String>[];
  final Set<dynamic> seen = <dynamic>{};
  for (int i = 0; i < uids.length && i < names.length; i++) {
    final dynamic u = uids[i];
    if (u == null || u == myUid || !seen.add(u)) continue;
    out.add('${names[i]}');
  }
  return out;
}
