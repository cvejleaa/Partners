// Online-loggen må kun få det træk, motoren faktisk UDFØRTE — aldrig et
// afvist træk, og aldrig klientens version med forældede slag-oplysninger.
// Før skrev mutate klientens indsendte træk uanset motorens dom; loggen og
// stillingen kom ud af trit, og "Mens du var væk"-brættet forsvandt
// (ejer-fund, klassisk). playMoveForLog/passHandForLog er den ENE vej (brugt
// af OnlineService.mutateLogged og AI-trækket).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/online_service.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

List<PiecePosition> start(int seat) =>
    <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(seat, s)];

void main() {
  const PlayingCard five = PlayingCard(Rank.five, Suit.spades);

  GameState board({int current = 0}) => makeState(
        currentPlayerIndex: current,
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(9),
            const StartPosition(0, 1),
            const StartPosition(0, 2),
            const StartPosition(0, 3),
          ],
          <PiecePosition>[
            const TrackPosition(14),
            const StartPosition(1, 1),
            const StartPosition(1, 2),
            const StartPosition(1, 3),
          ],
          start(2),
          start(3),
        ],
        hands: <List<PlayingCard>>[
          <PlayingCard>[five],
          <PlayingCard>[const PlayingCard(Rank.two, Suit.hearts)],
          <PlayingCard>[],
          <PlayingCard>[],
        ],
      );

  // Klientens version: 9 → 14 UDEN slag-oplysning (fx et forældet snapshot,
  // hvor feltet var tomt).
  const Move submitted = Move(card: five, steps: <MoveStep>[
    MoveStep(pieceId: 'p0.0', from: TrackPosition(9), to: TrackPosition(14)),
  ]);

  test('et accepteret træk logges i MOTORENS version (med slaget)', () {
    final GameState s = board();
    final Map<String, dynamic>? e =
        playMoveForLog(GameEngine(state: s), 0, submitted);
    expect(e, isNotNull);
    final Map<String, dynamic> step =
        Map<String, dynamic>.from((e!['steps'] as List).single as Map);
    expect(step['capId'], 'p1.0',
        reason: 'motoren slog p1.0 hjem — loggen skal sige det');
    expect(s.pieceById('p1.0').position, isA<StartPosition>());
    expect(s.pieceById('p0.0').position, const TrackPosition(14));
  });

  test('et afvist træk (ikke spillerens tur) giver INTET logindlæg', () {
    final GameState s = board(current: 1);
    expect(playMoveForLog(GameEngine(state: s), 0, submitted), isNull);
    // … og stillingen er urørt.
    expect(s.pieceById('p0.0').position, const TrackPosition(9));
    expect(s.pieceById('p1.0').position, const TrackPosition(14));
  });

  test('et ulovligt træk (forkert til-felt) giver INTET logindlæg', () {
    const Move wrong = Move(card: five, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.0', from: TrackPosition(9), to: TrackPosition(15)),
    ]);
    expect(playMoveForLog(GameEngine(state: board()), 0, wrong), isNull);
  });

  test('pas: kun når spilleren IKKE kan spille', () {
    // Plads 0 kan spille femmeren → pas afvises.
    expect(passHandForLog(GameEngine(state: board()), 0), isNull);
    // Alle brikker i start og kun en femmer (kan ikke gå ud i klassisk) →
    // pas er lovligt. Plads 1 har et kort, så hånden fortsætter efter passet.
    final GameState s = makeState(
      currentPlayerIndex: 0,
      piecePositions: <List<PiecePosition>>[start(0), start(1), start(2), start(3)],
      hands: <List<PlayingCard>>[
        <PlayingCard>[five],
        <PlayingCard>[const PlayingCard(Rank.two, Suit.hearts)],
        <PlayingCard>[], <PlayingCard>[],
      ],
    );
    final Map<String, dynamic>? e = passHandForLog(GameEngine(state: s), 0);
    expect(e, isNotNull);
    expect(e!['type'], 'pass');
    expect(e['cardsDiscarded'], 1);
  });

  test('pas er kun en dublet i SAMME hånd — ét i hver hånd er to ægte pas', () {
    // Det gamle skrive-værn så to pas fra samme spiller (intet kort, ingen
    // steps) som "samme træk" og smed det andet væk — også i en ny hånd.
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
      passLogEntry(2, 4, hn: 3),
    ];
    expect(isRecentDuplicateMove(log, passLogEntry(2, 4, hn: 4)), isFalse);
    expect(isRecentDuplicateMove(log, passLogEntry(2, 4, hn: 3)), isTrue);
  });

  // ---- hn læses FØR trækket (TM-hul: push_log_hn_test låser kontrakten på
  // motoren, men ikke at playMoveForLog/passHandForLog faktisk LÆSER før).
  // Et træk, der tømmer sidste hånd, tæller handNumber op synkront; læst
  // bagefter ville logindlægget bære den NÆSTE hånds nummer (2 i stedet for 1).

  test('et håndafsluttende TRÆK logges med hånden det hørte til (hn læst FØR)',
      () {
    final GameState s = makeState(
      currentPlayerIndex: 0,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(9),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        start(1), start(2), start(3),
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[five], <PlayingCard>[], <PlayingCard>[], <PlayingCard>[],
      ],
    );
    final int before = s.handNumber;
    final Map<String, dynamic>? e = playMoveForLog(
        GameEngine(state: s, rng: Random(1)), 0, submitted);
    expect(e, isNotNull);
    expect(s.handNumber, before + 1,
        reason: 'forudsætning: trækket tømte sidste hånd og startede en ny — '
            'ellers beviser testen intet om læse-rækkefølgen');
    expect(e!['hn'], before,
        reason: 'hn = hånden trækket hørte til ($before), ikke den nye '
            '(${s.handNumber})');
  });

  test('et håndafsluttende PAS logges med hånden det hørte til (hn læst FØR)',
      () {
    final GameState s = makeState(
      currentPlayerIndex: 0,
      hands: <List<PlayingCard>>[
        <PlayingCard>[five], <PlayingCard>[], <PlayingCard>[], <PlayingCard>[],
      ],
    );
    final GameEngine engine = GameEngine(state: s, rng: Random(1));
    expect(engine.canPlay(0), isFalse, reason: 'forudsætning: pas er lovligt');
    final int before = s.handNumber;
    final Map<String, dynamic>? e = passHandForLog(engine, 0);
    expect(e, isNotNull);
    expect(s.handNumber, before + 1, reason: 'forudsætning: hånden skiftede');
    expect(e!['hn'], before);
    expect(e['cardsDiscarded'], 1,
        reason: 'antallet læses FØR hånden tømmes (efter ville det være 0)');
  });
}
