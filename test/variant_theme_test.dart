// Variant-tema: 25 år-spil har sin egen (marineblå) spilflade, klassisk er
// uændret grøn — så man kan kende forskel på dem.
//
// F1 låser BEGGE varianters eksakte farver (ikke kun "forskellige" — et bånd
// der også ville bestå med knaldrød). F2 er wiring-testen: BoardView MALER
// faktisk variantens feltColor (pixel-læsning af den rå canvas — en mutation
// der ruller painteren tilbage til den hardkodede grønne, holder F1 grøn men
// gør F2 rød).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/board_view.dart';

import 'test_helpers.dart';

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
      expect(partners25.badgeColor, isNot(classicVariant.badgeColor));
    });

    test('badge-etiketter (det spillerne siger ved bordet)', () {
      expect(classicVariant.shortLabel, 'Klassisk');
      expect(partners25.shortLabel, '25 år');
    });
  });

  group('F2 — brættet MALER variantens feltColor (pixel-wiring)', () {
    Future<Color> cornerPixel(WidgetTester tester, VariantConfig v) async {
      final st = makeState(variant: v);
      final Key key = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: RepaintBoundary(
              key: key,
              child: BoardView(state: st),
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

    // Kanal-sammenligning med ±1/255-tolerance: render-pipelinen kan afrunde
    // en enkelt bit (CI målte blå 0x4E for 0x4F). Båndet er stadig mutations-
    // følsomt: klassisk grøn (0x14331F) og p25-blå (0x1B2C4F) afviger med
    // 7-48 kanaltrin, så en revert til den hardkodede grønne er langt uden
    // for båndet.
    void expectPixel(Color actual, Color expected) {
      int ch(double v) => (v * 255).round();
      expect(ch(actual.r), closeTo(ch(expected.r), 1),
          reason: 'rød kanal (forventede $expected, målte $actual)');
      expect(ch(actual.g), closeTo(ch(expected.g), 1),
          reason: 'grøn kanal (forventede $expected, målte $actual)');
      expect(ch(actual.b), closeTo(ch(expected.b), 1),
          reason: 'blå kanal (forventede $expected, målte $actual)');
    }

    testWidgets('klassisk maler grøn; p25 maler marineblå', (tester) async {
      // Hjørne-pixlen ligger UDEN FOR den creme spilleskive — det er præcis
      // bord-baggrunden painteren fylder først.
      expectPixel(await cornerPixel(tester, classicVariant),
          const Color(0xFF14331F));
      expectPixel(
          await cornerPixel(tester, partners25), const Color(0xFF1B2C4F));
    });
  });
}
