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

  CardRuleConfig copyWith({
    bool? exitStart,
    List<int>? forwardSteps,
    int? backwardSteps,
    bool clearBackward = false,
    int? splitTotal,
    bool clearSplit = false,
    bool? swap,
  }) {
    return CardRuleConfig(
      exitStart: exitStart ?? this.exitStart,
      forwardSteps: forwardSteps ?? this.forwardSteps,
      backwardSteps: clearBackward ? null : (backwardSteps ?? this.backwardSteps),
      splitTotal: clearSplit ? null : (splitTotal ?? this.splitTotal),
      swap: swap ?? this.swap,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exitStart': exitStart,
        'forwardSteps': forwardSteps,
        if (backwardSteps != null) 'backwardSteps': backwardSteps,
        if (splitTotal != null) 'splitTotal': splitTotal,
        'swap': swap,
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
    return CardRules(<Rank, CardRuleConfig>{
      Rank.ace: const CardRuleConfig(exitStart: true, forwardSteps: <int>[1, 11]),
      Rank.two: const CardRuleConfig(forwardSteps: <int>[2]),
      Rank.three: const CardRuleConfig(forwardSteps: <int>[3]),
      Rank.four: const CardRuleConfig(forwardSteps: <int>[4], backwardSteps: 4),
      Rank.five: const CardRuleConfig(forwardSteps: <int>[5]),
      Rank.six: const CardRuleConfig(forwardSteps: <int>[6]),
      Rank.seven: const CardRuleConfig(splitTotal: 7),
      Rank.eight: const CardRuleConfig(forwardSteps: <int>[8]),
      Rank.nine: const CardRuleConfig(forwardSteps: <int>[9]),
      Rank.ten: const CardRuleConfig(forwardSteps: <int>[10]),
      Rank.jack: const CardRuleConfig(forwardSteps: <int>[11]),
      Rank.queen: const CardRuleConfig(forwardSteps: <int>[12]),
      Rank.king: const CardRuleConfig(exitStart: true, forwardSteps: <int>[13]),
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
