// Stats-compute-modul.
//
// Læser et sæt af færdige `games`-dokumenter og beregner pr. bruger:
//   - Sejre, win-rate, makker-statistik (#1, #2, #3, #4)
//   - Slag (#8, #9, #20)
//   - Stil (#10 split-7, #11 byt, #13 dobbelter, #14 hjem-mester, #15 yndlingsåbner)
//   - Tempo (#22, #23, #24, #25, #26, #27)
//   - Sjove rekorder (#6 kortest sejr, #41 hot streak)
//
// Alle stats er fuldstændigt beregnet fra log + state — ingen
// klient-skrivninger til Firestore (cachen håndteres af stats_repository).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../game/card_rules.dart';
import '../game/progress.dart';
import '../models/playing_card.dart';
import '../online/serialize.dart';
import 'replay_engine.dart';

class UserStats {
  UserStats({
    required this.uid,
    required this.displayName,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.shortestWin,
    this.totalCaptures = 0,
    this.captureGames = 0, // antal spil hvor capture-tal er beregnet
    this.maxCapturesInGame = 0,
    this.timesCaptured = 0,
    this.split7Count = 0,
    this.solid7Count = 0,
    this.swapCount = 0,
    this.protectionCount = 0,
    this.homeStretchEntries = 0,
    Map<String, int>? favoriteStarter,
    this.handsPerWinSum = 0,
    this.gamesAsHost = 0,
    this.gamesOnline = 0,
    this.gamesAiOnly = 0,
    Map<String, PairStats>? partnerStats,
    Map<String, PairStats>? rivalStats,
    this.totalThinkSeconds = 0,
    this.thinkCount = 0,
    this.fastestThinkSeconds,
    this.passCount = 0,
    this.totalCardsDiscarded = 0,
    this.totalMinutesPlayed = 0,
    this.playedGamesWithDuration = 0,
    this.currentWinStreak = 0,
    this.longestWinStreak = 0,
    this.winMarginSum = 0,
    this.winMarginGames = 0,
    this.lossMarginSum = 0,
    this.lossMarginGames = 0,
    this.maxWinMargin,
    this.minWinMargin,
  })  : favoriteStarter = favoriteStarter ?? <String, int>{},
        partnerStats = partnerStats ?? <String, PairStats>{},
        rivalStats = rivalStats ?? <String, PairStats>{};

  final String uid;
  String displayName;

  // Resultater
  int gamesPlayed;
  int gamesWon;
  int? shortestWin; // færreste hænder for at vinde

  // Slag
  int totalCaptures; // slag givet i alt
  int captureGames;
  int maxCapturesInGame;
  int timesCaptured; // slag modtaget i alt

  // Stil
  int split7Count;
  int solid7Count;
  int swapCount;
  int protectionCount;
  int homeStretchEntries;
  Map<String, int> favoriteStarter; // rankLabel → antal

  // Tempo / generelt
  int handsPerWinSum;
  int gamesAsHost;
  int gamesOnline;
  int gamesAiOnly;

  // Makkerskab / rivalitet (key = anden uid)
  Map<String, PairStats> partnerStats;
  Map<String, PairStats> rivalStats;

  // Tænketid
  double totalThinkSeconds;
  int thinkCount;
  double? fastestThinkSeconds;

  // Pass
  int passCount;
  int totalCardsDiscarded;

  // Spilletid
  double totalMinutesPlayed;
  int playedGamesWithDuration;

  // Streak
  int currentWinStreak;
  int longestWinStreak;

  // Margin — hvor mange felter man vinder/taber med (det tabende holds
  // resterende felter til mål ved spil-slut).
  int winMarginSum;
  int winMarginGames;
  int lossMarginSum;
  int lossMarginGames;

  /// Største og mindste sejrsmargin (felter) på tværs af vundne spil.
  int? maxWinMargin;
  int? minWinMargin;

  double? get avgWinMargin =>
      winMarginGames == 0 ? null : winMarginSum / winMarginGames;
  double? get avgLossMargin =>
      lossMarginGames == 0 ? null : lossMarginSum / lossMarginGames;

