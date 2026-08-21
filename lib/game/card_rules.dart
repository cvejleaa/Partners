import '../models/playing_card.dart';

/// Konfigurerbare funktioner for ét kort (én rang).
///
/// Bruges af [Rules] i stedet for hardkodede rang-regler, så funktionerne kan
/// justeres fra admin-skærmen.
class CardRuleConfig {
  const CardRuleConfig({
    this.exitStart = false,
    this.forwardSteps = const <int>[],
    this.backwardSteps,
    this.splitTotal,
    this.swap = false,
    this.jumpsBlockade = false,
    this.seqForward,
    this.seqBackward,
    this.multiPieces,
    this.multiSteps,
  });

  /// Kan rykke en brik ud af start (til eget ud-felt).
  final bool exitStart;

  /// Antal felter kortet kan rykke frem (fx [1, 11] for Es). Tom = ingen.
  final List<int> forwardSteps;

  /// Antal felter kortet kan rykke baglæns. null = kan ikke rykke tilbage.
  final int? backwardSteps;

  /// Total antal felter der kan deles over flere egne brikker (7'eren).
  /// null = ingen split.
  final int? splitTotal;

  /// Kan bytte to brikker på banen (klassisk Knægt).
  final bool swap;

  /// Må PASSERE et blokeret fremmed startfelt (UD-felt med en brik på) under en
  /// fremad-bevægelse — "Hopsakortet" 5↷ i Partners+/Duo/25 år. Klassisk: false
  /// (en brik på sit eget UD-felt spærrer passage for alle andre). Gælder kun
  /// fremad-skridt (ikke baglæns/split).
  final bool jumpsBlockade;

  /// Sekvens-træk (25 års "7 ELLER +2−5"): SAMME brik rykker [seqForward] frem
  /// (rigtig landing — enlig modstander slås hjem) og derefter [seqBackward]
  /// tilbage. Begge skal være sat for at gælde — se [hasFwdThenBack]. To
  /// separate int-felter (ikke en liste), så sameConfig/copyWith aldrig kan
  /// snuble i reference-sammenligning.
  final int? seqForward;
  final int? seqBackward;

  /// Multi-brik-træk (25 års "11 ELLER 1×1"): PRÆCIS [multiPieces] forskellige
  /// brikker rykker hver [multiSteps] frem. Begge skal være sat — se
  /// [hasMultiForward].
  final int? multiPieces;
  final int? multiSteps;

  /// Positiv tilstedeværelse (én vagt, brugt af motor, kort-face, admin og
  /// tutorial — så ingen af dem opfinder sin egen halve udgave af tjekket).
  bool get hasFwdThenBack => seqForward != null && seqBackward != null;
  bool get hasMultiForward =>
      multiPieces != null && multiPieces! >= 2 && multiSteps != null &&
      multiSteps! >= 1;

