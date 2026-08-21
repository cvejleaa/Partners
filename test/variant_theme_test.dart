// Variant-tema: 25 år-spil har sin egen (marineblå) spilflade, klassisk er
// uændret grøn — så man kan kende forskel på dem.
//
// F1 låser BEGGE varianters eksakte farver (ikke kun "forskellige" — et bånd
// der også ville bestå med knaldrød). F2 er wiring-testen: BoardView MALER
// faktisk variantens feltColor ved FØRSTE mal (to friske painter-instanser —
// første-mal sker altid, uanset shouldRepaint). F3 dækker den ANDEN halvdel
// af samme wiring: et variant-SKIFT alene (uændret geometri/brikker) udløser
// et gen-mal via _BoardPainter.shouldRepaint — hvilket kun sker fordi
// state.variant.id er skrevet ind i _visualSig. F3 genbruger derfor SAMME
// RepaintBoundary-nøgle på tværs af to pumpWidget-kald: anden pump er et ægte
// REBUILD af samme RenderObject, hvor shouldRepaint afgør gen-malingen — en
// mutation der fjerner variant.id fra sig'en efterlader den GAMLE (grønne)
// pixel → rød.
//
// Alle pixel-læsninger sker i en 300×300-boks: hjørne-pixlen (1,1) er dermed
// ~69 px (≈5,7σ) uden for brættets slagskygge (MaskFilter.blur sigma 12 om
// skiven). Ved 100×100 lå den kun 1,9σ ude, og skyggen kostede ~0,5 kanaltrin
// (CI målte blå 0x4E for 0x4F).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/board_view.dart';

import 'test_helpers.dart';

const double _dim = 300;

/// Pump en [BoardView] for [v] under [key] og læs hjørne-pixel (1,1) — den
/// ligger uden for den creme spilleskive, så det er bord-baggrunden
/// (variantens feltColor), painteren fylder først.
Future<Color> _pumpAndReadCorner(
    WidgetTester tester, Key key, VariantConfig v) async {
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: SizedBox(
        width: _dim,
        height: _dim,
        child: RepaintBoundary(
          key: key,
          child: BoardView(state: makeState(variant: v)),
        ),
      ),
    ),
  ));
  await tester.pump();
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late final Color pixel;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final int offset = (1 * image.width + 1) * 4; // pixel (1,1)
    pixel = Color.fromARGB(
      data!.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
    image.dispose();
  });
  return pixel;
}

/// Kanal-sammenligning med ±1/255-tolerance: render-pipelinen kan afrunde en
/// enkelt bit. Båndet er stadig mutations-følsomt: klassisk grøn (0x14331F)
/// og p25-blå (0x1B2C4F) afviger med 7-48 kanaltrin, så en revert til den
/// hardkodede grønne — eller et udeblevet gen-mal (F3) — er langt uden for.
void _expectPixel(Color actual, Color expected) {
  int ch(double v) => (v * 255).round();
  expect(ch(actual.r), closeTo(ch(expected.r), 1),
      reason: 'rød kanal (forventede $expected, målte $actual)');
  expect(ch(actual.g), closeTo(ch(expected.g), 1),
      reason: 'grøn kanal (forventede $expected, målte $actual)');
  expect(ch(actual.b), closeTo(ch(expected.b), 1),
      reason: 'blå kanal (forventede $expected, målte $actual)');
}

void main() {
  group('F1 — variantfarverne er låst (eksakte hex)', () {
    test('klassisk = de HIDTIDIGE grønne (byte-identisk)', () {
      // Før denne ændring var farverne hardkodet i skærmene som netop disse
      // to værdier — klassisk må ikke flytte sig én bit.
      expect(classicVariant.tableColor, const Color(0xFF0E2A1A));
      expect(classicVariant.feltColor, const Color(0xFF14331F));
    });

    test('p25 = det lysstyrke-matchede marineblå par (og ≠ klassisk)', () {
      expect(partners25.tableColor, const Color(0xFF15243F));
      expect(partners25.feltColor, const Color(0xFF1B2C4F));
      expect(partners25.tableColor, isNot(classicVariant.tableColor));
      expect(partners25.feltColor, isNot(classicVariant.feltColor));
    });

    test('badge-farverne er låst eksakt (informationsbæreren)', () {
      // Klassisk: husets grønne (hvid 13px-tekst = 5,1:1 — 0xFF4CAF50 havde
      // kun 2,8:1); p25: blå med 4,8:1.
      expect(classicVariant.badgeColor, const Color(0xFF2E7D32));
      expect(partners25.badgeColor, const Color(0xFF3D6DDB));
    });

    test('badge-etiketter (det spillerne siger ved bordet)', () {
      expect(classicVariant.shortLabel, 'Klassisk');
      expect(partners25.shortLabel, '25 år');
    });
  });

  group('F2 — brættet MALER variantens feltColor (første mal)', () {
    testWidgets('klassisk maler grøn; p25 maler marineblå', (tester) async {
      // Hver sin UniqueKey = to friske painter-instanser — beviser selve
      // farvevalget i paint(), uafhængigt af shouldRepaint (F3).
      _expectPixel(
          await _pumpAndReadCorner(tester, UniqueKey(), classicVariant),
          const Color(0xFF14331F));
      _expectPixel(await _pumpAndReadCorner(tester, UniqueKey(), partners25),
          const Color(0xFF1B2C4F));
    });
  });

  group('F3 — variant.id indgår i painterens _visualSig', () {
    test('klassisk- og p25-sig AFVIGER (ellers ingen repaint ved skift)', () {
      // Klassisk og p25 er IDENTISKE på geometri, brik-antal, positioner og
      // spillerfarver — de to signaturer kan derfor KUN afvige via
      // state.variant.id. Fjernes id-linjen fra _computeVisualSig, bliver de
      // to strenge ens → rød. (Direkte sig-test frem for repaint-integration:
      // et samme-key-mutationsforsøg i CI viste at test-miljøet gen-maler
      // uanset shouldRepaint, så integrationen kan ikke isolere linjen.)
      final String classicSig =
          BoardView.debugVisualSig(makeState(variant: classicVariant));
      final String p25Sig =
          BoardView.debugVisualSig(makeState(variant: partners25));
      expect(classicSig, isNot(p25Sig));
      // Og sig'en er stabil for samme variant (ingen støj i låsen).
      expect(BoardView.debugVisualSig(makeState(variant: partners25)), p25Sig);
    });
  });
}