  // ---- afledte tal til UI ----

  double get winRate => gamesPlayed == 0 ? 0 : gamesWon / gamesPlayed;
  double get avgCapturesPerGame =>
      captureGames == 0 ? 0 : totalCaptures / captureGames;
  double get avgHandsPerWin =>
      gamesWon == 0 ? 0 : handsPerWinSum / gamesWon;
  double get split7Ratio {
    final t = split7Count + solid7Count;
    return t == 0 ? 0 : split7Count / t;
  }

  double? get avgThinkSeconds =>
      thinkCount == 0 ? null : totalThinkSeconds / thinkCount;

  double get avgMinutesPerGame => playedGamesWithDuration == 0
      ? 0
      : totalMinutesPlayed / playedGamesWithDuration;

  String? get favoriteOpener {
    if (favoriteStarter.isEmpty) return null;
    final sorted = favoriteStarter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  MapEntry<String, PairStats>? get bestPartner {
    if (partnerStats.isEmpty) return null;
    final list = partnerStats.entries
        .where((e) => e.value.games >= 2)
        .toList()
      ..sort((a, b) => b.value.winRate.compareTo(a.value.winRate));
    return list.isEmpty ? partnerStats.entries.first : list.first;
  }

  MapEntry<String, PairStats>? get worstRival {
    if (rivalStats.isEmpty) return null;
    final list = rivalStats.entries
        .where((e) => e.value.games >= 2)
        .toList()
      ..sort((a, b) => b.value.lossRate.compareTo(a.value.lossRate));
    return list.isEmpty ? rivalStats.entries.first : list.first;
  }

  // ---- Firestore round-trip ----

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'displayName': displayName,
        'gamesPlayed': gamesPlayed,
        'gamesWon': gamesWon,
        'shortestWin': shortestWin,
        'totalCaptures': totalCaptures,
        'captureGames': captureGames,
        'maxCapturesInGame': maxCapturesInGame,
        'timesCaptured': timesCaptured,
        'split7Count': split7Count,
        'solid7Count': solid7Count,
        'swapCount': swapCount,
        'protectionCount': protectionCount,
        'homeStretchEntries': homeStretchEntries,
        'favoriteStarter': favoriteStarter,
        'handsPerWinSum': handsPerWinSum,
        'gamesAsHost': gamesAsHost,
        'gamesOnline': gamesOnline,
        'gamesAiOnly': gamesAiOnly,
        'partnerStats': partnerStats.map((k, v) => MapEntry(k, v.toJson())),
        'rivalStats': rivalStats.map((k, v) => MapEntry(k, v.toJson())),
        'totalThinkSeconds': totalThinkSeconds,
        'thinkCount': thinkCount,
        'fastestThinkSeconds': fastestThinkSeconds,
        'passCount': passCount,
        'totalCardsDiscarded': totalCardsDiscarded,
        'totalMinutesPlayed': totalMinutesPlayed,
        'playedGamesWithDuration': playedGamesWithDuration,
        'currentWinStreak': currentWinStreak,
        'longestWinStreak': longestWinStreak,
        'winMarginSum': winMarginSum,
        'winMarginGames': winMarginGames,
        'lossMarginSum': lossMarginSum,
        'lossMarginGames': lossMarginGames,
        'maxWinMargin': maxWinMargin,
        'minWinMargin': minWinMargin,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory UserStats.fromJson(Map<String, dynamic> m) {
    return UserStats(
      uid: m['uid'] as String? ?? '',
      displayName: m['displayName'] as String? ?? 'Spiller',
      gamesPlayed: (m['gamesPlayed'] as num?)?.toInt() ?? 0,
      gamesWon: (m['gamesWon'] as num?)?.toInt() ?? 0,
      shortestWin: (m['shortestWin'] as num?)?.toInt(),
      totalCaptures: (m['totalCaptures'] as num?)?.toInt() ?? 0,
      captureGames: (m['captureGames'] as num?)?.toInt() ?? 0,
      maxCapturesInGame: (m['maxCapturesInGame'] as num?)?.toInt() ?? 0,
      timesCaptured: (m['timesCaptured'] as num?)?.toInt() ?? 0,
      split7Count: (m['split7Count'] as num?)?.toInt() ?? 0,
      solid7Count: (m['solid7Count'] as num?)?.toInt() ?? 0,
      swapCount: (m['swapCount'] as num?)?.toInt() ?? 0,
      protectionCount: (m['protectionCount'] as num?)?.toInt() ?? 0,
      homeStretchEntries: (m['homeStretchEntries'] as num?)?.toInt() ?? 0,
      favoriteStarter: (m['favoriteStarter'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toInt())) ??
          <String, int>{},
      handsPerWinSum: (m['handsPerWinSum'] as num?)?.toInt() ?? 0,
      gamesAsHost: (m['gamesAsHost'] as num?)?.toInt() ?? 0,
      gamesOnline: (m['gamesOnline'] as num?)?.toInt() ?? 0,
      gamesAiOnly: (m['gamesAiOnly'] as num?)?.toInt() ?? 0,
      partnerStats: (m['partnerStats'] as Map?)?.map((k, v) =>
              MapEntry(k as String,
                  PairStats.fromJson(Map<String, dynamic>.from(v as Map)))) ??
          <String, PairStats>{},
      rivalStats: (m['rivalStats'] as Map?)?.map((k, v) =>
              MapEntry(k as String,
                  PairStats.fromJson(Map<String, dynamic>.from(v as Map)))) ??
          <String, PairStats>{},
      totalThinkSeconds: (m['totalThinkSeconds'] as num?)?.toDouble() ?? 0,
      thinkCount: (m['thinkCount'] as num?)?.toInt() ?? 0,
      fastestThinkSeconds: (m['fastestThinkSeconds'] as num?)?.toDouble(),
      passCount: (m['passCount'] as num?)?.toInt() ?? 0,
      totalCardsDiscarded: (m['totalCardsDiscarded'] as num?)?.toInt() ?? 0,
      totalMinutesPlayed: (m['totalMinutesPlayed'] as num?)?.toDouble() ?? 0,
      playedGamesWithDuration:
          (m['playedGamesWithDuration'] as num?)?.toInt() ?? 0,
      currentWinStreak: (m['currentWinStreak'] as num?)?.toInt() ?? 0,
      longestWinStreak: (m['longestWinStreak'] as num?)?.toInt() ?? 0,
      winMarginSum: (m['winMarginSum'] as num?)?.toInt() ?? 0,
      winMarginGames: (m['winMarginGames'] as num?)?.toInt() ?? 0,
      lossMarginSum: (m['lossMarginSum'] as num?)?.toInt() ?? 0,
      lossMarginGames: (m['lossMarginGames'] as num?)?.toInt() ?? 0,
      maxWinMargin: (m['maxWinMargin'] as num?)?.toInt(),
      minWinMargin: (m['minWinMargin'] as num?)?.toInt(),
    );
  }
}

class PairStats {
  PairStats({this.displayName = '', this.games = 0, this.wins = 0});
  String displayName;
  int games;
  int wins;
  double get winRate => games == 0 ? 0 : wins / games;
  double get lossRate => games == 0 ? 0 : (games - wins) / games;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'displayName': displayName,
        'games': games,
        'wins': wins,
      };
  factory PairStats.fromJson(Map<String, dynamic> m) => PairStats(
        displayName: m['displayName'] as String? ?? '',
        games: (m['games'] as num?)?.toInt() ?? 0,
        wins: (m['wins'] as num?)?.toInt() ?? 0,
      );
}

