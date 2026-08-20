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

  CardRuleConfig copyWith({
    bool? exitStart,
    List<int>? forwardSteps,
    int? backwardSteps,
    bool clearBackward = false,
    int? splitTotal,
    bool clearSplit = false,
    bool? swap,
    bool? jumpsBlockade,
  }) {
    return CardRuleConfig(
      exitStart: exitStart ?? this.exitStart,
      forwardSteps: forwardSteps ?? this.forwardSteps,
      backwardSteps: clearBackward ? null : (backwardSteps ?? this.backwardSteps),
      splitTotal: clearSplit ? null : (splitTotal ?? this.splitTotal),
      swap: swap ?? this.swap,
      jumpsBlockade: jumpsBlockade ?? this.jumpsBlockade,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exitStart': exitStart,
        'forwardSteps': forwardSteps,
        if (backwardSteps != null) 'backwardSteps': backwardSteps,
        if (splitTotal != null) 'splitTotal': splitTotal,
        'swap': swap,
        // Kun skrevet når sat, så gamle/klassiske docs forbliver uændrede og
        // et manglende felt læses som false (bagud-kompat).
        if (jumpsBlockade) 'jumpsBlockade': jumpsBlockade,
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
