// Badge-/achievement-system (statistik Fase 4).
//
// Hver badge er en REN funktion af et [UserStats]-objekt: ingen sideeffekter,
// ingen Firestore. Det gør dem nemme at teste og at vise både på profilen og
// (top-badges) på site-stats-skærmen.
//
// En badge har et stabilt [id], et [emoji], en dansk [title] + [description],
// en [unlocked]-prædikat og en valgfri [progress] (0..1) der bruges til at vise
// "næsten der" for låste badges.

import 'user_stats.dart';

/// Tematisk gruppering så profilen kan vise badges i pæne sektioner.
enum BadgeCategory {
  resultater,
  stil,
  tempo,
  sjov,
}

extension BadgeCategoryLabel on BadgeCategory {
  String get label {
    switch (this) {
      case BadgeCategory.resultater:
        return 'Resultater';
      case BadgeCategory.stil:
        return 'Stil & strategi';
      case BadgeCategory.tempo:
        return 'Tempo';
      case BadgeCategory.sjov:
        return 'Sjove rekorder';
    }
  }
}

class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.description,
    required this.category,
    required this.unlocked,
    this.progress,
  });

  final String id;
  final String emoji;
  final String title;
  final String description;
  final BadgeCategory category;

  /// Er badgen optjent for de givne stats?
  final bool Function(UserStats) unlocked;

  /// Valgfri fremgang mod at låse badgen op (0..1). Bruges kun til at vise
  /// "næsten der" for endnu-låste badges. Må gerne være null.
  final double Function(UserStats)? progress;

  bool isUnlocked(UserStats s) => unlocked(s);

  /// Fremgang clampet til 0..1. Returnerer 1.0 hvis badgen er optjent.
  double progressFor(UserStats s) {
    if (unlocked(s)) return 1;
    final p = progress?.call(s);
    if (p == null) return 0;
    if (p.isNaN) return 0;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }
}

double _ratio(num value, num target) {
  if (target <= 0) return 0;
  return value / target;
}

/// Alle badges i fast rækkefølge (kategori-sorteret af UI'et).
const List<AchievementBadge> kAllBadges = <AchievementBadge>[
  // ---- Resultater ----
  AchievementBadge(
    id: 'first_win',
    emoji: '🥇',
    title: 'Førstegangs-sejr',
    description: 'Vind dit allerførste spil.',
    category: BadgeCategory.resultater,
    unlocked: _firstWin,
    progress: _firstWinProgress,
  ),
  AchievementBadge(
    id: 'veteran_10',
    emoji: '🎖️',
    title: 'Veteran',
    description: 'Spil 10 spil til ende.',
    category: BadgeCategory.resultater,
    unlocked: _veteran10,
    progress: _veteran10Progress,
  ),
  AchievementBadge(
    id: 'veteran_25',
    emoji: '🏅',
    title: 'Garvet veteran',
    description: 'Spil 25 spil til ende.',
    category: BadgeCategory.resultater,
    unlocked: _veteran25,
    progress: _veteran25Progress,
  ),
  AchievementBadge(
    id: 'veteran_50',
    emoji: '🛡️',
    title: 'Legende',
    description: 'Spil 50 spil til ende.',
    category: BadgeCategory.resultater,
    unlocked: _veteran50,
    progress: _veteran50Progress,
  ),
  AchievementBadge(
    id: 'streak_3',
    emoji: '📈',
    title: 'Sejrsstime',
    description: 'Vind 3 spil i træk.',
    category: BadgeCategory.resultater,
    unlocked: _streak3,
    progress: _streak3Progress,
  ),
  AchievementBadge(
    id: 'streak_5',
    emoji: '🚀',
    title: 'Uovervindelig',
    description: 'Vind 5 spil i træk.',
    category: BadgeCategory.resultater,
    unlocked: _streak5,
    progress: _streak5Progress,
  ),
  AchievementBadge(
    id: 'win_rate_60',
    emoji: '🎯',
    title: 'Skarpskytte',
    description: 'Hold en win-rate på mindst 60% (mindst 10 spil).',
    category: BadgeCategory.resultater,
    unlocked: _winRate60,
    progress: _winRate60Progress,
  ),
  AchievementBadge(
    id: 'host_5',
    emoji: '👑',
    title: 'Vært',
    description: 'Vær vært for 5 spil.',
    category: BadgeCategory.resultater,
    unlocked: _host5,
    progress: _host5Progress,
  ),
  // ---- Stil ----
  AchievementBadge(
    id: 'split_master',
    emoji: '✂️',
    title: 'Split-mester',
    description: 'Del en 7\'er mindst 70% af gangene (mindst 5 syvere).',
    category: BadgeCategory.stil,
    unlocked: _splitMaster,
    progress: _splitMasterProgress,
  ),
  AchievementBadge(
    id: 'swap_junkie',
    emoji: '🔀',
    title: 'Byttejunkie',
    description: 'Lav 10 knægt-byt.',
    category: BadgeCategory.stil,
    unlocked: _swapJunkie,
    progress: _swapJunkieProgress,
  ),
  AchievementBadge(
    id: 'home_master',
    emoji: '🏠',
    title: 'Hjem-mester',
    description: 'Få 8 brikker hele vejen i mål.',
    category: BadgeCategory.stil,
    unlocked: _homeMaster,
    progress: _homeMasterProgress,
  ),
  // ---- Tempo ----
  AchievementBadge(
    id: 'lightning_move',
    emoji: '⚡',
    title: 'Lyn-træk',
    description: 'Lav et træk på under 2 sekunder.',
    category: BadgeCategory.tempo,
    unlocked: _lightningMove,
  ),
  AchievementBadge(
    id: 'quick_win',
    emoji: '🏁',
    title: 'Lynhurtig sejr',
    description: 'Vind et spil på 8 hænder eller færre.',
    category: BadgeCategory.tempo,
    unlocked: _quickWin,
  ),
  // ---- Sjove rekorder ----
  AchievementBadge(
    id: 'table_on_fire',
    emoji: '🔥',
    title: 'Bordet brænder',
    description: 'Slå 5 brikker hjem i ét og samme spil.',
    category: BadgeCategory.sjov,
    unlocked: _tableOnFire,
    progress: _tableOnFireProgress,
  ),
  AchievementBadge(
    id: 'enforcer',
    emoji: '⚔️',
    title: 'Bøddel',
    description: 'Slå 25 modstander-brikker hjem i alt.',
    category: BadgeCategory.sjov,
    unlocked: _enforcer,
    progress: _enforcerProgress,
  ),
  AchievementBadge(
    id: 'sleeper',
    emoji: '😴',
    title: 'Tålmodig',
    description: 'Sid over 20 runder i alt (uden at spille).',
    category: BadgeCategory.sjov,
    unlocked: _sleeper,
    progress: _sleeperProgress,
  ),
];

