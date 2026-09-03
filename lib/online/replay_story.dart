// "Mens du var væk" — hvad et logget træk BETØD, sagt i spillernes eget sprog.
//
// BRUGERFUND: replayen skrev "rykkede en brik til felt 23". Det tal står
// ingen steder i spillet: brættet nummererer felterne 1..14 inde i hvert
// kvarter og kalder det første "UD" (board_view.dart). "Felt 23" er et
// udvikler-tal. Og "slog en brik hjem" sagde ikke HVIS brik — heller ikke når
// det var din egen.
//
// Alt herinde er RENT: ind kommer én log-entry plus hvem jeg er, ud kommer
// tekst. Ingen Firebase, ingen widgets, ingen genberegning af partiet — så
// ordvalget kan mutationstestes direkte.

import '../game/progress.dart';
import '../models/board.dart';
import 'serialize.dart';

/// Hvor hårdt skridtet ramte MIG. Tonen bæres visuelt (farve/ikon) — ikke af
/// tillægsord om en navngiven spillers træk.
///
/// Appen må gerne være ked af det PÅ MINE VEGNE. Den må ikke dømme
/// modspillerens træk: byttekortet er ikke et fejltrin, det ER kortet, og i
/// et makkerspil hvor man også må slå sin egen makker hjem, er "frækt!" en
/// dom appen ikke har mandat til (spil-rådgiverens fund).
enum ReplayTone {
  /// Det store flertal. Nogen flyttede en brik.
  neutral,

  /// Det gik ud over mig eller min makker.
  sad,

  /// Det gik vores vej.
  good,
}

/// Én linje i "mens du var væk".
class ReplayStory {
  const ReplayStory({
    required this.actor,
    required this.action,
    this.outcome,
    this.tone = ReplayTone.neutral,
    this.byAi = false,
  });

  /// Hvem gjorde det — navnet, eller "Du".
  final String actor;

  /// Hvad der skete med brikken, i spillernes sprog.
  final String action;

  /// Hvad det betød. null = intet ud over selve flytningen.
  final String? outcome;

  final ReplayTone tone;

  /// Trækket blev lavet af AI'en for en fraværende spiller.
  ///
  /// Uden det ville replayen rose MIG for et træk jeg ikke lavede (jeg var jo
  /// væk), og gøre mig vred på en ven, der sad i toget mens en bot spillede.
  final bool byAi;
}

/// Ejeren ud af et brik-id (`p<ejer>.<nummer>`).
///
/// ÉN vagt: statistikken parsede før den samme streng med
/// `split('.').first.substring(1)`, som KASTER på et id uden 'p'/'.'. Her er
/// den defensiv og returnerer null.
int? ownerOfPieceId(String? id) {
  if (id == null || id.length < 2 || !id.startsWith('p')) return null;
  final int dot = id.indexOf('.');
  return int.tryParse(dot < 0 ? id.substring(1) : id.substring(1, dot));
}

/// Feltets navn, som det står på brættet: "dit felt 8", "Carins UD-felt",
/// "dit hjemstræk".
///
/// Kvarteret kommer fra GEOMETRIEN, ikke fra et hardkodet 15: Partners+ har
/// 6 segmenter à 13 felter, og et fast tal ville navngive hvert eneste felt
/// forkert dén dag varianten kommer.
String fieldName(
  PiecePosition pos, {
  required int mySeat,
  required List<String> names,
  required BoardGeometry geometry,
}) {
  String whose(int owner) {
    if (owner == mySeat) return 'dit';
    if (owner < 0 || owner >= names.length) return 'et';
    return '${names[owner]}s';
  }

  if (pos is StartPosition) {
    return pos.ownerIndex == mySeat
        ? 'din start'
        : '${whose(pos.ownerIndex)} start';
  }
  if (pos is HomeStretchPosition) {
    return '${whose(pos.ownerIndex)} hjemstræk';
  }
  if (pos is TrackPosition) {
    final int quarter = geometry.trackLength ~/ geometry.segments;
    if (quarter <= 0) return 'banen';
    final int owner = pos.index ~/ quarter;
    final int within = pos.index % quarter;
    // Kvarterets første felt ER UD-feltet — brættet skriver "UD" der, ikke et
    // tal, så det må teksten heller ikke.
    if (within == 0) return '${whose(owner)} UD-felt';
    return '${whose(owner)} felt $within';
  }
  return 'banen';
}

/// Afstanden sagt som spillerne siger den — aldrig som forskellen mellem to
/// ringindeks.
///
/// Et indeks-regnestykke bliver FORKERT, fordi fremmede UD-felter ikke tæller
/// med: fra ét kvarters felt 14 til næste kvarters felt 1 er ét tællende felt,
/// men to indeks. [fieldsToFinish] er husets eksisterende mål (bruges i
/// slutrapportens margin) og har skip-reglen indbygget.
///
/// [owner] er BRIKKENS ejer, ikke trækkets spiller — afgørende ved byt, hvor
/// det andet step flytter modstanderens brik.
///
/// null = fra start (der giver et felt-regnestykke ingen mening; teksten
/// hedder "kom ud af start").
int? stepsAdvanced(
  PiecePosition from,
  PiecePosition to, {
  required int owner,
  required BoardGeometry geometry,
}) {
  if (from is StartPosition) return null;
  return fieldsToFinish(geometry, owner, from) -
      fieldsToFinish(geometry, owner, to);
}

