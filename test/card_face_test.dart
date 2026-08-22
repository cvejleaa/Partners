// Kortenes token-sprog (CardFace v2): glyf-VALGET er ren logik på den
// OPLØSTE config, og glyf-listen på CardFace er den ENE kilde (tooltip,
// maler og disse tests læser samme liste — ingen dobbelt-vagt).
//
// Mutations-følsomhed (designet, ikke håbet):
//  - `if (c.swap)` ↔ `if (c.jumpsBlockade)` byttet om → nine/five-testene
//    røde (de asserterer FORSKELLIGE glyf-typer).
//  - `&& c.forwardSteps.isNotEmpty` fjernet fra hop-vagten → "hop uden
//    frem-skridt (kun tilbage)"-testen rød (kortet ville love en evne uden
//    effekt). NB: den simple "ingen bevægelse"-variant af testen rammer
//    describeCardFace's sidste default-literal, som ALDRIG læser den lokale
//    `glyphs`-liste — den fanger IKKE denne mutation alene og bevises kun af
//    tilbage-varianten nedenfor, som går gennem "Kort med bevægelse"-grenen.
//  - 2 og 5 byttet i sekvens-tokenen → a/b-assertions røde.
//  - eyebrow-grænsen flippet → 48/56-widget-testene røde.
//  - glyf + gammel 8px-tekst begge beholdt → findsNothing-testene røde.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/card_view.dart';

CardRules get _p25Rules =>
    CardRules.defaults().withOverrides(partners25.cardRuleOverrides!);

CardFace _face(Rank r, CardRules rules) =>
    describeCardFace(PlayingCard(r, Suit.hearts), rules);

List<CardGlyphType> _types(Rank r, CardRules rules) =>
    _face(r, rules).glyphs.map((g) => g.type).toList();

