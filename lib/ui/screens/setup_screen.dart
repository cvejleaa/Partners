import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/palette.dart';
import '../../app.dart';
import '../../game/ai/ai_player.dart';
import '../../models/variant_config.dart';
import '../../state/card_rules_controller.dart';
import '../../state/variant_card_rules_controller.dart';
import '../widgets/variant_picker.dart';
import 'admin_screen.dart';
import 'game_screen.dart';
import 'self_test_screen.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final List<TextEditingController> _names = <TextEditingController>[
    TextEditingController(text: 'Du'),
    TextEditingController(text: 'AI 1'),
    TextEditingController(text: 'AI 2 (makker)'),
    TextEditingController(text: 'AI 3'),
  ];

  final List<int> _colorIdx = <int>[0, 1, 2, 3];

  /// Hvilken plads spilleren selv sidder på.
  int _humanSeat = 0;

  /// Valgt AI-sværhedsgrad (0=Begynder, 1=Normal, 2=Skarp).
  int _aiLevel = kAiLevelDefault;

  /// Valgt variant-ID. Default klassisk. Afgør bræt/kort — vælges FØRST,
  /// fordi "hvad spiller vi" bestemmer resten af opsætningen. Id frem for
  /// config-instans: listen (inkl. admins egne varianter) materialiseres pr.
  /// build af selectableVariantsProvider, så instanserne er ikke stabile.
  String _variantId = classicVariant.id;

  VariantConfig _variantFrom(List<VariantConfig> list) => list.firstWhere(
      (VariantConfig v) => v.id == _variantId,
      orElse: () => classicVariant);

  /// Navn/beskrivelse med admins evt. egne tekster. Customs bærer allerede
  /// deres admin-navn/-beskrivelse fra materialiseringen (variantFromRaw);
  /// de indbyggede varianter med egne kort (25 år, Duo) har en kode-tekst,
  /// som admin kan afløse.
  String _displayName(VariantConfig v) => variantNameFrom(
      v,
      isEditableBuiltin(v.id)
          ? ref.watch(variantCardRulesProvider).configFor(v.id).name
          : null);

  String? _displayDescription(VariantConfig v) => variantDescriptionFrom(
      v,
      isEditableBuiltin(v.id)
          ? ref.watch(variantCardRulesProvider).configFor(v.id).description
          : null);

  @override
  void dispose() {
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rækker i opsætningen: én pr. HÅND. Klassisk 4; Duo 2 (du og
  /// modstanderen) — hver række styrer to sæt på brættet.
  int _rowCount(VariantConfig v) => v.handCount(4);

  @override
  Widget build(BuildContext context) {
    final VariantConfig chosen =
        _variantFrom(ref.watch(selectableVariantsProvider));
    final int rows = _rowCount(chosen);
    // Sikkerhedsnet ud over nulstillingen i variant-vælgeren: "Dig" kan
    // aldrig sidde på en skjult række.
    final int humanSeat = _humanSeat < rows ? _humanSeat : 0;
    final bool unique = _colorIdx.take(rows).toSet().length == rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partners — Opsætning'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Admin — kortfunktioner',
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Kør selvtest',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SelfTestScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              chosen.seatsShareController
                  ? 'Indtast navn og vælg farve for dig og din modstander. '
                      'I Duo styrer I hver to sæt brikker i samme farve — '
                      'ring og prik — og hvert sæt har sit eget mål.'
                  : 'Indtast navn og vælg farve for hver spiller. Marker din '
                      'egen plads med radioknappen — brættet roteres så du '
                      'sidder nederst. Pladsen overfor er din makker.',
            ),
            const SizedBox(height: 16),
            // Variant FØRST: "hvad spiller vi" bestemmer bræt og kort. Dropdown
            // (ikke SegmentedButton), så den kan rumme flere kommende varianter.
            // Listen/varianten/beskrivelsen beregnes ÉN gang pr. build
            // (QC-fund: fire watch-kald og dobbeltberegning før).
            // Samme vælger som online ("Nyt spil" og lobbyen): VariantPicker.
            Builder(builder: (BuildContext context) {
              final List<VariantConfig> variants =
                  ref.watch(selectableVariantsProvider);
              return VariantPicker(
                variants: variants,
                // Arkiveres den valgte custom mens skærmen er åben, falder
                // den til klassisk (samme fallback som _variantFrom).
                selected: _variantFrom(variants),
                nameOf: _displayName,
                descriptionOf: _displayDescription,
                onChanged: (String id) => setState(() {
                  _variantId = id;
                  // Duo har kun to rækker: sad "Dig" på en række, der nu er
                  // skjult, flyttes du op.
                  if (_humanSeat >= _rowCount(_variantFrom(variants))) {
                    _humanSeat = 0;
                  }
                }),
              );
            }),
            const SizedBox(height: 12),
            RadioGroup<int>(
              groupValue: humanSeat,
              onChanged: (int? v) {
                if (v != null) setState(() => _humanSeat = v);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < rows; i++) ...<Widget>[
                    _PlayerRow(
                      index: i,
                      nameController: _names[i],
                      colorIdx: _colorIdx[i],
                      isHuman: i == humanSeat,
                      onColorChanged: (int c) =>
                          setState(() => _colorIdx[i] = c),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const Spacer(),
            // AI-sværhedsgrad. Parametrene bag graderne kan justeres i Admin.
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.smart_toy, size: 18),
                  const SizedBox(width: 8),
                  const Text('AI-sværhed:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: <ButtonSegment<int>>[
                        for (int i = 0; i < kAiLevelNames.length; i++)
                          ButtonSegment<int>(
                              value: i, label: Text(kAiLevelNames[i])),
                      ],
                      selected: <int>{_aiLevel},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<int> s) =>
                          setState(() => _aiLevel = s.first),
                    ),
                  ),
                ],
              ),
            ),
            if (!unique)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  rows == 2
                      ? 'Vælg to forskellige farver.'
                      : 'Vælg fire forskellige farver.',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: unique
                    ? () async {
                        // Hent altid friske kortregler fra Firestore inden
                        // spillet starter, så admin-ændringer slår igennem —
                        // BÅDE de klassiske og variantens egne.
                        await ref.read(cardRulesProvider.notifier).refresh();
                        await ref
                            .read(variantCardRulesProvider.notifier)
                            .refresh();
                        if (!context.mounted) return;
                        // Opløs spillets faktiske kortregler ÉN gang her:
                        // klassisk live + variantens overrides (admin-gemte
                        // vinder over kode-seedet; en custom uden entry =
                        // klassisk). startGame opløser ikke selv.
                        final VariantConfig variant = _variantFrom(
                            ref.read(selectableVariantsProvider));
                        final List<PlayerSetup> setups =
                            playerSetupsFor(variant, <RowSetup>[
                          for (int i = 0; i < _rowCount(variant); i++)
                            (
                              name: _names[i].text.trim(),
                              color: kPalette[_colorIdx[i]].color,
                              isHuman: i == humanSeat,
                            ),
                        ]);
                        final VariantAdminConfig vc = ref
                            .read(variantCardRulesProvider)
                            .configFor(variant.id);
                        ref.read(gameProvider.notifier).startGame(
                              setups,
                              cardRules: effectiveCardRules(
                                variant,
                                ref.read(cardRulesProvider),
                                stored: vc.stored ? vc.overrides : null,
                              ),
                              aiLevel: _aiLevel,
                              variant: variant,
                            );
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const GameScreen(),
                          ),
                        );
                      }
                    : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Start spil'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Én udfyldt række i opsætningen.