/// Saml stats for hver bruger fra et sæt færdige spil.
///
/// [games] er en liste af rå Firestore-dokumenter — én pr. spil. Spil der ikke
/// er afsluttet (`status != 'over'`) springes over. Sorteres kronologisk efter
/// `finishedAt` (eller `createdAt`) for korrekt streak-beregning.
Map<String, UserStats> computeAllStats(
    List<Map<String, dynamic>> games) {
  final result = <String, UserStats>{};

  // Sortér kronologisk så win-streaks beregnes i rigtig rækkefølge.
  final ordered = List<Map<String, dynamic>>.from(games);
  ordered.sort((a, b) {
    final ta = _timestampMs(a['finishedAt']) ?? _timestampMs(a['createdAt']) ?? 0;
    final tb = _timestampMs(b['finishedAt']) ?? _timestampMs(b['createdAt']) ?? 0;
    return ta.compareTo(tb);
  });

  for (final game in ordered) {
    if (game['status'] != 'over') continue;
    _accumulateGame(game, result);
  }

  return result;
}

int? _timestampMs(dynamic v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  return null;
}

void _accumulateGame(
    Map<String, dynamic> game, Map<String, UserStats> bucket) {
  final uids = (game['uids'] as List?)?.cast<dynamic>() ?? const <dynamic>[];
  final names = (game['names'] as List?)?.cast<dynamic>() ?? const <dynamic>[];
  final winningTeam = (game['winningTeamIndex'] as num?)?.toInt();
  final handNumber = ((game['state'] as Map?)?['hn'] as num?)?.toInt() ?? 0;

  // Margin: hvor mange felter det tabende hold manglede ved spil-slut.
  int? marginFields;
  final stateMap = game['state'];
  if (winningTeam != null && stateMap is Map) {
    try {
      final finalState =
          gameStateFromMap(Map<String, dynamic>.from(stateMap));
      marginFields = winMarginFields(finalState);
    } catch (_) {
      marginFields = null;
    }
  }
  final hostUid = game['hostUid'] as String?;
  final log = ((game['log'] as List?) ?? const <dynamic>[])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  // Replay skal køre med de OPLØSTE regler spillet faktisk blev spillet med —
  // dvs. state'ns 'cr' (som bærer variantens kort, fx Hopsakortet), IKKE
  // doc'ets rå 'cardRules' (det uopløste klassiske snapshot). Ellers replayes
  // et 25 år-spil med klassiske kort. Fallback: doc'ets cardRules → defaults.
  Map? cardRulesMap;
  final dynamic stateRaw = game['state'];
  if (stateRaw is Map && stateRaw['cr'] is Map) {
    cardRulesMap = stateRaw['cr'] as Map;
  }
  cardRulesMap ??= game['cardRules'] as Map?;
  final cardRules = cardRulesMap == null
      ? CardRules.defaults()
      : CardRules.fromJson(Map<String, dynamic>.from(cardRulesMap));

  // Online vs AI: alle 4 uids udfyldt = online; ellers AI-blandet.
  final isFullyOnline = uids.length == 4 && uids.every((u) => u != null);

  // Spil-varighed.
  final created = _timestampMs(game['createdAt']);
  final finished = _timestampMs(game['finishedAt']);
  double? minutes;
  if (created != null && finished != null && finished > created) {
    minutes = (finished - created) / 60000.0;
  }

  // Pr-træk tænketid: diff'es chronologically.
  int? lastT;
  final thinkSecondsBySeat = <int, List<double>>{};
  for (final entry in log) {
    final t = _timestampMs(entry['t']);
    if (t != null && lastT != null) {
      final secs = (t - lastT) / 1000.0;
      if (secs >= 0 && secs <= 3600) {
        final seat = (entry['player'] as num).toInt();
        thinkSecondsBySeat.putIfAbsent(seat, () => <double>[]).add(secs);
      }
    }
    if (t != null) lastT = t;
  }

  // Replay loggen for slag/dobbelter/hjemstræk.
  final captureGivenBySeat = <int, int>{};
  final captureReceivedBySeat = <int, int>{};
  final homeStretchEntriesBySeat = <int, int>{};
  ReplayResult? replay;
  try {
    replay = replayGame(
      playerNames: names.map((e) => e as String).toList(),
      isHuman: List<bool>.filled(4, true),
      playerColors: List<int>.filled(4, 0xFF000000),
      cardRules: cardRules,
      log: log,
    );
    for (final ev in replay.events) {
      captureGivenBySeat[ev.player] =
          (captureGivenBySeat[ev.player] ?? 0) + ev.captured.length;
      homeStretchEntriesBySeat[ev.player] =
          (homeStretchEntriesBySeat[ev.player] ?? 0) + ev.movedToHomeStretch;
      for (final captured in ev.captured) {
        // capturedPieceId formateres som p<owner>.<slot>
        final owner = int.tryParse(captured.split('.').first.substring(1));
        if (owner != null) {
          captureReceivedBySeat[owner] =
              (captureReceivedBySeat[owner] ?? 0) + 1;
        }
      }
    }
  } catch (_) {
    // Hvis replay fejler (defekt log) — fortsætter med 0-stats.
  }

  // Pr. spiller-tæller for log-baserede stats.
  final split7Count = <int, int>{};
  final solid7Count = <int, int>{};
  final swapCount = <int, int>{};
  final openerCount = <int, Map<String, int>>{};
  final passBySeat = <int, int>{};
  final cardsDiscardedBySeat = <int, int>{};
  final protectionBySeat = <int, int>{};

  for (final entry in log) {
    final seat = (entry['player'] as num).toInt();
    final type = entry['type'] as String? ?? 'move';
    if (type == 'pass') {
      passBySeat[seat] = (passBySeat[seat] ?? 0) + 1;
      cardsDiscardedBySeat[seat] = (cardsDiscardedBySeat[seat] ?? 0) +
          ((entry['cardsDiscarded'] as num?)?.toInt() ?? 0);
      continue;
    }
    if (type != 'move') continue;

    final cardMap = Map<String, dynamic>.from(entry['card'] as Map);
    final card = cardFromMap(cardMap);
    final steps = (entry['steps'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!card.isExit && card.rank == Rank.seven) {
      if (steps.length > 1) {
        split7Count[seat] = (split7Count[seat] ?? 0) + 1;
      } else {
        solid7Count[seat] = (solid7Count[seat] ?? 0) + 1;
      }
    }
    if (!card.isExit && card.rank == Rank.jack && steps.length == 2) {
      swapCount[seat] = (swapCount[seat] ?? 0) + 1;
    }
    // Yndlingsåbner: kort spillet til at gå ud af start.
    final firstStep = steps.isNotEmpty
        ? Map<String, dynamic>.from(steps.first)
        : null;
    if (firstStep != null) {
      final fromMap = Map<String, dynamic>.from(firstStep['from'] as Map);
      if (fromMap['t'] == 'start') {
        final label = card.isExit ? 'UD' : card.rankLabel;
        openerCount.putIfAbsent(seat, () => <String, int>{});
        openerCount[seat]![label] = (openerCount[seat]![label] ?? 0) + 1;
      }
    }
  }

  // Per-spiller "var jeg en beskyttet dobbelt" — tæller events fra replay
  // hvor min brik ender på et felt med 2+ egne brikker.
  if (replay != null) {
    for (final ev in replay.events) {
      if (ev.kind != ReplayKind.move) continue;
      // (Forsimplet) — tæl events hvor møver flytter en brik som ender på
      // samme felt som en anden af spillerens brikker. Vi godkender et
      // approksimerings-tal her; eksakt skal bruges via replay.finalState
      // pr. step. For nu: spring helt over og acceptér 0 = "ikke beregnet".
      // Sat eksplicit til 0 for at undgå misvisende tal.
      protectionBySeat[ev.player] = 0;
    }
  }

  // Update bucket pr. spiller.
  for (int seat = 0; seat < uids.length; seat++) {
    final uid = uids[seat] as String?;
    if (uid == null) continue;
    final name = seat < names.length ? names[seat] as String : 'Spiller';

    final s = bucket.putIfAbsent(
        uid, () => UserStats(uid: uid, displayName: name));
    s.displayName = name;
    s.gamesPlayed += 1;
    if (hostUid == uid) s.gamesAsHost += 1;
    if (isFullyOnline) {
      s.gamesOnline += 1;
    } else {
      s.gamesAiOnly += 1;
    }
    if (minutes != null) {
      s.totalMinutesPlayed += minutes;
      s.playedGamesWithDuration += 1;
    }

    // Sejre / streaks.
    final isOnTeam0 = seat % 2 == 0;
    final won = winningTeam != null &&
        ((winningTeam == 0 && isOnTeam0) ||
            (winningTeam == 1 && !isOnTeam0));
    if (won) {
      s.gamesWon += 1;
      s.handsPerWinSum += handNumber;
      if (s.shortestWin == null || handNumber < s.shortestWin!) {
        s.shortestWin = handNumber;
      }
      s.currentWinStreak += 1;
      if (s.currentWinStreak > s.longestWinStreak) {
        s.longestWinStreak = s.currentWinStreak;
      }
      if (marginFields != null) {
        s.winMarginSum += marginFields;
        s.winMarginGames += 1;
        if (s.maxWinMargin == null || marginFields > s.maxWinMargin!) {
          s.maxWinMargin = marginFields;
        }
        if (s.minWinMargin == null || marginFields < s.minWinMargin!) {
          s.minWinMargin = marginFields;
        }
      }
    } else {
      s.currentWinStreak = 0;
      if (winningTeam != null && marginFields != null) {
        s.lossMarginSum += marginFields;
        s.lossMarginGames += 1;
      }
    }

    // Slag.
    final caps = captureGivenBySeat[seat] ?? 0;
    s.totalCaptures += caps;
    s.captureGames += 1;
    if (caps > s.maxCapturesInGame) s.maxCapturesInGame = caps;
    s.timesCaptured += captureReceivedBySeat[seat] ?? 0;
    s.homeStretchEntries += homeStretchEntriesBySeat[seat] ?? 0;

    // Stil.
    s.split7Count += split7Count[seat] ?? 0;
    s.solid7Count += solid7Count[seat] ?? 0;
    s.swapCount += swapCount[seat] ?? 0;
    s.protectionCount += protectionBySeat[seat] ?? 0;
    final opener = openerCount[seat];
    if (opener != null) {
      for (final e in opener.entries) {
        s.favoriteStarter[e.key] = (s.favoriteStarter[e.key] ?? 0) + e.value;
      }
    }

    // Pass.
    s.passCount += passBySeat[seat] ?? 0;
    s.totalCardsDiscarded += cardsDiscardedBySeat[seat] ?? 0;

    // Tænketid.
    final times = thinkSecondsBySeat[seat] ?? const <double>[];
    if (times.isNotEmpty) {
      s.totalThinkSeconds += times.reduce((a, b) => a + b);
      s.thinkCount += times.length;
      final fast = times.reduce((a, b) => a < b ? a : b);
      if (s.fastestThinkSeconds == null || fast < s.fastestThinkSeconds!) {
        s.fastestThinkSeconds = fast;
      }
    }

    // Makker (overfor) og rivaler (sidemand).
    if (isFullyOnline) {
      final partnerSeat = (seat + 2) % 4;
      final partnerUid = uids[partnerSeat] as String?;
      if (partnerUid != null) {
        final ps = s.partnerStats.putIfAbsent(
            partnerUid, () => PairStats());
        ps.displayName = (partnerSeat < names.length
            ? names[partnerSeat] as String
            : ps.displayName);
        ps.games += 1;
        if (won) ps.wins += 1;
      }
      for (final rivalSeat in <int>[(seat + 1) % 4, (seat + 3) % 4]) {
        final rivalUid = uids[rivalSeat] as String?;
        if (rivalUid != null) {
          final rs = s.rivalStats.putIfAbsent(
              rivalUid, () => PairStats());
          rs.displayName = rivalSeat < names.length
              ? names[rivalSeat] as String
              : rs.displayName;
          rs.games += 1;
          if (!won) rs.wins += 1; // wins = mig tabte = de vandt
        }
      }
    }
  }
}