void main() {
  group('glyf-valget (opløste regler, ingen rang-antagelser)', () {
    test('25 år: 4×1, 5↷, 7/+2−5, 9/⇄, 11/1×2 — hver sin glyf', () {
      expect(_types(Rank.four, _p25Rules), <CardGlyphType>[
        CardGlyphType.splitX1,
      ]);
      expect(_face(Rank.four, _p25Rules).bigNumber, '4');
      expect(_types(Rank.five, _p25Rules), <CardGlyphType>[
        CardGlyphType.jump,
      ]);
      expect(_types(Rank.seven, _p25Rules), <CardGlyphType>[
        CardGlyphType.seq,
      ]);
      // Rækkefølgen SKAL være 2 frem, 5 tilbage — byttes de, er kortet et
      // andet kort (netto −3 med dobbelt-hjemslånings-mulighed).
      final CardGlyph seq = _face(Rank.seven, _p25Rules).glyphs.single;
      expect(seq.a, 2);
      expect(seq.b, 5);
      expect(_types(Rank.nine, _p25Rules), <CardGlyphType>[
        CardGlyphType.swap,
      ]);
      final CardGlyph multi = _face(Rank.jack, _p25Rules).glyphs.single;
      expect(multi.type, CardGlyphType.multi);
      expect(multi.a, 1); // skridt
      expect(multi.b, 2); // brikker
    });

    test('klassisk: 7 = split, 4 = frem/tilbage-dobbeltpil, 6 = ingen glyf',
        () {
      expect(_types(Rank.seven, CardRules.defaults()),
          <CardGlyphType>[CardGlyphType.splitX1]);
      expect(_types(Rank.four, CardRules.defaults()),
          <CardGlyphType>[CardGlyphType.dirBoth]);
      // Et rent frem-kort har INGEN glyffer — maleren må ikke male noget
      // (blæk-testen nedenfor beviser det på pixels).
      expect(_types(Rank.six, CardRules.defaults()), isEmpty);
    });

    test('hop UDEN frem-skridt viser INTET hop-glyf (evnen har ingen effekt)',
        () {
      // NB: dette kort har HVERKEN frem- eller tilbage-skridt, exitStart
      // eller swap — describeCardFace falder derfor helt igennem til den
      // sidste default-literal (`eyebrow: '—' ...`), som er en konstant med
      // TOM glyphs-liste og ALDRIG læser den lokale `glyphs`-variabel hop-
      // guarden bygger. Testen er derfor grøn UANSET om
      // `&& c.forwardSteps.isNotEmpty` findes — den beviser kun at et helt
      // virkningsløst kort ikke viser noget. Den reelle guard bevises af
      // testen nedenfor (kort med KUN tilbage-skridt, som rent faktisk går
      // gennem grenen der bruger `glyphs`).
      final CardRules rules = CardRules.defaults()
          .withRank(Rank.six, const CardRuleConfig(jumpsBlockade: true));
      expect(_types(Rank.six, rules), isEmpty);
    });

    test(
        'hop UDEN frem-skridt (kun tilbage-træk) viser INTET hop-glyf — '
        'dækker guarden i den gren der FAKTISK læser glyphs', () {
      // backwardSteps sat (ingen forwardSteps) → kortet går gennem "Kort med
      // bevægelse"-grenen (hasBackward), som konsumerer den lokale glyphs-
      // liste. Fjernes `&& c.forwardSteps.isNotEmpty` fra hop-guarden, ville
      // dette kort forkert vise et hop-glyf — DENNE assertion bliver rød.
      final CardRules rules = CardRules.defaults().withRank(
          Rank.six, const CardRuleConfig(backwardSteps: 4, jumpsBlockade: true));
      expect(_types(Rank.six, rules), isEmpty);
    });

    test('tooltip-teksten bygges af SAMME glyf-liste (én kilde)', () {
      final String seven =
          cardFunctionSummary(PlayingCard(Rank.seven, Suit.hearts), _p25Rules);
      expect(seven, contains('2 frem → 5 tilbage'));
      final String four = cardFunctionSummary(
          PlayingCard(Rank.four, Suit.hearts), CardRules.defaults());
      expect(four, contains('frem eller tilbage'));
      final String split = cardFunctionSummary(
          PlayingCard(Rank.seven, Suit.hearts), CardRules.defaults());
      expect(split, contains('del over dine brikker'));
    });
  });

  group('widget ved 48 px (håndens FAKTISKE maksbredde)', () {
    Widget host(PlayingCard card, CardRules rules, double width, Key key) =>
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: CardView(card: card, rules: rules, width: width),
            ),
          ),
        );

    testWidgets('8 px-prosaen er VÆK — glyf i stedet (negativ assertion)',
        (tester) async {
      // En regression der beholder BÅDE glyf og den gamle tekst ville ellers
      // bestå glyf-testene.
      await tester.pumpWidget(host(PlayingCard(Rank.seven, Suit.hearts),
          CardRules.defaults(), 48, UniqueKey()));
      expect(find.text('del over dine brikker'), findsNothing);
      expect(find.textContaining('del over'), findsNothing);
      await tester.pumpWidget(host(PlayingCard(Rank.four, Suit.hearts),
          CardRules.defaults(), 48, UniqueKey()));
      expect(find.text('frem eller tilbage'), findsNothing);
    });

    testWidgets('eyebrow skæres under 56 px (7 px-tekst) og vises ved 56',
        (tester) async {
      await tester.pumpWidget(host(PlayingCard(Rank.seven, Suit.hearts),
          CardRules.defaults(), 48, UniqueKey()));
      expect(find.text('SPECIAL'), findsNothing);
      await tester.pumpWidget(host(PlayingCard(Rank.seven, Suit.hearts),
          CardRules.defaults(), 56, UniqueKey()));
      expect(find.text('SPECIAL'), findsOneWidget);
    });

    testWidgets('split-tokenen ×1 står på kortet (25 år-4 ≠ klassisk 4)',
        (tester) async {
      await tester.pumpWidget(host(PlayingCard(Rank.four, Suit.hearts),
          _p25Rules, 48, UniqueKey()));
      expect(find.text('×1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('"frem" skrives IKKE på kortet (sort tal = frem); '
        '"tilbage" vises fortsat', (tester) async {
      // Brugerens fund: ordet stod på hvert eneste flyt-kort og var støj.
      await tester.pumpWidget(host(PlayingCard(Rank.six, Suit.hearts),
          CardRules.defaults(), 48, UniqueKey()));
      expect(find.text('frem'), findsNothing);
      // Tilbage-kort: rødt tal + ordet (sjældent nok til at ordet bærer).
      final CardRules backRules = CardRules.defaults()
          .withRank(Rank.six, const CardRuleConfig(backwardSteps: 6));
      await tester.pumpWidget(host(PlayingCard(Rank.six, Suit.hearts),
          backRules, 48, UniqueKey()));
      expect(find.text('tilbage'), findsOneWidget);
      // Tooltip-teksten BEHOLDER ordet (opslags-sproget er uændret).
      expect(
          cardFunctionSummary(
              PlayingCard(Rank.six, Suit.hearts), CardRules.defaults()),
          contains('frem'));
    });

    testWidgets('"tilbage"-ordet er RØDT på rene tilbage-kort (følger tallet)',
        (tester) async {
      // QC-fund: ordet er kortets eneste retningsord og må ikke modsige
      // tallets farve. Rødt = 0xFFC62828 (samme _cInkBack som tallet).
      final CardRules backRules = CardRules.defaults()
          .withRank(Rank.six, const CardRuleConfig(backwardSteps: 6));
      await tester.pumpWidget(host(PlayingCard(Rank.six, Suit.hearts),
          backRules, 48, UniqueKey()));
      final Text word = tester.widget<Text>(find.text('tilbage'));
      expect(word.style!.color, const Color(0xFFC62828));
    });

    testWidgets('glyf-only-kort (ren byt) renderer glyffet STORT — ikke i '
        'token-rækkens størrelse', (tester) async {
      // Brugerens fund på legenden: byt-glyffet druknede. Hero-størrelsen er
      // 0,42×bredden (48 → 20,2 px); token-rækkens er (48×0,24)=11,5 px.
      // Båndet ≥19 udelukker altså den GAMLE (række-)størrelse.
      Size swapPaintSize() => tester
          .widget<CustomPaint>(find.byWidgetPredicate((w) =>
              w is CustomPaint && w.painter is SwapGlyphPainter))
          .size;
      final CardRules swapOnly = CardRules.defaults()
          .withRank(Rank.jack, const CardRuleConfig(swap: true));
      await tester.pumpWidget(host(
          PlayingCard(Rank.jack, Suit.hearts), swapOnly, 48, UniqueKey()));
      expect(swapPaintSize().height, greaterThanOrEqualTo(19.0));
      // På et kort MED tal (9/⇄) er glyffet fortsat i række-størrelse.
      final CardRules nineSwap = CardRules.defaults().withRank(Rank.nine,
          const CardRuleConfig(forwardSteps: <int>[9], swap: true));
      await tester.pumpWidget(host(
          PlayingCard(Rank.nine, Suit.hearts), nineSwap, 48, UniqueKey()));
      expect(swapPaintSize().height, lessThan(12.0));
    });

    // ---- Blæk-tests: maleren MALES faktisk, og forskellige mekanikker
    // maler FORSKELLIGT. Sammenligninger (ikke absolutte koordinater), så
    // layout-justeringer ikke vælter dem — og kortenes skygge går ud mod
    // begge sider af sammenligningen.

    Future<int> inkCount(WidgetTester tester, Key key,
        bool Function(int r, int g, int b) predicate) async {
      final RenderRepaintBoundary boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      late int count;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage();
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        count = 0;
        for (int i = 0; i < data!.lengthInBytes; i += 4) {
          if (predicate(
              data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2))) {
            count++;
          }
        }
        image.dispose();
      });
      return count;
    }

    bool red(int r, int g, int b) => r > 150 && g < 100 && b < 100;

    testWidgets(
        'retningsfarven males: p25-7 (−5 tilbage) har RØDE pixels, et rent '
        'frem-kort har INGEN', (tester) async {
      final Key k1 = UniqueKey();
      await tester.pumpWidget(host(
          PlayingCard(Rank.seven, Suit.hearts), _p25Rules, 48, k1));
      final int seqRed = await inkCount(tester, k1, red);
      expect(seqRed, greaterThan(0),
          reason: 'sekvens-tokenens −5 skal males rødt');

      final Key k2 = UniqueKey();
      await tester.pumpWidget(host(
          PlayingCard(Rank.six, Suit.hearts), CardRules.defaults(), 48, k2));
      final int fwdRed = await inkCount(tester, k2, red);
      expect(fwdRed, 0,
          reason: 'et rent frem-kort må ikke have røde pixels — ellers kan '
              'sort/rød ombyttes med grøn suite');
    });

    testWidgets('byt- og hop-glyfferne maler FORSKELLIGE tegninger',
        (tester) async {
      // Samme kort-skal (9 frem), kun mekanikken afviger — al forskel i blæk
      // kommer fra glyffet. En mutation der genbruger samme tegning til
      // begge ville give ens blæk-tal.
      bool ink(int r, int g, int b) => r < 200 || g < 200 || b < 200;
      final CardRules swapRules = CardRules.defaults().withRank(Rank.nine,
          const CardRuleConfig(forwardSteps: <int>[9], swap: true));
      final CardRules jumpRules = CardRules.defaults().withRank(Rank.nine,
          const CardRuleConfig(forwardSteps: <int>[9], jumpsBlockade: true));
      final Key k1 = UniqueKey();
      await tester.pumpWidget(
          host(PlayingCard(Rank.nine, Suit.hearts), swapRules, 48, k1));
      final int swapInk = await inkCount(tester, k1, ink);
      final Key k2 = UniqueKey();
      await tester.pumpWidget(
          host(PlayingCard(Rank.nine, Suit.hearts), jumpRules, 48, k2));
      final int jumpInk = await inkCount(tester, k2, ink);
      expect((swapInk - jumpInk).abs(), greaterThan(10),
          reason: 'to mekanikker med samme tegning kan ikke skelnes');
      // Og begge maler faktisk MERE end kortet uden mekanik.
      final CardRules plainRules = CardRules.defaults().withRank(
          Rank.nine, const CardRuleConfig(forwardSteps: <int>[9]));
      final Key k3 = UniqueKey();
      await tester.pumpWidget(
          host(PlayingCard(Rank.nine, Suit.hearts), plainRules, 48, k3));
      final int plainInk = await inkCount(tester, k3, ink);
      expect(swapInk, greaterThan(plainInk + 10));
      expect(jumpInk, greaterThan(plainInk + 10));
    });
  });
}
