import '../models/variant_config.dart';

// Lobbyens fire pladser som rene lister — uden Firestore — så reglerne for
// "hvem sidder hvor" kan testes direkte og kun findes ét sted.
//
// Partners Duo: fire pladser på brættet, men kun to spillere. Plads 2 og 3 er
// SPEJLE af 0 og 1 (samme uid, navn, farve og AI-markering) — samme format
// som lokale Duo-spil gemmer. Et spejl kan aldrig vælges for sig: alle
// skrivninger går gennem [LobbySeats.mirrored].

/// En lobby-handling, der ikke kan lade sig gøre. [message] vises for brugeren.
class LobbyError implements Exception {
  const LobbyError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Tekst på en tom plads.
const String kOpenSeatName = 'Åben';

/// Standard-paletten (rød, blå, grøn, gul) — OnlineService.kPalette peger hertil.
const List<int> kLobbyPalette = <int>[
  0xFFE53935,
  0xFF1E88E5,
  0xFF43A047,
  0xFFFDD835,
];

class LobbySeats {
  LobbySeats({
    required this.uids,
    required this.names,
    required this.colors,
    required this.aiSeats,
  });

  /// Læs pladserne fra et lobby-doc. Skæve/korte lister fyldes op til fire.
  factory LobbySeats.fromDoc(Map<String, dynamic> d) {
    List<dynamic> four(dynamic raw, dynamic fill) {
      final List<dynamic> l =
          raw is List ? List<dynamic>.from(raw) : <dynamic>[];
      while (l.length < 4) {
        l.add(fill);
      }
      return l.sublist(0, 4);
    }

    return LobbySeats(
      uids: four(d['uids'], null),
      names: four(d['names'], kOpenSeatName),
      colors: four(d['colors'], kLobbyPalette[0])
          .map((dynamic c) => c is num ? c.toInt() : kLobbyPalette[0])
          .toList(),
      aiSeats: four(d['aiSeats'], false)
          .map((dynamic a) => a == true)
          .toList(),
    );
  }

  final List<dynamic> uids;
  final List<dynamic> names;
  final List<int> colors;
  final List<bool> aiSeats;

  Map<String, dynamic> toUpdate() => <String, dynamic>{
        'uids': uids,
        'names': names,
        'colors': colors,
        'aiSeats': aiSeats,
      };

  /// Kopi hvor hver plads, der ikke har en hånd, bærer sin styrende plads'
  /// data. Klassisk: uændret kopi.
  LobbySeats mirrored(VariantConfig v) {
    final LobbySeats c = copy();
    for (int s = 0; s < 4; s++) {
      final int ctl = v.controllerOf(s);
      if (ctl == s) continue;
      c.uids[s] = c.uids[ctl];
      c.names[s] = c.names[ctl];
      c.colors[s] = c.colors[ctl];
      c.aiSeats[s] = c.aiSeats[ctl];
    }
    return c;
  }

  LobbySeats copy() => LobbySeats(
        uids: List<dynamic>.from(uids),
        names: List<dynamic>.from(names),
        colors: List<int>.from(colors),
        aiSeats: List<bool>.from(aiSeats),
      );

  /// De forskellige mennesker, i plads-orden.
  List<String> get humans => <String>[
        for (final dynamic u in uids)
          if (u is String) u,
      ].toSet().toList();

  /// [uid] tager [seat]. En eventuel anden plads, [uid] sad på, frigøres
  /// (pladsskift). Duo: kun en plads med hånd kan vælges; spejlet følger med.
  LobbySeats join(VariantConfig v, int seat, String uid, String name,
      int color) {
    if (seat < 0 || seat > 3) throw const LobbyError('Ukendt plads');
    if (!v.hasHand(seat)) {
      throw const LobbyError('Duo er 1 mod 1 — vælg en af de to pladser');
    }
    final dynamic taken = uids[seat];
    if (taken != null && taken != uid) {
      throw const LobbyError('Pladsen er taget');
    }
    final LobbySeats c = copy();
    for (int i = 0; i < 4; i++) {
      if (c.uids[i] == uid && i != seat) {
        c.uids[i] = null;
        c.names[i] = kOpenSeatName;
      }
    }
    c.uids[seat] = uid;
    c.names[seat] = name;
    c.colors[seat] = color;
    c.aiSeats[seat] = false;
    return c.mirrored(v);
  }

  /// Værten markerer [seat] som computer (eller fortryder). Duo: spejlet
  /// følger med, og kun en plads med hånd kan vælges.
  LobbySeats fillAi(VariantConfig v, int seat, bool ai) {
    if (seat < 0 || seat > 3) throw const LobbyError('Ukendt plads');
    if (!v.hasHand(seat)) {
      throw const LobbyError('Duo er 1 mod 1 — vælg en af de to pladser');
    }
    if (uids[seat] != null) {
      throw const LobbyError('Pladsen er taget af en spiller');
    }
    final LobbySeats c = copy();
    c.aiSeats[seat] = ai;
    c.names[seat] = ai ? 'Computer' : kOpenSeatName;
    return c.mirrored(v);
  }