/// Fortællingen om ét logget træk, set fra [mySeat].
ReplayStory storyFor(
  Map<String, dynamic> entry, {
  required int mySeat,
  required List<String> names,
  required BoardGeometry geometry,
}) {
  final int seat = (entry['player'] as num?)?.toInt() ?? -1;
  final bool byAi = entry['ai'] == true;
  final bool mine = seat == mySeat;
  final String actor = mine
      ? (byAi ? 'AI\'en (for dig)' : 'Du')
      : (seat >= 0 && seat < names.length ? names[seat] : 'Spiller');

  final String type = entry['type'] as String? ?? 'move';
  if (type == 'pass') {
    final int n = (entry['cardsDiscarded'] as num?)?.toInt() ?? 0;
    return ReplayStory(
      actor: actor,
      action: 'kunne ikke bruge nogen kort og sad over',
      outcome: n > 0 ? 'Smed $n kort' : null,
      byAi: byAi,
    );
  }

  final List<Map<String, dynamic>> steps =
      ((entry['steps'] as List?) ?? const <dynamic>[])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  if (steps.isEmpty) {
    return ReplayStory(actor: actor, action: 'sad over', byAi: byAi);
  }

  PiecePosition posOf(Map<String, dynamic> s, String key) =>
      posFromMap(Map<String, dynamic>.from(s[key] as Map));

  // ---- Byt: begge brikker står i loggen, så det kræver ingen genberegning.
  if (isSwapLogSteps(steps)) {
    // Byttet rammer MIG, hvis en af de to brikker er min.
    final int? o0 = ownerOfPieceId(steps[0]['pieceId'] as String?);
    final int? o1 = ownerOfPieceId(steps[1]['pieceId'] as String?);
    final int? mineIdx = o0 == mySeat ? 0 : (o1 == mySeat ? 1 : null);
    if (mineIdx == null) {
      return ReplayStory(
        actor: actor,
        action: 'byttede to brikker',
        byAi: byAi,
      );
    }
    final Map<String, dynamic> s = steps[mineIdx];
    final PiecePosition was = posOf(s, 'from');
    final String fromName = fieldName(was,
        mySeat: mySeat, names: names, geometry: geometry);
    final int? left = fieldsToFinishOrNull(geometry, mySeat, was);
    return ReplayStory(
      actor: actor,
      action: 'byttede din brik væk fra $fromName',
      outcome: left == null
          ? 'Din brik blev byttet væk'
          : 'Din brik manglede $left felter til mål',
      tone: mine ? ReplayTone.neutral : ReplayTone.sad,
      byAi: byAi,
    );
  }

  // ---- Slag og brand: 'capId' siger HVIS brik det gik ud over.
  final List<int?> hitOwners = <int?>[
    for (final Map<String, dynamic> s in steps)
      if (s['cap'] == true) ownerOfPieceId(s['capId'] as String?),
  ];
  final bool burned = steps.any((Map<String, dynamic> s) => s['burn'] == true);

  // ---- Selve flytningen: første step bærer hovedhandlingen.
  final Map<String, dynamic> first = steps.first;
  final int owner = ownerOfPieceId(first['pieceId'] as String?) ?? seat;
  final PiecePosition from = posOf(first, 'from');
  final PiecePosition to = posOf(steps.length == 1 ? first : steps.last, 'to');
  final String where =
      fieldName(to, mySeat: mySeat, names: names, geometry: geometry);

  String action;
  if (steps.length > 2) {
    action = 'delte kortet over ${steps.length} brikker';
  } else if (steps.length == 2 && steps[0]['pieceId'] != steps[1]['pieceId']) {
    action = 'flyttede to brikker';
  } else if (from is StartPosition) {
    action = 'kom ud af start til $where';
  } else if (to is HomeStretchPosition) {
    action = 'kom ind i $where';
  } else {
    final int? adv =
        stepsAdvanced(from, to, owner: owner, geometry: geometry);
    action = adv == null || adv == 0
        ? 'flyttede en brik til $where'
        : adv > 0
            ? 'rykkede $adv frem til $where'
            : 'rykkede ${-adv} tilbage til $where';
  }

  String? outcome;
  ReplayTone tone = ReplayTone.neutral;
  if (burned) {
    outcome = 'Brændte sin egen brik hjem';
  } else if (hitOwners.isNotEmpty) {
    final bool hitMe = hitOwners.contains(mySeat);
    if (hitMe) {
      outcome = hitOwners.length == 1
          ? 'Slog din brik hjem'
          : 'Slog din brik hjem (${hitOwners.length} i alt)';
      tone = ReplayTone.sad;
    } else {
      final int? victim = hitOwners.first;
      final String who =
          (victim != null && victim >= 0 && victim < names.length)
              ? '${names[victim]}s'
              : 'en';
      outcome = hitOwners.length == 1
          ? 'Slog $who brik hjem'
          : 'Slog ${hitOwners.length} brikker hjem';
      // Kun godt for mig, hvis det var MIT hold der slog — og aldrig som
      // jubel over en navngiven modspiller, kun som en rolig markering.
      if (seat % 2 == mySeat % 2 && mySeat >= 0) tone = ReplayTone.good;
    }
  } else if (to is HomeStretchPosition && owner == mySeat) {
    tone = ReplayTone.good;
  }

  return ReplayStory(
    actor: actor,
    action: action,
    outcome: outcome,
    tone: tone,
    byAi: byAi,
  );
}

/// [fieldsToFinish], men null i stedet for et tal når positionen ikke kan
/// måles (fx en brik i start).
int? fieldsToFinishOrNull(
    BoardGeometry geometry, int owner, PiecePosition pos) {
  if (pos is StartPosition) return null;
  return fieldsToFinish(geometry, owner, pos);
}
