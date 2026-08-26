// Udledningerne bag arkivet: hvem vandt, hvornår sluttede spillet, og har JEG
// set slutningen? De beregnes af gameSummaryFromDoc ud fra RÅ Firestore-felter.
//
// Hvorfor en egen fil: archive_test.dart bygger GameSummary direkte via
// konstruktøren og rammer derfor ALDRIG denne kode. En mutation her — fx
// `unseen: false` — ville være usynlig for hele resten af suiten. Logikken lå
// før på en privat metode i en klasse, der ikke kan konstrueres i et
// testmiljø; den er nu top-level, netop for at kunne bevises (TM-fund).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

Map<String, dynamic> _doc({
  String status = 'over',
  List<dynamic>? uids,
  Map<String, dynamic>? state,
  List<dynamic>? log,
  Map<String, dynamic>? seen,
  int? winningTeamIndexTop,
  int? finishedAtMs,
  int? createdAtMs,
  String? mode,
}) =>
    <String, dynamic>{
      'status': status,
      'hostName': 'vært',
      'names': <String>['A', 'B', 'C', 'D'],
      'uids': uids ?? <dynamic>['me', 'b', 'c', 'd'],
      if (state != null) 'state': state,
      'log': log ?? <dynamic>[],
      if (seen != null) 'seen': seen,
      if (winningTeamIndexTop != null) 'winningTeamIndex': winningTeamIndexTop,
      if (finishedAtMs != null) 'finishedAt': finishedAtMs,
      if (createdAtMs != null) 'createdAt': createdAtMs,
      if (mode != null) 'mode': mode,
    };

void main() {
  group('unseen — "sluttede spillet mens jeg var væk?"', () {
    test('færre sete log-indlæg end der findes → uset', () {
      // MUTATION: `unseen: false` fast → rød. Mærket "Ny slutrapport" ville
      // aldrig vises, og det var netop dét brugeren manglede.
      final g = gameSummaryFromDoc(
          'G1',
          _doc(
            state: <String, dynamic>{'wt': 0},
            log: <dynamic>[1, 2, 3],
            seen: <String, dynamic>{'me': 1},
          ),
          'me');
      expect(g.unseen, isTrue);
    });

    test('set hele loggen → IKKE uset (så udfaldet må vises i listen)', () {
      final g = gameSummaryFromDoc(
          'G2',
          _doc(
            state: <String, dynamic>{'wt': 0},
            log: <dynamic>[1, 2, 3],
            seen: <String, dynamic>{'me': 3},
          ),
          'me');
      expect(g.unseen, isFalse);
    });

    test('et IGANGVÆRENDE spil er aldrig "uset slutrapport"', () {
      final g = gameSummaryFromDoc(
          'G3',
          _doc(
            status: 'playing',
            state: <String, dynamic>{'ph': 'play'},
            log: <dynamic>[1, 2, 3],
            seen: <String, dynamic>{'me': 0},
          ),
          'me');
      expect(g.unseen, isFalse);
    });
  });

  group('vinderen: state er autoritet, topniveau er fallback', () {
    test('state["wt"] vinder over et FORÆLDET topniveau-felt', () {
      // Topniveau-feltet skrives kun ved selve overgangen; state'n er husets
      // autoritet efter start. MUTATION: læs topniveau først → rød.
      final g = gameSummaryFromDoc(
          'G4',
          _doc(
              state: <String, dynamic>{'wt': 1}, winningTeamIndexTop: 0),
          'me');
      expect(g.winningTeamIndex, 1);
      expect(g.mySeat, 0);
      expect(g.iWon, isFalse, reason: 'plads 0 er hold 0, hold 1 vandt');
    });

    test('mangler state["wt"] → topniveau bruges (ældre dokumenter)', () {
      final g = gameSummaryFromDoc(
          'G5', _doc(state: <String, dynamic>{}, winningTeamIndexTop: 0), 'me');
      expect(g.winningTeamIndex, 0);
      expect(g.iWon, isTrue);
    });

    test('ingen af delene → ukendt (ingen påstand om udfaldet)', () {
      final g = gameSummaryFromDoc('G6', _doc(state: <String, dynamic>{}), 'me');
      expect(g.winningTeamIndex, isNull);
      expect(g.iWon, isNull);
    });
  });

  group('tidsstempel og spiltype', () {
    test('finishedAt foretrækkes; createdAt er fallback', () {
      expect(
          gameSummaryFromDoc(
                  'G7', _doc(finishedAtMs: 500, createdAtMs: 100), 'me')
              .finishedAtMs,
          500);
      expect(
          gameSummaryFromDoc('G8', _doc(createdAtMs: 100), 'me').finishedAtMs,
          100,
          reason: 'uden finishedAt sorteres på oprettelsen frem for at falde ud');
    });

    test('mode:"ai" markerer solospil (holdes ude af arkivet)', () {
      expect(gameSummaryFromDoc('G9', _doc(mode: 'ai'), 'me').isAi, isTrue);
      expect(gameSummaryFromDoc('G10', _doc(), 'me').isAi, isFalse);
    });

    test('jeg sad ikke med → mySeat -1 og intet udfald', () {
      final g = gameSummaryFromDoc(
          'G11',
          _doc(uids: <dynamic>['x', 'y', 'z', 'w'],
              state: <String, dynamic>{'wt': 0}),
          'me');
      expect(g.mySeat, -1);
      expect(g.iWon, isNull);
    });
  });
}