  /// Pladserne efter et skift af variant fra [from] til [to].
  ///
  /// - TIL en variant, hvor spillere deler pladser (Duo): højst to mennesker.
  ///   Den, der allerede sidder på en hånd-plads (0/1), bliver; de øvrige
  ///   MENNESKER flyttes til de ledige hånd-pladser (med farve) FØR en
  ///   computer-plads får en, og pladserne spejles. Ellers [LobbyError].
  /// - FRA sådan en variant: spejlene ryddes, så de kan tages af nye
  ///   spillere, og får de to farver, de to spillere ikke har.
  /// - Mellem varianter uden delte pladser: uændret.
  LobbySeats switchVariant(VariantConfig from, VariantConfig to) {
    if (to.seatsShareController) {
      final List<String> h = humans;
      final int hands = to.handCount(4);
      if (h.length > hands) {
        throw LobbyError('${to.name} er 1 mod 1 — der sidder ${h.length} '
            'spillere. Bed nogen om at forlade lobbyen først.');
      }
      final LobbySeats c = copy();
      // Hvem skal sidde på hvilken hånd-plads? Folk, der allerede sidder på en
      // hånd-plads, bliver; de øvrige flyttes til de ledige hånd-pladser.
      final List<int> handSeats = <int>[
        for (int s = 0; s < 4; s++)
          if (to.hasHand(s)) s,
      ];
      final List<int> free = <int>[
        for (final int s in handSeats)
          if (c.uids[s] == null && !c.aiSeats[s]) s,
      ];
      // To pas: MENNESKER først, så computere. I plads-rækkefølge kunne en
      // computer på plads 2 tage den sidste ledige hånd-plads fra en gæst på
      // plads 3 — og gæsten forsvandt tavst fra bordet (QC-fund).
      for (int s = 0; s < 4; s++) {
        if (to.hasHand(s)) continue;
        final dynamic u = c.uids[s];
        final bool alreadySeated =
            u != null && handSeats.any((int hs) => c.uids[hs] == u);
        if (u != null && !alreadySeated && free.isNotEmpty) {
          final int t = free.removeAt(0);
          c.uids[t] = u;
          c.names[t] = c.names[s];
          c.colors[t] = c.colors[s];
          c.aiSeats[t] = false;
        }
      }
      for (int s = 0; s < 4; s++) {
        if (to.hasHand(s)) continue;
        if (c.uids[s] == null && c.aiSeats[s] && free.isNotEmpty) {
          final int t = free.removeAt(0);
          c.aiSeats[t] = true;
          c.names[t] = c.names[s];
        }
      }
      return c.mirrored(to);
    }
    if (from.seatsShareController) {
      final LobbySeats c = copy();
      for (int s = 0; s < 4; s++) {
        if (from.hasHand(s)) continue;
        c.uids[s] = null;
        c.names[s] = kOpenSeatName;
        c.aiSeats[s] = false;
      }
      final Set<int> used = <int>{
        for (int s = 0; s < 4; s++)
          if (from.hasHand(s)) c.colors[s],
      };
      final List<int> rest = <int>[
        for (final int p in kLobbyPalette)
          if (!used.contains(p)) p,
      ];
      for (int s = 0; s < 4; s++) {
        if (from.hasHand(s)) continue;
        if (rest.isNotEmpty) c.colors[s] = rest.removeAt(0);
      }
      return c;
    }
    return copy();
  }
}

/// Pladser, der skal fyldes (af et menneske eller en computer), før spillet
/// kan startes: pladser MED en hånd — i Duo to, ikke fire.
List<int> lobbyPlayableSeats(VariantConfig v) => <int>[
      for (int s = 0; s < 4; s++)
        if (v.hasHand(s)) s,
    ];

/// Antal spilbare pladser, der hverken har en spiller eller en computer. Den
/// ENE tælling, lobby-skærmen og "Mine spil" begge bruger.
int lobbyOpenSeats(
    VariantConfig v, List<dynamic> uids, List<dynamic> aiSeats) {
  int open = 0;
  for (final int s in lobbyPlayableSeats(v)) {
    final bool human = s < uids.length && uids[s] != null;
    final bool ai = s < aiSeats.length && aiSeats[s] == true;
    if (!human && !ai) open++;
  }
  return open;
}

/// Navnene på spillerne — én gang pr. SPILLER (hånd-plads), aldrig to gange
/// for en Duo-spiller, der sidder på to pladser. Tomme pladser udelades.
List<String> playerNamesOnce(VariantConfig v, List<dynamic> names) =>
    <String>[
      for (final int s in lobbyPlayableSeats(v))
        if (s < names.length &&
            names[s] is String &&
            names[s] != kOpenSeatName)
          names[s] as String,
    ];

/// Antal spilbare pladser, der HAR en spiller eller en computer. Den ENE
/// tælling, "kan startes" (lobbyCanStart), startknappen og hjælpeteksten
/// bruger — ellers kunne de tre blive uenige.
int lobbyFilledSeats(
        VariantConfig v, List<dynamic> uids, List<dynamic> aiSeats) =>
    lobbyPlayableSeats(v).length - lobbyOpenSeats(v, uids, aiSeats);

/// Hjælpelinjen under startknappen — det, der er SANDT lige nu, med skærmens
/// egne ord ("Fyld med AI", "Invitér spiller"). null = ingen linje.
///
/// Før stod "Tomme pladser bliver til computer-spillere ved start" også, når
/// værten sad alene og ikke kunne starte (ejer-fund): de tomme pladser
/// blev netop IKKE fyldt.
String? lobbyStartHint(VariantConfig v, int filled, int open) {
  if (filled < 2) {
    return v.seatsShareController
        ? '${v.name} er 1 mod 1 — invitér din modstander, eller tryk '
            '"Fyld med AI" på din modstanders plads.'
        : 'Mindst 2 spillere — invitér en spiller, eller tryk '
            '"Fyld med AI" på en plads.';
  }
  if (open > 0) return 'Tomme pladser bliver til computer-spillere ved start.';
  return null;
}
