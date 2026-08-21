import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/palette.dart';
import '../../app.dart';
import '../../game/ai/ai_player.dart';
import '../../models/variant_config.dart';
import '../../state/card_rules_controller.dart';
import '../../state/variant_card_rules_controller.dart';
import '../widgets/variant_badge.dart';
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
  /// kun 25 år har en kode-tekst der kan afløses.
  String _displayName(VariantConfig v) => variantNameFrom(
      v,
      v.id == partners25.id
          ? ref
              .watch(variantCardRulesProvider)
              .configFor(partners25.id)
              .name
          : null);

  String? _displayDescription(VariantConfig v) => variantDescriptionFrom(
      v,
      v.id == partners25.id
          ? ref
              .watch(variantCardRulesProvider)
              .configFor(partners25.id)
              .description
          : null);

  @override
  void dispose() {
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool unique = _colorIdx.toSet().length == 4;
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
            const Text(
              'Indtast navn og vælg farve for hver spiller. Marker din egen '
              'plads med radioknappen — brættet roteres så du sidder nederst. '
              'Pladsen overfor er din makker.',
            ),
            const SizedBox(height: 16),
            // Variant FØRST: "hvad spiller vi" bestemmer bræt og kort. Dropdown
            // (ikke SegmentedButton), så den kan rumme flere kommende varianter.
            // Listen/varianten/beskrivelsen beregnes ÉN gang pr. build
            // (QC-fund: fire watch-kald og dobbeltberegning før).
            Builder(builder: (BuildContext context) {
              final List<VariantConfig> variants =
                  ref.watch(selectableVariantsProvider);
              final VariantConfig current = _variantFrom(variants);
              final String? desc = _displayDescription(current);
              // Arkiveres den valgte custom mens skærmen er åben, ryger den
              // ud af listen — dropdown-value skal så falde til klassisk
              // (samme fallback som _variantFrom bruger for reglerne).
              final String dropdownValue =
                  variants.any((VariantConfig v) => v.id == _variantId)
                      ? _variantId
                      : classicVariant.id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      VariantBadge(variant: current, compact: true),
                      const SizedBox(width: 8),
                      const Text('Spil:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: dropdownValue,
                          items: <DropdownMenuItem<String>>[
                            // Indbyggede + admins egne (ikke-arkiverede).
                            for (final VariantConfig v in variants)
                              DropdownMenuItem<String>(
                                  value: v.id,
                                  child: Text(_displayName(v),
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (String? id) {
                            if (id != null) {
                              setState(() => _variantId = id);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (desc != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        desc,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 12),
            RadioGroup<int>(
              groupValue: _humanSeat,
              onChanged: (int? v) {
                if (v != null) setState(() => _humanSeat = v);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < 4; i++) ...<Widget>[
                    _PlayerRow(
                      index: i,
                      nameController: _names[i],
                      colorIdx: _colorIdx[i],
                      isHuman: i == _humanSeat,
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
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Vælg fire forskellige farver.',
                  style: TextStyle(color: Colors.red),
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
                        final List<PlayerSetup> setups = <PlayerSetup>[
                          for (int i = 0; i < 4; i++)
                            PlayerSetup(
                              name: _names[i].text.trim().isEmpty
                                  ? 'Spiller ${i + 1}'
                                  : _names[i].text.trim(),
                              color: kPalette[_colorIdx[i]].color,
                              isHuman: i == _humanSeat,
                            ),
                        ];
                        // Opløs spillets faktiske kortregler ÉN gang her:
                        // klassisk live + variantens overrides (admin-gemte
                        // vinder over kode-seedet; en custom uden entry =
                        // klassisk). startGame opløser ikke selv.
                        final VariantConfig variant = _variantFrom(
                            ref.read(selectableVariantsProvider));
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
