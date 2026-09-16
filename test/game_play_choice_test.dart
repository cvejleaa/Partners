// Rutningen af et brik-tryk, når kortet kan to ting.
//
// BRUGERFUND, ordret: "når et kort har flere muligheder skal dialogen om
// hvilken man vælger være mere tydelig. I dag kommer den i bunden af skærmen,
// men hvis man ikke vælger en af mulighederne men starter med at klikke på en
// brik, bliver brikken flyttet direkte, selv om man måske ønskede at f.eks.
// bytte 2 brikker".
//
// HVORFOR DENNE FIL FINDES: der fandtes INGEN test, der rørte GamePlayView.
// Klassifikationen kan testes rent (move_options_test.dart), men den beviser
// ikke dét, brugeren klagede over — at et tryk ikke må flytte noget. Uden
// dette stillads ville mutationen "lad uafgjort falde tilbage til flyt" stå
// GRØN, og rettelsen ville være en påstand.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/state/display_config.dart';
import 'package:partners/ui/widgets/board_view.dart';
import 'package:partners/ui/widgets/card_view.dart';
import 'package:partners/ui/widgets/game_play_view.dart';

import 'test_helpers.dart';

/// 25 års nier: "Byt ELLER 9" — et helt almindeligt kort, 4 i bunken.
const PlayingCard nine = PlayingCard(Rank.nine, Suit.spades);

/// Klassisk firer: 4 frem ELLER 4 tilbage — samme brik, to udfald.
const PlayingCard four = PlayingCard(Rank.four, Suit.hearts);

/// Klassisk konge: ud af start ELLER 13 frem — men ALDRIG for samme brik.
const PlayingCard king = PlayingCard(Rank.king, Suit.clubs);

/// Klassisk es: ud af start ELLER 1 frem ELLER 11 frem.
const PlayingCard ace = PlayingCard(Rank.ace, Suit.diamonds);

/// 25 års knægt: 11 frem ELLER 1×1 — to FORSKELLIGE evner på samme kort.
const PlayingCard jack = PlayingCard(Rank.jack, Suit.hearts);

/// Klassisk syver: splitTotal alene — 7 på én brik ELLER delt over flere.
/// IKKE to separate evner (se _hasSeparateMultiAbility): split-flowet
/// spørger allerede brik for brik.
const PlayingCard seven = PlayingCard(Rank.seven, Suit.spades);
final CardRules p25 = effectiveCardRules(partners25, CardRules.defaults());
final CardRules classic = CardRules.defaults();

/// Admin-hybrid (findes ikke i nogen skibet variant): "1 ELLER 9 frem ELLER
/// 1×1" — enkelt-brik-evnen har SELV to afstande, så et tryk i enkelt-tilstand
/// er tvetydigt for netop den brik. Bruges KUN til at bevise, at rutningen i
/// _handlePieceTap rent faktisk styrer noget: uden "&& _multiPieceMode !=
/// false" ville et sådant tryk falde i splitflowets EGEN afstands-dialog
/// ("Hvor mange felter?") i stedet for de inline "1 frem"/"9 frem"-knapper —
/// præcis det forklædte spørgsmål, denne commit fjernede for knægten.
const PlayingCard hybridTen = PlayingCard(Rank.ten, Suit.spades);
final CardRules hybridRules = CardRules.defaults().withRank(
  Rank.ten,
  const CardRuleConfig(
      forwardSteps: <int>[1, 9], multiPieces: 2, multiSteps: 1),
);

