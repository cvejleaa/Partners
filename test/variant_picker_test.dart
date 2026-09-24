// VariantPicker — DEN ENE variantvælger, som lokal opsætning, "Nyt spil" og
// lobbyen alle bruger (variant_picker.dart-docstring). To ting, der ikke
// dækkes andre steder, fordi de sidder i selve widget'en, ikke i en ren
// funktion:
//
// F1: [onChanged] == null skal vise LÆSEVISNING (Text), ikke en redigerbar
//     dropdown — det er sådan en gæst i lobbyen, der ikke må vælge, holdes
//     ude. En regression, der altid tegner dropdownen, ville lade gæsten
//     TRYKKE på et valg, der aldrig skulle være muligt.
// F2: en arkiveret variant, der IKKE længere findes i [variants] (fx en
//     slettet custom-variant, spillet allerede kører med), skal stadig kunne
//     vises som lobbyens/dialogens valgte værdi UDEN at DropdownButton kaster
//     sin "der skal være nøjagtig ét item med denne value"-assertion (et
//     rigtigt nedbrud, ikke kun forkert tekst).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/variant_picker.dart';

const VariantConfig _archived = VariantConfig(id: 'cv-old', name: 'Gamle Bo');

Widget _pickerApp({
  required VariantConfig selected,
  List<VariantConfig> variants = const <VariantConfig>[
    classicVariant,
    partners25,
  ],
  ValueChanged<String>? onChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: VariantPicker(
          variants: variants,
          selected: selected,
          nameOf: (VariantConfig v) => v.name,
          onChanged: onChanged,
        ),
      ),
    );

void main() {
  testWidgets('onChanged null: læsevisning (Text) — ingen dropdown at trykke på',
      (WidgetTester tester) async {
    await tester.pumpWidget(_pickerApp(selected: classicVariant));

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text(classicVariant.name), findsOneWidget);
  });

  testWidgets('onChanged sat: dropdown vises MED variantens navn som valg',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        _pickerApp(selected: classicVariant, onChanged: (String _) {}));

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    // Den valgte værdi optræder — dropdownens lukkede visning viser navnet.
    expect(find.text(classicVariant.name), findsWidgets);
  });

  testWidgets(
      'arkiveret valgt variant (ikke i variants): vises uden at DropdownButton crasher',
      (WidgetTester tester) async {
    await tester.pumpWidget(_pickerApp(
      selected: _archived,
      variants: const <VariantConfig>[classicVariant, partners25],
      onChanged: (String _) {},
    ));
    await tester.pumpAndSettle();

    // DropdownButton kræver præcis ét item med sin `value` — havde
    // VariantPicker IKKE tilføjet [_archived] til items-listen selv (den
    // sidder ikke i [variants]), ville byggetrinnet kaste en assertion her.
    expect(tester.takeException(), isNull);
    expect(find.text(_archived.name), findsOneWidget);
  });
}