  CardRuleConfig copyWith({
    bool? exitStart,
    List<int>? forwardSteps,
    int? backwardSteps,
    bool clearBackward = false,
    int? splitTotal,
    bool clearSplit = false,
    bool? swap,
    bool? jumpsBlockade,
    int? seqForward,
    int? seqBackward,
    bool clearSeq = false,
    int? multiPieces,
    int? multiSteps,
    bool clearMulti = false,
  }) {
    return CardRuleConfig(
      exitStart: exitStart ?? this.exitStart,
      forwardSteps: forwardSteps ?? this.forwardSteps,
      backwardSteps: clearBackward ? null : (backwardSteps ?? this.backwardSteps),
      splitTotal: clearSplit ? null : (splitTotal ?? this.splitTotal),
      swap: swap ?? this.swap,
      jumpsBlockade: jumpsBlockade ?? this.jumpsBlockade,
      seqForward: clearSeq ? null : (seqForward ?? this.seqForward),
      seqBackward: clearSeq ? null : (seqBackward ?? this.seqBackward),
      multiPieces: clearMulti ? null : (multiPieces ?? this.multiPieces),
      multiSteps: clearMulti ? null : (multiSteps ?? this.multiSteps),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exitStart': exitStart,
        'forwardSteps': forwardSteps,
        if (backwardSteps != null) 'backwardSteps': backwardSteps,
        if (splitTotal != null) 'splitTotal': splitTotal,
        'swap': swap,
        // Nye felter skrives kun når sat, så gamle/klassiske docs forbliver
        // uændrede og et manglende felt læses som fravær (bagud-kompat).
        if (jumpsBlockade) 'jumpsBlockade': jumpsBlockade,
        if (seqForward != null) 'seqForward': seqForward,
        if (seqBackward != null) 'seqBackward': seqBackward,
        if (multiPieces != null) 'multiPieces': multiPieces,
        if (multiSteps != null) 'multiSteps': multiSteps,
      };

  factory CardRuleConfig.fromJson(Map<String, dynamic> json) {
    return CardRuleConfig(
      exitStart: json['exitStart'] as bool? ?? false,
      forwardSteps: (json['forwardSteps'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e as int)
          .toList(),
      backwardSteps: json['backwardSteps'] as int?,
      splitTotal: json['splitTotal'] as int?,
      swap: json['swap'] as bool? ?? false,
      jumpsBlockade: json['jumpsBlockade'] as bool? ?? false,
      seqForward: json['seqForward'] as int?,
      seqBackward: json['seqBackward'] as int?,
      multiPieces: json['multiPieces'] as int?,
      multiSteps: json['multiSteps'] as int?,
    );
  }
}

/// Hele regelsættet: en konfiguration pr. rang.
class CardRules {
  const CardRules(this.byRank);

  final Map<Rank, CardRuleConfig> byRank;

  CardRuleConfig forRank(Rank rank) =>
      byRank[rank] ?? const CardRuleConfig();

  CardRules withRank(Rank rank, CardRuleConfig config) {
    final next = Map<Rank, CardRuleConfig>.from(byRank);
    next[rank] = config;
    return CardRules(next);
  }

  /// Anvend et sæt rang-overrides oven på DISSE regler. Bruges af varianter, der
  /// kun ændrer nogle få kort (fx 25 år: 5-kortet → Hopsakort) og skal arve
  /// resten fra de LIVE/admin-konfigurerede regler frem for at fryse et helt
  /// sæt (så fx admin's byttekort på Knægten bevares i varianten).
  CardRules withOverrides(Map<Rank, CardRuleConfig> overrides) {
    if (overrides.isEmpty) return this;
    final next = Map<Rank, CardRuleConfig>.from(byRank);
    next.addAll(overrides);
    return CardRules(next);
  }

  /// Standard (klassiske) regler — matcher spillets oprindelige opførsel.
  factory CardRules.defaults() {
    return const CardRules(<Rank, CardRuleConfig>{
      Rank.ace: CardRuleConfig(exitStart: true, forwardSteps: <int>[1, 11]),
      Rank.two: CardRuleConfig(forwardSteps: <int>[2]),
      Rank.three: CardRuleConfig(forwardSteps: <int>[3]),
      Rank.four: CardRuleConfig(forwardSteps: <int>[4], backwardSteps: 4),
      Rank.five: CardRuleConfig(forwardSteps: <int>[5]),
      Rank.six: CardRuleConfig(forwardSteps: <int>[6]),
      Rank.seven: CardRuleConfig(splitTotal: 7),
      Rank.eight: CardRuleConfig(forwardSteps: <int>[8]),
      Rank.nine: CardRuleConfig(forwardSteps: <int>[9]),
      Rank.ten: CardRuleConfig(forwardSteps: <int>[10]),
      Rank.jack: CardRuleConfig(forwardSteps: <int>[11]),
      Rank.queen: CardRuleConfig(forwardSteps: <int>[12]),
      Rank.king: CardRuleConfig(exitStart: true, forwardSteps: <int>[13]),
    });
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final entry in byRank.entries)
          entry.key.name: entry.value.toJson(),
      };

  /// True hvis de to regelsæt giver samme config for [rank] (bruges af admin-
  /// UI'et til at vise om en variant-rang afviger fra klassisk).
  static bool sameRank(CardRules a, CardRules b, Rank rank) =>
      sameConfig(a.forRank(rank), b.forRank(rank));

  /// Felt-for-felt-sammenligning af to kort-configs — INKL. jumpsBlockade, så
  /// UI-sync aldrig overser et felt (et load der kun flipper hop skal opdatere
  /// switchen).
  static bool sameConfig(CardRuleConfig a, CardRuleConfig b) {
    if (a.exitStart != b.exitStart) return false;
    if (a.swap != b.swap) return false;
    if (a.jumpsBlockade != b.jumpsBlockade) return false;
    if (a.backwardSteps != b.backwardSteps) return false;
    if (a.splitTotal != b.splitTotal) return false;
    if (a.seqForward != b.seqForward) return false;
    if (a.seqBackward != b.seqBackward) return false;
    if (a.multiPieces != b.multiPieces) return false;
    if (a.multiSteps != b.multiSteps) return false;
    if (a.forwardSteps.length != b.forwardSteps.length) return false;
    for (int i = 0; i < a.forwardSteps.length; i++) {
      if (a.forwardSteps[i] != b.forwardSteps[i]) return false;
    }
    return true;
  }

  factory CardRules.fromJson(Map<String, dynamic> json) {
    final map = <Rank, CardRuleConfig>{};
    for (final entry in json.entries) {
      final rank = Rank.values.where((r) => r.name == entry.key);
      if (rank.isEmpty) continue;
      map[rank.first] =
          CardRuleConfig.fromJson(entry.value as Map<String, dynamic>);
    }
    // Udfyld manglende rangs med default.
    final defaults = CardRules.defaults();
    for (final r in Rank.values) {
      map.putIfAbsent(r, () => defaults.forRank(r));
    }
    return CardRules(map);
  }
}

/// Serialisér et PARTIELT override-map (kun de rangs varianten ændrer) til et
/// Firestore-venligt map — samme pr-rang-format som [CardRules.toJson], men
/// uden at udfylde manglende rangs. Modstykket er [cardRuleOverridesFromJson].
Map<String, dynamic> cardRuleOverridesToJson(
        Map<Rank, CardRuleConfig> overrides) =>
    <String, dynamic>{
      for (final e in overrides.entries) e.key.name: e.value.toJson(),
    };

/// Læs et partielt override-map DEFENSIVT: ukendte rang-navne og ikke-map-
/// værdier springes over (et skævt felt må aldrig vælte indlæsning), og der
/// udfyldes IKKE med defaults — et override-map er netop partielt.
Map<Rank, CardRuleConfig> cardRuleOverridesFromJson(Map<String, dynamic> json) {
  final map = <Rank, CardRuleConfig>{};
  for (final entry in json.entries) {
    if (entry.value is! Map) continue;
    final rank = Rank.values.where((r) => r.name == entry.key);
    if (rank.isEmpty) continue;
    map[rank.first] = CardRuleConfig.fromJson(
        Map<String, dynamic>.from(entry.value as Map));
  }
  return map;
}

/// Ikke-blokerende sanity-advarsler for et regelsæt — vises i admin-UI'et, så
/// et reelt uspilleligt eller ødelagt bord opdages FØR nogen starter et spil.
/// Admin er autoritet: advarsler, aldrig spærringer.
List<String> deckSanityWarnings(CardRules rules) {
  final List<String> warnings = <String>[];
  int hopCount = 0;
  int hopWithoutForward = 0;
  bool anyExit = false;
  bool anyForward = false;
  for (final Rank r in Rank.values) {
    final CardRuleConfig c = rules.forRank(r);
    if (c.jumpsBlockade) {
      hopCount++;
      // Hop gælder kun fremad-skridt i motoren — på et kort uden dem er
      // flaget virkningsløst (og ville lyve på kortet, hvis chippen viste det).
      if (c.forwardSteps.isEmpty) hopWithoutForward++;
    }
    if (c.exitStart) anyExit = true;
    if (c.forwardSteps.isNotEmpty || c.splitTotal != null) anyForward = true;
  }
  if (!anyExit) {
    warnings.add('Ingen kort kan sætte en brik ud — spillet kan ikke komme i '
        'gang.');
  }
  if (!anyForward) {
    warnings.add('Ingen kort kan flytte frem — brikkerne kan aldrig nå i mål.');
  }
  if (hopCount >= 3) {
    warnings.add('$hopCount af ${Rank.values.length} kort kan hoppe over '
        'blokade — blokaden mister sin værdi som forsvar.');
  }
  if (hopWithoutForward > 0) {
    warnings.add('$hopWithoutForward kort har hop slået til uden fremad-skridt '
        '— hop virker kun på fremad-bevægelse og har ingen effekt dér.');
  }
  // Spilfladen vælger flertrins-kort brik-for-brik; et kort med BÅDE
  // split/multi OG frem+tilbage-sekvens kan ikke udtrykke sekvensen dér
  // (samme brik skal vælges to gange). Advar frem for at spærre.
  int seqTrapped = 0;
  for (final Rank r in Rank.values) {
    final CardRuleConfig c = rules.forRank(r);
    if (c.hasFwdThenBack && (c.splitTotal != null || c.hasMultiForward)) {
      seqTrapped++;
    }
  }
  if (seqTrapped > 0) {
    warnings.add('$seqTrapped kort kombinerer frem+tilbage med split/flere '
        'brikker — frem+tilbage kan ikke vælges i spilfladen på sådan et kort.');
  }
  return warnings;
}