/// Kun ÉN brik på banen, langt fra både start og hjemstræk, så både 4 frem
/// (→ felt 24) og 4 tilbage (→ felt 16) er lovlige for netop den brik.
/// Resten står i start og kan intet med en firer — så de to eneste lovlige
/// træk i stillingen hører til p0.0.
GameState fourState() => makeState(
      cardRules: classic,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[four],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// Esset, hvor BEGGE slags valg findes samtidig:
/// p0.0 står på banen og kan både 1 frem (→ 21) og 11 frem (→ 32, felt 30 er
/// et fremmed UD-felt og tæller ikke). p0.1 står i start og har præcis ÉT
/// lovligt træk — ud af start. Netop den kombination udløste QC-fundet.
GameState aceState() => makeState(
      cardRules: classic,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[ace],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// BRUGERENS EGEN OPSÆTNING: en firer, der KUN kan baglæns.
///
/// Sat som admin ville sætte den — via `withRank`, samme vej som gemte
/// overrides går gennem `effectiveCardRules` og videre i spillets `state.cr`.
/// Testen nedenfor er der, fordi resten af firer-testene kører på de
/// KLASSISKE standardregler (frem ELLER tilbage), og de siger derfor intet
/// om det spil, der faktisk spilles. Uden denne test hvilede påstanden
/// "ændringen følger din opsætning" kun på kode-læsning.
final CardRules backwardOnlyFour = CardRules.defaults().withRank(
  Rank.four,
  const CardRuleConfig(backwardSteps: 4),
);

GameState backwardFourState() => makeState(
      cardRules: backwardOnlyFour,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[four],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// Alle egne brikker i start: kongens eneste lovlige træk er "ud af start".
GameState kingState() => makeState(
      cardRules: classic,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        for (int i = 0; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[king],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// En stilling hvor nieren KAN begge dele: min brik kan rykke 9 frem, og der
/// står en modstanderbrik at bytte med.
GameState choiceState() => makeState(
      cardRules: p25,
      variant: partners25,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(5),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        <PiecePosition>[
          const StartPosition(2, 0),
          const StartPosition(2, 1),
          const StartPosition(2, 2),
          const StartPosition(2, 3),
        ],
        <PiecePosition>[
          const StartPosition(3, 0),
          const StartPosition(3, 1),
          const StartPosition(3, 2),
          const StartPosition(3, 3),
        ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[nine],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// Knægten, hvor BEGGE evner er lovlige samtidig: to egne brikker på banen,
/// langt fra hinanden. Hver kan rykke 11 frem alene (p0.0: 5 → 17, idet felt
/// 15 er et fremmed UD-felt og ikke tæller), og de kan tilsammen rykke 1 frem
/// hver. Uden BEGGE dele ville der ikke være noget at vælge imellem — og så
/// målte testen ingenting.
GameState jackState() => makeState(
      cardRules: p25,
      variant: partners25,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(5),
          const TrackPosition(40),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[jack],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// REGRESSIONS-fixture for _hasSeparateMultiAbility: klassisk syver, to egne
/// brikker langt fra hinanden (3 og 20), så BÅDE "7 på én brik" og en rigtig
/// split (fx 3+4 på to brikker) er lovlige samtidig. Uden begge dele målte
/// testen ingenting (MoveOptions.hasBothPieceCounts ville stå falsk uanset).
GameState sevenState() => makeState(
      cardRules: classic,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(3),
          const TrackPosition(20),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[seven],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

/// Til [hybridTen]: p0.0 på felt 3 kan BÅDE 1 frem (→4) og 9 frem (→12) —
/// tvetydigt i enkelt-tilstand. p0.1 på felt 40 gør 1×1 lovligt sammen med
/// p0.0 (begge +1), så der reelt ER et evne-valg at træffe først.
GameState hybridTenState() => makeState(
      cardRules: hybridRules,
      variant: classicVariant,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(3),
          const TrackPosition(40),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        for (int i = 1; i < 4; i++)
          <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[hybridTen],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

Future<List<Move>> pumpAndPlay(
  WidgetTester tester,
  GameState state, {
  required Future<void> Function(WidgetTester t) act,
}) async {
  final List<Move> applied = <Move>[];
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      // Rammer Firestore i produktion; fast værdi her, så testen ikke
      // afhænger af netværk eller af en fallback-timing.
      boardMinPxProvider.overrideWith((ref) => Stream<double>.value(240)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: GamePlayView(
          state: state,
          mySeat: 0,
          onApplyMove: (int seat, Move m) => applied.add(m),
          onPass: (int seat) {},
          onSubmitExchange: (int seat, PlayingCard c) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await act(tester);
  await tester.pumpAndSettle();
  return applied;
}

/// Skærm-punktet hvor brættet FAKTISK tegner [pieceId].
///
/// HVORFOR IKKE BARE brættets midte: det var den første udgave af denne fil,
/// og den beviste ingenting. Midten er et tomt felt — der er ingen brik at
/// ramme, så `applied` stod tom, uanset om koden flyttede eller ej. Testen var
/// grøn med fejlen genindsat. Punktet hentes derfor fra brættets EGEN
/// geometri (samme kilde som tap-detektionen), og testen "flyt-valget flytter
/// rent faktisk brikken" nedenfor er den positive kontrol: rammer dette punkt
/// en dag ved siden af, bliver DEN rød, og så ved vi det.
Offset pieceSpot(WidgetTester t, GameState state, String pieceId) {
  final Finder board = find.byType(BoardView);
  final BoardView view = t.widget<BoardView>(board);
  final Rect r = t.getRect(board);
  final Map<String, Offset> centers = BoardView.debugPieceCenters(
      state, r.shortestSide, view.debugRotation,
      scale: view.debugScale);
  final Offset? c = centers[pieceId];
  expect(c, isNotNull, reason: 'brættet tegner ingen brik ved id $pieceId');
  return r.topLeft + c!;
}

void main() {
  testWidgets('kortet tilbyder BEGGE muligheder som knapper', (t) async {
    await pumpAndPlay(t, choiceState(), act: (t) async {
      await t.tap(find.byType(CardView).first);
    });
    expect(find.text('Kortet kan to ting — vælg én:'), findsOneWidget);
    expect(find.text('Byt plads på to brikker'), findsOneWidget);
  });

  testWidgets('FUNDET: et brik-tryk flytter IKKE, mens valget er uafgjort',
      (t) async {
    // Kernen i rapporten. Før stod tilstanden lydløst på "flyt", og dette
    // tryk flyttede brikken uigenkaldeligt. Trykket rammer p0.0 — den brik
    // der KAN rykke 9 frem — så et "ingenting skete" her er et valg, ikke et
    // forbier.
    final GameState state = choiceState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, isEmpty,
        reason: 'ingen brik må flyttes, før spilleren har valgt');
  });

  testWidgets('POSITIV KONTROL: vælger man FLYT, flytter det SAMME tryk brikken',
      (t) async {
    // Denne test findes for at holde den forrige ærlig. Samme kort, samme
    // punkt på brættet — eneste forskel er, at valget er truffet. Bliver
    // denne rød (fx fordi geometrien er flyttet sig, og punktet rammer tomt),
    // er den forrige tests "ingen træk" heller ikke længere et bevis.
    final GameState state = choiceState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      // Ikke på tekst: flyt-knappens tekst er den konkrete beskrivelse af
      // trækket, når der kun er ét (fx "Ryk 9 frem"). Ikonet er knappens
      // stabile identitet.
      await t.tap(find.byIcon(Icons.arrow_forward));
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, hasLength(1),
        reason: 'efter valget skal netop dette tryk flytte p0.0');
    expect(applied.single.steps.first.pieceId, 'p0.0');
  });

  // -------------------------------------------------------------------------
  // Brikkens eget valg: det hvide "Vælg træk"-ark er erstattet af de SAMME
  // inline-knapper. Kortet her er en klassisk firer, hvor én brik kan begge
  // retninger.
  // -------------------------------------------------------------------------

  testWidgets('FIREREN: et tryk på brikken flytter IKKE — den spørger',
      (t) async {
    final GameState state = fourState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, isEmpty,
        reason: 'brikken kan to ting — trykket må ikke vælge for spilleren');
    // Indholdet, ikke bare at NOGET blev vist: begge retninger skal stå der,
    // og de skal stå som de retninger de er.
    expect(find.text('4 frem'), findsOneWidget);
    expect(find.text('4 tilbage'), findsOneWidget);
    expect(find.text('Annullér'), findsOneWidget,
        reason: 'uden en vej ud er et inline-valg en fælde');
  });

  testWidgets('FIREREN: knappen anvender præcis DET træk, der står på den',
      (t) async {
    final GameState state = fourState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
      await t.pumpAndSettle();
      await t.tap(find.text('4 tilbage'));
    });
    expect(applied, hasLength(1));
    // 20 − 4 = 16. Vælger knappen det andet træk, lander den på 24, og
    // dette tal gør testen rød.
    expect(applied.single.steps.single.to, const TrackPosition(16),
        reason: '"4 tilbage" skal føre BAGLÆNS, ikke fremad');
  });

  testWidgets('FIREREN: Annullér fortryder valget uden at flytte noget',
      (t) async {
    final GameState state = fourState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
      await t.pumpAndSettle();
      await t.tap(find.text('Annullér'));
    });
    expect(applied, isEmpty);
    expect(find.text('4 frem'), findsNothing,
        reason: 'knapperne skal være væk igen efter Annullér');
  });

  testWidgets(
      'ADMIN-OPSÆTNING: en firer der KUN kan baglæns spørger ikke — den rykker',
      (t) async {
    // Hele fladen udleder sine valg af de træk, motoren FANDT, og af
    // `state.cardRules` — som bærer admins gemte overrides. Er fireren sat
    // til kun baglæns, findes der ét lovligt træk for brikken, og så er der
    // intet at spørge om.
    final GameState state = backwardFourState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, hasLength(1),
        reason: 'ét lovligt træk → udfør det, spørg ikke');
    expect(applied.single.steps.single.to, const TrackPosition(16),
        reason: '20 − 4 = 16; fremad findes ikke i denne opsætning');
    // Og det, der IKKE må være der: hverken spørgsmålet eller en frem-knap.
    expect(find.text('Denne brik kan flere ting — vælg én:'), findsNothing);
    expect(find.text('4 frem'), findsNothing,
        reason: 'et træk admin har slået fra, må aldrig kunne vælges');
    expect(find.text('Annullér'), findsNothing);
  });

  testWidgets('KONGEN: brikken har allerede svaret — ingen knapper, træk straks',
      (t) async {
    // Kernen i den afledte placering. Kongen kan "ud af start" ELLER "13
    // frem", men aldrig for SAMME brik: en brik i start kan kun komme ud.
    // Derfor må der ikke spørges om noget her.
    final GameState state = kingState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, hasLength(1),
        reason: 'ét lovligt træk for brikken → udfør det, spørg ikke');
    expect(applied.single.exitsStart, isTrue);
    expect(find.text('Annullér'), findsNothing,
        reason: 'ingen knaprække må dukke op, når der intet er at vælge');
  });

  testWidgets('ESSET: brikken på banen tilbyder både 1 frem og 11 frem',
      (t) async {
    final GameState state = aceState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, isEmpty);
    expect(find.text('1 frem'), findsOneWidget);
    expect(find.text('11 frem'), findsOneWidget);
    // Og det, der IKKE må stå: ud-af-start hører til en ANDEN brik og må
    // aldrig blandes ind i denne briks valg.
    expect(find.text('Gå ud af start'), findsNothing);
  });

  testWidgets(
      'QC-FUND: et tryk på en ANDEN brik må ikke udføre noget, mens valget står åbent',
      (t) async {
    // Fejlen: mens knapperne for p0.0 stod fremme, var brættet stadig
    // tapbart. Et tryk på p0.1 — som har præcis ét lovligt træk — sendte den
    // brik ud af start ØJEBLIKKELIGT, og valget for p0.0 forsvandt lydløst.
    // Det modale ark spærrede brættet; den inline form skal spærre selv.
    final GameState state = aceState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.1'));
    });
    expect(applied, isEmpty,
        reason: 'p0.1 måtte ikke gå ud af start bag om det åbne valg');
    // Og valget skal stadig stå åbent — ikke være tabt på gulvet.
    expect(find.text('1 frem'), findsOneWidget);
    expect(find.text('11 frem'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Knægten: 11 frem ELLER 1×1. Det var her spørgsmålet var FORKLÆDT — det
  // stod som "Hvor mange felter?" med svarene "1 frem"/"11 frem", selv om
  // svaret i virkeligheden afgør, om kortet bliver ét stort træk eller to
  // små. Ingen kunne gætte det.
  // -------------------------------------------------------------------------

  testWidgets('KNÆGTEN: de to EVNER står som knapper — ikke som en afstand',
      (t) async {
    final GameState state = jackState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, isEmpty,
        reason: 'uafgjort evne-valg må ikke flytte noget');
    expect(find.text('11 frem'), findsOneWidget);
    expect(find.text('1 frem med 2 brikker'), findsOneWidget);
    // Det gamle, forklædte spørgsmål må IKKE være der længere.
    expect(find.text('Hvor mange felter?'), findsNothing);
  });

  testWidgets('KNÆGTEN: vælger man 11 frem, bliver det ÉT træk på ÉN brik',
      (t) async {
    final GameState state = jackState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tap(find.text('11 frem'));
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
    });
    expect(applied, hasLength(1));
    expect(applied.single.steps, hasLength(1),
        reason: 'ét stort træk — ikke to små');
    // 5 + 11 tællende felter = 17, fordi felt 15 er et fremmed UD-felt og
    // ikke tæller med. Ramte den 16, havde den talt UD-feltet.
    expect(applied.single.steps.single.to, const TrackPosition(17));
  });

  testWidgets('KNÆGTEN: vælger man 1×1, kræver det TO brikker — ét træk med to steps',
      (t) async {
    final GameState state = jackState();
    final List<Move> applied = await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tap(find.text('1 frem med 2 brikker'));
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
      await t.pumpAndSettle();
      // Første brik må IKKE have udløst et træk i sig selv.
      await t.tapAt(pieceSpot(t, state, 'p0.1'));
    });
    expect(applied, hasLength(1),
        reason: 'de to tryk er ÉT træk, ikke to');
    expect(applied.single.steps, hasLength(2));
    expect(
        applied.single.steps.map((MoveStep s) => s.pieceId).toSet(),
        <String>{'p0.0', 'p0.1'},
        reason: 'én brik hver, ikke samme brik to gange');
  });

  testWidgets('vælger man BYT, går trykket i byt-flowet — ikke flyt',
      (t) async {
    final List<Move> applied =
        await pumpAndPlay(t, choiceState(), act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Byt plads på to brikker'));
    });
    expect(applied, isEmpty, reason: 'byt kræver to brikker og en bekræftelse');
    expect(find.textContaining('Byt:'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // REGRESSION: splitTotal er IKKE en separat evne (se _hasSeparateMultiAbility).
  // -------------------------------------------------------------------------

  testWidgets(
      'SYVEREN (klassisk): splitTotal alene må ALDRIG udløse "kortet kan to ting"',
      (t) async {
    // En delt syver laver også BÅDE ét- og fler-briks-træk (7 på én brik,
    // eller fx 3+4 på to) — men det er samme evne brugt to måder, og
    // split-flowet spørger allerede brik for brik. Uden denne test stod
    // mutationen "_hasSeparateMultiAbility accepterer også splitTotal" grøn.
    final GameState state = sevenState();
    await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
    });
    // Det FORKERTE spørgsmål må aldrig stå på en syver.
    expect(find.text('Kortet kan to ting — vælg én:'), findsNothing);
    // Det RIGTIGE spørgsmål — split-flowets eget — skal stå i stedet.
    expect(find.textContaining('træk tilbage'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // REGRESSION: rutningen i _handlePieceTap skal RESPEKTERE det valgte flow
  // ("&& _multiPieceMode != false"), ellers falder et tryk i enkelt-tilstand
  // ned i splitflowets EGEN afstands-dialog i stedet for de inline knapper.
  // -------------------------------------------------------------------------

  testWidgets(
      'REGRESSION: valgt enkelt-brik-evne spørger INLINE — aldrig det gamle "Hvor mange felter?"-ark',
      (t) async {
    final GameState state = hybridTenState();
    await pumpAndPlay(t, state, act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      // To distinkte enkelt-briks-afstande (1 og 9 for BÅDE p0.0 og p0.1) →
      // _singleAbilityLabel falder tilbage til den generiske knap.
      await t.tap(find.text('Flyt én brik'));
      await t.pumpAndSettle();
      await t.tapAt(pieceSpot(t, state, 'p0.0'));
      await t.pumpAndSettle();
    });
    // Det gamle, forklædte spørgsmål må ALDRIG stå her — det er splitflowets
    // egen dialog, og enkelt-brik-evnen har allerede sit eget spørgsmål.
    expect(find.text('Hvor mange felter?'), findsNothing,
        reason:
            'et tryk i valgt enkelt-tilstand må ikke falde i splitflowets afstands-ark');
    // Det RIGTIGE spørgsmål: to inline knapper, én pr. afstand.
    expect(find.text('1 frem'), findsOneWidget);
    expect(find.text('9 frem'), findsOneWidget);
  });
}