typedef RowSetup = ({String name, Color color, bool isHuman});

/// Pladserne på brættet ud fra opsætningens rækker. Klassisk: række i =
/// plads i. Duo: to rækker (hånd-pladserne 0 og 1); plads 2 og 3 er deres
/// andet sæt og arver navn, farve og menneske/AI fra den plads, der styrer
/// dem ([VariantConfig.controllerOf]) — ellers ville et AI-flag eller en
/// farve på en håndløs plads kunne afvige fra spilleren, der rykker den.
List<PlayerSetup> playerSetupsFor(VariantConfig v, List<RowSetup> rows) {
  return <PlayerSetup>[
    for (int seat = 0; seat < 4; seat++)
      () {
        final int row = v.controllerOf(seat);
        final RowSetup r = rows[row];
        return PlayerSetup(
          name: r.name.isEmpty ? 'Spiller ${row + 1}' : r.name,
          color: r.color,
          isHuman: r.isHuman,
        );
      }(),
  ];
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.index,
    required this.nameController,
    required this.colorIdx,
    required this.isHuman,
    required this.onColorChanged,
  });

  final int index;
  final TextEditingController nameController;
  final int colorIdx;
  final bool isHuman;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Radio<int>(
          value: index,
        ),
        SizedBox(
          width: 64,
          child: Text(isHuman ? 'Dig' : 'AI ${index + 1}'),
        ),
        Expanded(
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Navn',
            ),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: colorIdx,
          items: <DropdownMenuItem<int>>[
            for (int i = 0; i < kPalette.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: kPalette[i].color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(kPalette[i].name),
                  ],
                ),
              ),
          ],
          onChanged: (int? v) {
            if (v != null) onColorChanged(v);
          },
        ),
      ],
    );
  }
}