// Prædikater og progress som top-level funktioner, så listen kan være `const`.

bool _firstWin(UserStats s) => s.gamesWon >= 1;
double _firstWinProgress(UserStats s) => _ratio(s.gamesWon, 1);

bool _veteran10(UserStats s) => s.gamesPlayed >= 10;
double _veteran10Progress(UserStats s) => _ratio(s.gamesPlayed, 10);

bool _veteran25(UserStats s) => s.gamesPlayed >= 25;
double _veteran25Progress(UserStats s) => _ratio(s.gamesPlayed, 25);

bool _veteran50(UserStats s) => s.gamesPlayed >= 50;
double _veteran50Progress(UserStats s) => _ratio(s.gamesPlayed, 50);

bool _streak3(UserStats s) => s.longestWinStreak >= 3;
double _streak3Progress(UserStats s) => _ratio(s.longestWinStreak, 3);

bool _streak5(UserStats s) => s.longestWinStreak >= 5;
double _streak5Progress(UserStats s) => _ratio(s.longestWinStreak, 5);

bool _winRate60(UserStats s) => s.gamesPlayed >= 10 && s.winRate >= 0.6;
double _winRate60Progress(UserStats s) =>
    s.gamesPlayed < 10 ? _ratio(s.gamesPlayed, 10) : _ratio(s.winRate, 0.6);

bool _host5(UserStats s) => s.gamesAsHost >= 5;
double _host5Progress(UserStats s) => _ratio(s.gamesAsHost, 5);

bool _splitMaster(UserStats s) =>
    (s.split7Count + s.solid7Count) >= 5 && s.split7Ratio >= 0.7;
double _splitMasterProgress(UserStats s) {
  final total = s.split7Count + s.solid7Count;
  if (total < 5) return _ratio(total, 5);
  return _ratio(s.split7Ratio, 0.7);
}

bool _swapJunkie(UserStats s) => s.swapCount >= 10;
double _swapJunkieProgress(UserStats s) => _ratio(s.swapCount, 10);

bool _homeMaster(UserStats s) => s.homeStretchEntries >= 8;
double _homeMasterProgress(UserStats s) => _ratio(s.homeStretchEntries, 8);

bool _lightningMove(UserStats s) =>
    s.fastestThinkSeconds != null && s.fastestThinkSeconds! < 2.0;

bool _quickWin(UserStats s) => s.shortestWin != null && s.shortestWin! <= 8;

bool _tableOnFire(UserStats s) => s.maxCapturesInGame >= 5;
double _tableOnFireProgress(UserStats s) => _ratio(s.maxCapturesInGame, 5);

bool _enforcer(UserStats s) => s.totalCaptures >= 25;
double _enforcerProgress(UserStats s) => _ratio(s.totalCaptures, 25);

bool _sleeper(UserStats s) => s.passCount >= 20;
double _sleeperProgress(UserStats s) => _ratio(s.passCount, 20);

/// De badges der er optjent for [s], i kanonisk rækkefølge.
List<AchievementBadge> unlockedBadges(UserStats s) =>
    kAllBadges.where((b) => b.isUnlocked(s)).toList();

/// Antal optjente badges for [s].
int unlockedBadgeCount(UserStats s) =>
    kAllBadges.where((b) => b.isUnlocked(s)).length;

/// Badges grupperet pr. kategori (bevarer rækkefølgen i [kAllBadges]).
Map<BadgeCategory, List<AchievementBadge>> badgesByCategory() {
  final map = <BadgeCategory, List<AchievementBadge>>{};
  for (final b in kAllBadges) {
    map.putIfAbsent(b.category, () => <AchievementBadge>[]).add(b);
  }
  return map;
}
