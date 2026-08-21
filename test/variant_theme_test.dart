// Variant-tema: 25 år-spil har sin egen (marineblå) spilflade, klassisk er
// uændret grøn — så man kan kende forskel på dem.
//
// F1 låser BEGGE varianters eksakte farver (ikke kun "forskellige" — et bånd
// der også ville bestå med knaldrød). F2 er wiring-testen: BoardView MALER
// faktisk variantens feltColor (pixel-læsning af den rå canvas — en mutation
// der ruller painteren tilbage til den hardkodede grønne, holder F1 grøn men
// gør F2 rød). F3 dækker den ANDEN halvdel af samme wiring: at et variant-
// skift ALENE (uændret geometri/brikker) rent faktisk udløser et gen-mal via
// _BoardPainter.shouldRepaint — hvilket kun sker fordi state.variant.id er
// skrevet ind i _visualSig. F2's to kald bruger hver sin UniqueKey og monterer
// derfor to HELT NYE painter-instanser (første-mal sker altid, uanset
// shouldRepaint) — det dækker IKKE en fjernelse af variant.id fra sig'en. F3
// genbruger SAMME RepaintBoundary-nøgle på tværs af to pumpWidget-kald, så
// anden pump er et ægte REBUILD af samme RenderObject, hvor shouldRepaint
// faktisk afgør om der gen-males.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/board_view.dart';

import 'test_helpers.dart';

/// Hjørne-pixel (1,1) af en monteret/rebuildet [BoardView] i en 100×100-boks —
/// ligger uden for den creme spilleskive (se F2), så det er bord-baggrunden
/// (variantens feltColor) painteren fylder først.
Future<Color> _cornerPixelAt(WidgetTester tester, RenderRepaintBoundary boundary) async {
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

// Kanal-sammenligning med ±1/255-tolerance: render-pipelinen kan afrunde en
// enkelt bit (CI målte blå 0x4E for 0x4F). Båndet er stadig mutations-
// følsomt: klassisk grøn (0x14331F) og p25-blå (0x1B2C4F) afviger med 7-48
// kanaltrin, så en revert til den hardkodede grønne — eller et uændret
// gen-mal, se F3 — er langt uden for båndet.
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

  group('F2 — brættet MALER variantens feltColor (pixel-wiring)', () {
    // 300×300: hjørne-pixlen (1,1) er dermed ~69 px (≈5,7σ) uden for brættets
    // slagskygge (MaskFilter.blur sigma 12 om skiven) — ved 100×100 lå den kun
    // 1,9σ ude, og skyggen kostede ~0,5 kanaltrin (CI målte 0x4E for 0x4F).
    // ±1-tolerancen beholdes som værn mod ren afrunding; grøn/blå afviger
    // 7-48 kanaltrin, så en revert af painteren er stadig langt uden for.
    const double dim = 300;

    void expectPixel(Color actual, Color expected) {
      int ch(double v) => (v * 255).round();
      expect(ch(actual.r), closeTo(ch(expected.r), 1),
          reason: 'rød kanal (forventede $expected, målte $actual)');
      expect(ch(actual.g), closeTo(ch(expected.g), 1),
          reason: 'grøn kanal (forventede $expected, målte $actual)');
      expect(ch(actual.b), closeTo(ch(expected.b), 1),
          reason: 'blå kanal (forventede $expected, målte $actual)');
    }

    Future<Color> pumpAndRead(
        WidgetTester tester, Key key, VariantConfig v) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: dim,
            height: dim,
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

    testWidgets('klassisk maler grøn; p25 maler marineblå — med SAMME key',
        (tester) async {
      // Hjørne-pixlen ligger uden for den creme spilleskive — det er præcis
      // bord-baggrunden painteren fylder først. SAMME key for begge pump:
      // widget-træet genbruges, så variant-skiftet går gennem shouldRepaint —
      // en mutation der fjerner variant.id fra _visualSig efterlader den
      // GAMLE (grønne) pixel efter skiftet → rød.
      const Key key = ValueKey<String>('theme-board');
      expectPixel(await pumpAndRead(tester, key, classicVariant),
          const Color(0xFF14331F));
      expectPixel(await pumpAndRead(tester, key, partners25),
          const Color(0xFF1B2C4F));
    });
  });
}
