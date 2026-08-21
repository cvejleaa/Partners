import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';
import '../../game/ai/ai_player.dart';
import '../../models/variant_config.dart';
import '../../online/online_service.dart';
import '../../state/card_rules_controller.dart';
import '../../state/display_config.dart';
import '../../state/variant_card_rules_controller.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  static const List<Rank> _order = <Rank>[
    Rank.ace,
    Rank.two,
    Rank.three,
    Rank.four,
    Rank.five,
    Rank.six,
    Rank.seven,
    Rank.eight,
    Rank.nine,
    Rank.ten,
    Rank.jack,
    Rank.queen,
    Rank.king,
  ];

  static String _label(Rank r) => PlayingCard(r, Suit.spades).rankLabel;

  static String _hhmmss(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (!isAdmin(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock, size: 56, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  user == null
                      ? 'Du skal være logget ind som admin.'
                      : 'Kun admin kan ændre kortfunktioner.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ctrl = ref.read(cardRulesProvider.notifier);
    final variantCtrl = ref.read(variantCardRulesProvider.notifier);
    final String saveErr = ref.watch(cardRulesSaveErrorProvider);
    final String variantSaveErr = ref.watch(variantCardRulesSaveErrorProvider);
    final CardRulesStatus status = ref.watch(cardRulesStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Kortfunktioner'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Hent fra database NU (klassisk + 25 år)',
            icon: const Icon(Icons.cloud_download, color: Colors.white),
            onPressed: () async {
              // BEGGE datasæt — ellers lyver knappen om det ene.
              await ctrl.refresh();
              await variantCtrl.refresh();
              if (context.mounted) {
                final s = ref.read(cardRulesStatusProvider);
                final vs = ref.read(variantCardRulesLoadSourceProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(s.lastLoadError.isEmpty
                          ? 'Hentet — klassisk: ${s.lastLoadSource} · '
                              '25 år: $vs'
                          : 'Læsefejl: ${s.lastLoadError}')),
                );
              }
            },
          ),
          TextButton.icon(
            onPressed: () async {
              // BEGGE datasæt gemmes; fejl rapporteres pr. datasæt, så et
              // fejlet 25 år-gem aldrig maskeres af et grønt klassisk-gem.
              await ctrl.retrySave();
              await variantCtrl.retrySave();
              if (context.mounted) {
                final err = ref.read(cardRulesSaveErrorProvider);
                final vErr = ref.read(variantCardRulesSaveErrorProvider);
                // Intet variant-entry gemt = seedet gælder og der skrives
                // bevidst ikke — sig det, frem for at påstå "gemt".
                final bool vStored =
                    ref.read(variantCardRulesProvider).entries.isNotEmpty;
                final String msg = err.isEmpty && vErr.isEmpty
                    ? (vStored
                        ? 'Gemt (klassisk + varianter)'
                        : 'Gemt (klassisk) · 25 år følger de indbyggede '
                            'specialkort (intet at gemme)')
                    : <String>[
                        if (err.isNotEmpty) 'Klassisk: $err',
                        if (vErr.isNotEmpty) '25 år: $vErr',
                      ].join(' · ');
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              }
            },
            icon: const Icon(Icons.cloud_upload, color: Colors.white),
            label: const Text('Gem nu', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () async {
              // Nulstil rammer BEGGE datasæt — dialogen siger præcis hvad der
              // sker, for 25 år-delen sletter admins eget arbejde.
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  title: const Text('Nulstil kortregler?'),
                  content: const Text(
                      'Klassisk sættes til standardreglerne. Partners 25 år '
                      'mister dine tilpasninger og går tilbage til de fem '
                      'indbyggede specialkort (4×1, 5↷, 7/+2−5, byt/9, '
                      '11/1×1). Dette kan ikke fortrydes.'),
                  actions: <Widget>[
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annullér')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Nulstil begge')),
                  ],
                ),
              );
              if (ok != true) return;
              ctrl.resetDefaults();
              // Kun 25 år nulstilles — egne varianter er admins arbejde og
              // røres ikke af den generelle nulstilling (de har deres egne
              // "Nulstil kort"/"Arkivér"-greb i variant-sektionen).
              await variantCtrl.resetRules(partners25.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Nulstillet: klassisk = standard, 25 år = de fem specialkort')));
              }
            },
            icon: const Icon(Icons.restore, color: Colors.white),
            label: const Text('Nulstil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          if (saveErr.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Kunne ikke gemme i databasen',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  Text(saveErr, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text(
                    'Indstillingen virker stadig lokalt indtil næste deploy '
                    'eller anden enhed.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          // DB-status: vis hvornår der senest blev hentet og gemt.
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5EA),
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  status.loaded
                      ? 'Klassisk hentet fra ${status.lastLoadSource} '
                          '${status.loadedAt != null ? _hhmmss(status.loadedAt!) : ''}'
                      : 'Henter regler fra database…',
                  style: const TextStyle(fontSize: 12),
                ),
                Builder(builder: (BuildContext _) {
                  final String vSource =
                      ref.watch(variantCardRulesLoadSourceProvider);
                  return Text(
                    '25 år-regler: ${vSource.isEmpty ? 'henter…' : vSource} '
                    '(seed = de indbyggede specialkort, firestore = dine gemte, prefs = '
                    'lokal kopi)',
                    style: const TextStyle(fontSize: 12),
                  );
                }),
                if (status.savedAt != null)
                  Text(
                    'Klassisk sidst gemt i database: ${_hhmmss(status.savedAt!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (status.lastLoadError.isNotEmpty)
                  Text(
                    'Læsefejl: ${status.lastLoadError}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.red),
                  ),
              ],
            ),
          ),
          if (variantSaveErr.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('25 år-regler: $variantSaveErr',
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            ),
          const _BoardMinTile(),
          const _AiLevelsTile(),
          const _VariantAdminHeader(),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Hvert kort har TO kolonner: venstre = klassisk, højre = '
              'Partners 25 år. De redigeres uafhængigt — en 25 år-kolonne '
              'uden egen regel FØLGER klassisk. Ændringer gemmes automatisk i '
              'Firebase; ser felterne ud som standarder selv om du har gemt '
              'før, så tryk på sky-pil-ned (øverst) for at hente fra databasen '
              'nu.',
            ),
          ),
          for (final Rank r in _order)
            _RankTile(
              key: ValueKey<Rank>(r),
              rank: r,
              label: _label(r),
            ),
        ],
      ),
    );
  }
}

/// Admin-editor for parametrene bag de tre AI-sværhedsgrader (config/ai). Selve
/// GRADEN vælger spilleren ved spilstart; her defineres HVAD hver grad gør.
class _AiLevelsTile extends ConsumerStatefulWidget {
  const _AiLevelsTile();

  @override
  ConsumerState<_AiLevelsTile> createState() => _AiLevelsTileState();
}

class _AiLevelsTileState extends ConsumerState<_AiLevelsTile> {
  // Lokal redigeringskopi mens man trækker i sliderne.
  List<AiParams>? _local;

  Future<void> _save(List<AiParams> levels) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setAiLevels(levels);
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Kunne ikke gemme: $e')));
    }
  }

  List<AiParams> _with(List<AiParams> levels, int i, AiParams p) {
    final List<AiParams> copy = List<AiParams>.from(levels);
    copy[i] = p;
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final List<AiParams> live =
        ref.watch(aiLevelsProvider).valueOrNull ?? kDefaultAiLevels;
    final List<AiParams> levels = _local ?? live;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.smart_toy, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI-sværhedsgrader',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _local = List<AiParams>.from(
                        kDefaultAiLevels));
                    _save(kDefaultAiLevels);
                  },
                  child: const Text('Nulstil'),
                ),
              ],
            ),
            const Text(
              'Spilleren vælger selv graden ved spilstart. Her justeres HVAD '
              'hver grad gør.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            for (int i = 0; i < levels.length; i++)
              _levelEditor(i, levels[i], levels),
          ],
        ),
      ),
    );
  }

  Widget _levelEditor(int i, AiParams p, List<AiParams> levels) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5F7),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              i < kAiLevelNames.length ? kAiLevelNames[i] : 'Grad $i',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            // Støj: 0 = altid bedste træk, højt = kluntet.
            _sliderRow(
              label: 'Tilfældighed (støj)',
              value: p.noise,
              min: 0,
              max: 20,
              display: p.noise.toStringAsFixed(0),
              onChanged: (double v) => setState(
                  () => _local = _with(levels, i, p.copyWith(noise: v))),
              onEnd: (double v) =>
                  _save(_with(levels, i, p.copyWith(noise: v))),
            ),
            // Sandsynlighed for et helt tilfældigt træk (%).
            _sliderRow(
              label: 'Tilfældigt træk',
              value: p.randomMoveChance,
              min: 0,
              max: 1,
              display: '${(p.randomMoveChance * 100).round()}%',
              onChanged: (double v) => setState(() => _local =
                  _with(levels, i, p.copyWith(randomMoveChance: v))),
              onEnd: (double v) => _save(
                  _with(levels, i, p.copyWith(randomMoveChance: v))),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Beholder eget ud-af-start-kort',
                  style: TextStyle(fontSize: 13)),
              value: p.protectExitCard,
              onChanged: (bool v) {
                final List<AiParams> next =
                    _with(levels, i, p.copyWith(protectExitCard: v));
                setState(() => _local = next);
                _save(next);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(
            width: 42,
            child: Text(display,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}

/// Admin-slider til minimums-brætstørrelse (config/ui.boardMinPx).
class _BoardMinTile extends ConsumerStatefulWidget {
  const _BoardMinTile();

  @override
  ConsumerState<_BoardMinTile> createState() => _BoardMinTileState();
}

class _BoardMinTileState extends ConsumerState<_BoardMinTile> {
  // Lokal værdi mens man trækker i slideren (før den gemmes).
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final double live =
        ref.watch(boardMinPxProvider).valueOrNull ?? kBoardMinDefault;
    final double value =
        (_dragging ?? live).clamp(kBoardMinLower, kBoardMinUpper);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.crop_square, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Minimum brætstørrelse',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text('${value.round()} px',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            Slider(
              min: kBoardMinLower,
              max: kBoardMinUpper,
              divisions: ((kBoardMinUpper - kBoardMinLower) / 5).round(),
              value: value,
              label: '${value.round()} px',
              onChanged: (double v) => setState(() => _dragging = v),
              onChangeEnd: (double v) async {
                setState(() => _dragging = null);
                try {
                  await setBoardMinPx(v);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Minimum brætstørrelse sat til ${v.round()} px')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Kunne ikke gemme: $e')),
                    );
                  }
                }
              },
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Brættet gøres aldrig mindre end dette. Højere værdi = større '
                'bræt, men mere scroll på lave/små skærme. Gælder alle enheder '
                'med det samme.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kort resumé af én kort-config — bruges i tile-subtitler for BEGGE
/// kolonner, så admin og spiller læser samme ord ("hop" matcher kort-chippen).
String _configSummary(CardRuleConfig c) {
  final List<String> parts = <String>[];
  if (c.exitStart) parts.add('ud');
  if (c.forwardSteps.isNotEmpty) parts.add('frem ${c.forwardSteps.join('/')}');
  if (c.backwardSteps != null) parts.add('tilbage ${c.backwardSteps}');
  if (c.splitTotal != null) parts.add('split ${c.splitTotal}');
  if (c.swap) parts.add('byt');
  if (c.jumpsBlockade) parts.add('hop');
  if (c.hasFwdThenBack) parts.add('${c.seqForward}frem+${c.seqBackward}tilb');
  if (c.hasMultiForward) parts.add('${c.multiSteps}frem×${c.multiPieces}brik');
  return parts.isEmpty ? 'ingen funktion' : parts.join(' · ');
}

/// Én rang, to uafhængige editorer SIDE OM SIDE: venstre = klassisk, højre =
/// Partners 25 år. Afviger de to, markeres tilen ("≠ afviger" — ikon+tekst,
/// ikke farve alene) og subtitlen viser begge resuméer, så listen kan scannes
/// under afskrivning af det fysiske sæt.
class _RankTile extends ConsumerWidget {
  const _RankTile({
    super.key,
    required this.rank,
    required this.label,
  });

  final Rank rank;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CardRules classic = ref.watch(cardRulesProvider);
    final String selId = ref.watch(selectedAdminVariantIdProvider);
    final VariantAdminConfig va = ref.watch(selectedVariantAdminProvider);
    final VariantConfig selVariant = selId == partners25.id
        ? partners25
        : variantFromRaw(
            selId, ref.watch(variantCardRulesProvider).toRawJson());
    final String selLabel = selVariant.shortLabel;
    final CardRuleConfig classicCfg = classic.forRank(rank);
    // De EFFEKTIVE variant-regler for denne rang — beregnet med SAMME resolver
    // som spil-oprettelsen (effectiveCardRules), så forhåndsvisningen aldrig
    // kan drive fra det spillerne faktisk får. For en custom er kode-seedet
    // null, så tomme overrides = klassisk (derfor viser en ny variant
    // "Følger klassisk" på alle 13 kort).
    final CardRuleConfig variantCfg =
        effectiveCardRules(selVariant, classic, stored: va.overrides)
            .forRank(rank);
    final bool diverges = !CardRules.sameConfig(classicCfg, variantCfg);
    final bool hasOwn = va.overrides.containsKey(rank);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(label)),
        title: Row(
          children: <Widget>[
            Text('Kort $label'),
            if (diverges)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '≠ afviger',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.deepOrange.shade700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(diverges
            ? 'Klassisk: ${_configSummary(classicCfg)}  ·  '
                '$selLabel: ${_configSummary(variantCfg)}'
            : _configSummary(classicCfg)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
          LayoutBuilder(builder: (BuildContext context, BoxConstraints cons) {
            final Widget classicCol = _ConfigEditor(
              title: 'Klassisk',
              config: classicCfg,
              onChanged: (CardRuleConfig cfg) =>
                  ref.read(cardRulesProvider.notifier).updateRank(rank, cfg),
            );
            final Widget p25Col = _ConfigEditor(
              title: selVariant.name,
              config: variantCfg,
              onChanged: (CardRuleConfig cfg) => ref
                  .read(variantCardRulesProvider.notifier)
                  .updateRank(selId, rank, cfg),
              trailing: hasOwn
                  ? Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      const Text('Egen regel',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'Følg klassisk igen (fjern egen regel)',
                        icon: const Icon(Icons.link, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(variantCardRulesProvider.notifier)
                            .clearRank(selId, rank),
                      ),
                    ])
                  : const Text('Følger klassisk',
                      style:
                          TextStyle(fontSize: 11, color: Colors.black54)),
            );
            // Smal skærm (afskrivning ved bordet = telefon/tablet): stak
            // kolonnerne med hver sin overskrift i stedet for at klemme dem.
            if (cons.maxWidth < 700) {
              return Column(children: <Widget>[
                classicCol,
                const Divider(height: 20),
                p25Col,
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: classicCol),
                const SizedBox(width: 20),
                Expanded(child: p25Col),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Editor for ÉN kort-config (én kolonne). Committer via
/// [CardRuleConfig.copyWith] på den indkomne config, så et felt der ikke er
/// repræsenteret i UI'et STRUKTURELT ikke kan gå tabt ved et gem.
class _ConfigEditor extends StatefulWidget {
  const _ConfigEditor({
    required this.title,
    required this.config,
    required this.onChanged,
    this.trailing,
  });

  final String title;
  final CardRuleConfig config;
  final ValueChanged<CardRuleConfig> onChanged;
  final Widget? trailing;

  @override
  State<_ConfigEditor> createState() => _ConfigEditorState();
}

class _ConfigEditorState extends State<_ConfigEditor> {
  late bool _exitStart;
  late bool _forwardOn;
  late bool _backwardOn;
  late bool _splitOn;
  late bool _swap;
  late bool _jump;
  late bool _seqOn;
  late bool _multiOn;

  late TextEditingController _forwardCtrl;
  late TextEditingController _backwardCtrl;
  late TextEditingController _splitCtrl;
  late TextEditingController _seqFwdCtrl;
  late TextEditingController _seqBackCtrl;
  late TextEditingController _multiPiecesCtrl;
  late TextEditingController _multiStepsCtrl;

  /// Senest committede config — så vores EGEN værdi, der kommer retur gennem
  /// provideren, ikke re-synker felterne. Uden denne vagt låser frem-feltet
  /// sig selv midt i indtastningen: tøm "5" for at skrive "8" → tom = [] →
  /// commit → resync → _forwardOn=false → feltet disables og mister fokus.
  /// Det ville ramme præcis afskrivnings-workflowet (skriv sættet af kort for
  /// kort). Eksterne ændringer (load/"Hent nu"/nulstil/følg-klassisk) synker
  /// stadig.
  CardRuleConfig? _lastCommitted;

  @override
  void initState() {
    super.initState();
    _forwardCtrl = TextEditingController();
    _backwardCtrl = TextEditingController();
    _splitCtrl = TextEditingController();
    _seqFwdCtrl = TextEditingController();
    _seqBackCtrl = TextEditingController();
    _multiPiecesCtrl = TextEditingController();
    _multiStepsCtrl = TextEditingController();
    _syncFromConfig(widget.config);
  }

  @override
  void didUpdateWidget(_ConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Vores egen netop-committede værdi kom retur → rør ikke felter/toggles.
    if (_lastCommitted != null &&
        CardRules.sameConfig(_lastCommitted!, widget.config)) {
      return;
    }
    // Når configen ændres udefra (Firestore-load, "Hent nu", nulstil, følg-
    // klassisk) skal toggles/felter opdateres. sameConfig dækker ALLE felter
    // (inkl. jumpsBlockade), så et load der kun flipper hop også synker.
    if (!CardRules.sameConfig(oldWidget.config, widget.config)) {
      _syncFromConfig(widget.config);
    }
  }

  void _syncFromConfig(CardRuleConfig c) {
    _exitStart = c.exitStart;
    _forwardOn = c.forwardSteps.isNotEmpty;
    _backwardOn = c.backwardSteps != null;
    _splitOn = c.splitTotal != null;
    _swap = c.swap;
    _jump = c.jumpsBlockade;
    _seqOn = c.hasFwdThenBack;
    _multiOn = c.hasMultiForward;
    _forwardCtrl.text = c.forwardSteps.join(', ');
    _backwardCtrl.text = (c.backwardSteps ?? 4).toString();
    _splitCtrl.text = (c.splitTotal ?? 7).toString();
    _seqFwdCtrl.text = (c.seqForward ?? 2).toString();
    _seqBackCtrl.text = (c.seqBackward ?? 5).toString();
    _multiPiecesCtrl.text = (c.multiPieces ?? 2).toString();
    _multiStepsCtrl.text = (c.multiSteps ?? 1).toString();
  }

  @override
  void dispose() {
    _forwardCtrl.dispose();
    _backwardCtrl.dispose();
    _splitCtrl.dispose();
    _seqFwdCtrl.dispose();
    _seqBackCtrl.dispose();
    _multiPiecesCtrl.dispose();
    _multiStepsCtrl.dispose();
    super.dispose();
  }

  List<int> _parseForward() {
    return _forwardCtrl.text
        .split(RegExp(r'[,\s]+'))
        .map((String s) => int.tryParse(s.trim()))
        .whereType<int>()
        .where((int n) => n != 0)
        .toList();
  }

  void _commit() {
    // copyWith på den INDKOMNE config: felter uden UI-repræsentation bevares.
    final CardRuleConfig cfg = widget.config.copyWith(
      exitStart: _exitStart,
      forwardSteps: _forwardOn ? _parseForward() : <int>[],
      backwardSteps:
          _backwardOn ? (int.tryParse(_backwardCtrl.text.trim()) ?? 4) : null,
      clearBackward: !_backwardOn,
      splitTotal:
          _splitOn ? (int.tryParse(_splitCtrl.text.trim()) ?? 7) : null,
      clearSplit: !_splitOn,
      swap: _swap,
      jumpsBlockade: _jump,
      // Klampet: sekvens kræver mindst 1 frem og 1 tilbage; multi kræver
      // mindst 2 brikker og 1 felt (ellers er kortet virkningsløst/dublet).
      seqForward:
          _seqOn ? (int.tryParse(_seqFwdCtrl.text.trim()) ?? 2).clamp(1, 20) : null,
      seqBackward: _seqOn
          ? (int.tryParse(_seqBackCtrl.text.trim()) ?? 5).clamp(1, 20)
          : null,
      clearSeq: !_seqOn,
      multiPieces: _multiOn
          ? (int.tryParse(_multiPiecesCtrl.text.trim()) ?? 2).clamp(2, 4)
          : null,
      multiSteps: _multiOn
          ? (int.tryParse(_multiStepsCtrl.text.trim()) ?? 1).clamp(1, 20)
          : null,
      clearMulti: !_multiOn,
    );
    _lastCommitted = cfg;
    widget.onChanged(cfg);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Rykke en brik ud'),
          value: _exitStart,
          onChanged: (bool v) {
            setState(() => _exitStart = v);
            _commit();
          },
        ),
        _toggleWithField(
          title: 'Rykke frem',
          on: _forwardOn,
          onChanged: (bool v) {
            setState(() => _forwardOn = v);
            _commit();
          },
          controller: _forwardCtrl,
          hint: 'felter, fx 1, 11',
          digitsOnly: false,
        ),
        _toggleWithField(
          title: 'Rykke tilbage',
          on: _backwardOn,
          onChanged: (bool v) {
            setState(() => _backwardOn = v);
            _commit();
          },
          controller: _backwardCtrl,
          hint: 'antal felter',
          digitsOnly: true,
        ),
        _toggleWithField(
          title: 'Kan deles (7-split)',
          on: _splitOn,
          onChanged: (bool v) {
            setState(() => _splitOn = v);
            _commit();
          },
          controller: _splitCtrl,
          hint: 'total felter',
          digitsOnly: true,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Byt to brikker'),
          value: _swap,
          onChanged: (bool v) {
            setState(() => _swap = v);
            _commit();
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Hoppe over blokade (5↷)'),
          subtitle: const Text(
            'Må passere et blokeret startfelt — gælder kun fremad-skridt',
            style: TextStyle(fontSize: 11),
          ),
          value: _jump,
          onChanged: (bool v) {
            setState(() => _jump = v);
            _commit();
          },
        ),
        _togglePair(
          title: 'Frem + tilbage (fx +2−5)',
          subtitle: 'Samme brik: frem med rigtig landing, så tilbage',
          on: _seqOn,
          onChanged: (bool v) {
            setState(() => _seqOn = v);
            _commit();
          },
          firstCtrl: _seqFwdCtrl,
          firstHint: 'frem',
          secondCtrl: _seqBackCtrl,
          secondHint: 'tilbage',
        ),
        _togglePair(
          title: 'Flere brikker frem (fx 1×1)',
          subtitle: 'Præcis N brikker rykker hver S felter frem',
          on: _multiOn,
          onChanged: (bool v) {
            setState(() => _multiOn = v);
            _commit();
          },
          firstCtrl: _multiPiecesCtrl,
          firstHint: 'brikker',
          secondCtrl: _multiStepsCtrl,
          secondHint: 'felter',
        ),
      ],
    );
  }

  /// Toggle med TO talfelter (fx frem/tilbage eller brikker/felter).
  Widget _togglePair({
    required String title,
    required String subtitle,
    required bool on,
    required ValueChanged<bool> onChanged,
    required TextEditingController firstCtrl,
    required String firstHint,
    required TextEditingController secondCtrl,
    required String secondHint,
  }) {
    Widget numField(TextEditingController ctrl, String hint) => SizedBox(
          width: 64,
          child: TextField(
            controller: ctrl,
            enabled: on,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly
            ],
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              helperText: hint,
              helperStyle: const TextStyle(fontSize: 9),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _commit(),
          ),
        );
    return Row(
      children: <Widget>[
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
            value: on,
            onChanged: onChanged,
          ),
        ),
        numField(firstCtrl, firstHint),
        const SizedBox(width: 6),
        numField(secondCtrl, secondHint),
      ],
    );
  }

  Widget _toggleWithField({
    required String title,
    required bool on,
    required ValueChanged<bool> onChanged,
    required TextEditingController controller,
    required String hint,
    required bool digitsOnly,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            value: on,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: controller,
            enabled: on,
            keyboardType: digitsOnly
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: digitsOnly
                ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
                : <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,\s]')),
                  ],
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _commit(),
          ),
        ),
      ],
    );
  }
}

/// Header-sektion for variant-kolonnen: VÆLGEREN (25 år + egne varianter),
/// "Ny variant"-grebet, admins navn/mærke/beskrivelse/tema, "kopiér
/// klassisk"-grebet (fuldt uafhængigt snapshot i ét tryk), afvigelses-tælleren
/// og sanity-advarsler for BEGGE regelsæt. Advarsler, aldrig spærringer —
/// admin er autoritet.
class _VariantAdminHeader extends ConsumerStatefulWidget {
  const _VariantAdminHeader();

  @override
  ConsumerState<_VariantAdminHeader> createState() =>
      _VariantAdminHeaderState();
}

class _VariantAdminHeaderState extends ConsumerState<_VariantAdminHeader> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _labelCtrl;

  /// Hvilken variant felterne er synket for — et variantskifte SKAL resynke,
  /// ellers taster admin videre i den forrige variants tekster.
  String _syncedFor = '';
  String _syncedName = '';
  String _syncedDesc = '';
  String _syncedLabel = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _labelCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _syncMeta(String id, VariantAdminConfig va) {
    // Synk kun når den EKSTERNE værdi ændrer sig (load/nulstil/variantskifte),
    // så vi ikke overskriver mens admin taster.
    final bool switched = id != _syncedFor;
    _syncedFor = id;
    final String n = va.name ?? '';
    final String d = va.description ?? '';
    final String l = va.label ?? '';
    if (switched || n != _syncedName) {
      _syncedName = n;
      _nameCtrl.text = n;
    }
    if (switched || d != _syncedDesc) {
      _syncedDesc = d;
      _descCtrl.text = d;
    }
    if (switched || l != _syncedLabel) {
      _syncedLabel = l;
      _labelCtrl.text = l;
    }
  }

  void _commitMeta() {
    // UÆNDRET = ingen skrivning. Ellers ville et klik ind og ud af feltet
    // gøre kode-seedet til "admins gemte valg" (stored=true) og fryse det i
    // databasen — hvorefter en senere kode-ændring af seedet ikke slår
    // igennem.
    if (_nameCtrl.text == _syncedName &&
        _descCtrl.text == _syncedDesc &&
        _labelCtrl.text == _syncedLabel) {
      return;
    }
    _syncedName = _nameCtrl.text;
    _syncedDesc = _descCtrl.text;
    _syncedLabel = _labelCtrl.text;
    ref.read(variantCardRulesProvider.notifier).updateMeta(
          _syncedFor,
          name: _nameCtrl.text,
          description: _descCtrl.text,
          label: _labelCtrl.text,
        );
  }

  Future<void> _newVariantDialog() async {
    final nameCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String themeId = kVariantThemes.first.id;
    final String? error = await showDialog<String?>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDlg) => AlertDialog(
          title: const Text('Ny variant'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'En egen variant er altid klassisk-formet (4 spillere, '
                  'samme bræt) og starter med klassiske kortregler — '
                  'tilpas kortene bagefter i kolonnen. Navnet giver '
                  'variantens faste id, som aldrig kan ændres.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  maxLength: kMaxCustomNameLength,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Navn',
                    hintText: 'fx Familie-special',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: labelCtrl,
                  maxLength: kMaxCustomLabelLength,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Kort mærke (badgen på bordet)',
                    hintText: 'fx Familie',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Beskrivelse (valgfri)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Farvetema',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final VariantTheme t in kVariantThemes)
                      ChoiceChip(
                        avatar: CircleAvatar(
                            backgroundColor: t.badgeColor, radius: 8),
                        label: Text(t.name),
                        selected: themeId == t.id,
                        onSelected: (_) => setDlg(() => themeId = t.id),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Faste, kontrast-efterprøvede temaer — grøn og marineblå '
                  'er reserveret til Klassisk og 25 år.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annullér')),
            FilledButton(
              onPressed: () async {
                final String? err = await ref
                    .read(variantCardRulesProvider.notifier)
                    .createVariant(
                      name: nameCtrl.text,
                      label: labelCtrl.text,
                      theme: themeId,
                      description: descCtrl.text,
                    );
                if (!ctx.mounted) return;
                if (err != null) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(err)));
                  return; // dialogen bliver åben, admin kan rette navnet
                }
                Navigator.pop(ctx, slugForVariantName(nameCtrl.text));
              },
              child: const Text('Opret'),
            ),
          ],
        ),
      ),
    );
    if (error != null && mounted) {
      // Ny variant valgt med det samme — det er dén admin vil redigere nu.
      ref.read(selectedAdminVariantIdProvider.notifier).state = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final CardRules classic = ref.watch(cardRulesProvider);
    final String selId = ref.watch(selectedAdminVariantIdProvider);
    final VariantsAdminState all = ref.watch(variantCardRulesProvider);
    final VariantAdminConfig va = all.configFor(selId);
    _syncMeta(selId, va);
    final Map<String, dynamic> raw = all.toRawJson();
    final VariantConfig selVariant =
        selId == partners25.id ? partners25 : variantFromRaw(selId, raw);
    final String selLabel = selVariant.shortLabel;
    // Samme resolver som spil-oprettelsen — én kilde til "hvad får spillerne".
    final CardRules effective =
        effectiveCardRules(selVariant, classic, stored: va.overrides);
    final int divergent = Rank.values
        .where((Rank r) => !CardRules.sameRank(classic, effective, r))
        .length;
    final List<String> classicWarnings = deckSanityWarnings(classic);
    final List<String> variantWarnings = deckSanityWarnings(effective);
    // Vælgeren: 25 år + ALLE customs (også arkiverede — admin skal kunne
    // gendanne dem; de markeres i teksten).
    final List<String> selectableIds = <String>[
      partners25.id,
      ...customVariantIdsFrom(raw, includeArchived: true),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.style, size: 18),
                const SizedBox(width: 8),
                // Variant-vælgeren: hvilken variant redigerer højre kolonne?
                Expanded(
                  child: DropdownButton<String>(
                    value: selectableIds.contains(selId)
                        ? selId
                        : partners25.id,
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final String id in selectableIds)
                        DropdownMenuItem<String>(
                          value: id,
                          child: Text(
                            id == partners25.id
                                ? variantNameFrom(
                                    partners25, all.configFor(id).name)
                                : '${variantFromRaw(id, raw).name}'
                                    '${all.configFor(id).archived ? ' (arkiveret)' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (String? id) {
                      if (id != null) {
                        _commitMeta(); // gem den forrige variants felter først
                        ref
                            .read(selectedAdminVariantIdProvider.notifier)
                            .state = id;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _newVariantDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ny variant'),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                const Spacer(),
                Text(
                  '$divergent af ${Rank.values.length} kort afviger fra '
                  'klassisk',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: divergent > 0
                        ? Colors.deepOrange.shade700
                        : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Navn/beskrivelse: vises i variant-vælgeren og online-lobbyen.
            // Tomt felt = variantens indbyggede tekst (kun 25 år har en).
            TextField(
              controller: _nameCtrl,
              maxLength: kMaxCustomNameLength,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                labelText: 'Navn i variant-vælgeren',
                hintText: selId == partners25.id ? 'Partners 25 år' : null,
                helperText: selId == partners25.id
                    ? 'Tomt = indbygget navn.'
                    : 'Variantens id ($selId) er fast og følger IKKE med '
                        'ved omdøbning.',
                border: const OutlineInputBorder(),
              ),
              onEditingComplete: _commitMeta,
              onTapOutside: (_) => _commitMeta(),
            ),
            const SizedBox(height: 8),
            if (va.custom) ...<Widget>[
              TextField(
                controller: _labelCtrl,
                maxLength: kMaxCustomLabelLength,
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  labelText: 'Kort mærke (badgen på bordet)',
                  hintText: 'Tomt = navnet',
                  border: OutlineInputBorder(),
                ),
                onEditingComplete: _commitMeta,
                onTapOutside: (_) => _commitMeta(),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Beskrivelse i variant-vælgeren',
                border: OutlineInputBorder(),
              ),
              onEditingComplete: _commitMeta,
              onTapOutside: (_) => _commitMeta(),
            ),
            if (va.custom) ...<Widget>[
              const SizedBox(height: 8),
              // Tema-valg: kurateret, aldrig frie farver.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final VariantTheme t in kVariantThemes)
                    ChoiceChip(
                      avatar: CircleAvatar(
                          backgroundColor: t.badgeColor, radius: 8),
                      label: Text(t.name),
                      selected: (va.theme ?? kVariantThemes.last.id) == t.id,
                      onSelected: (_) => ref
                          .read(variantCardRulesProvider.notifier)
                          .updateMeta(selId, theme: t.id),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Regelændringer gælder kun NYE spil. Har varianten allerede '
                'spillede spil, så overvej en ny variant i stedet — ellers '
                'blander statistikken to regelsæt under samme navn.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: Text(
                      'Kopiér klassisk til $selLabel (alle 13 kort)'),
                  onPressed: () async {
                    final bool? ok = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext ctx) => AlertDialog(
                        title: Text('Kopiér klassisk til $selLabel?'),
                        content: Text(
                            'Alle 13 kort får en EGEN regel (den nuværende '
                            'effektive $selLabel-regel). Derefter er '
                            '$selLabel et fuldt uafhængigt sæt: senere '
                            'klassisk-ændringer følger IKKE med.'),
                        actions: <Widget>[
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annullér')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Kopiér')),
                        ],
                      ),
                    );
                    if (ok == true && mounted) {
                      ref
                          .read(variantCardRulesProvider.notifier)
                          .materializeAll(selId, effective);
                    }
                  },
                ),
                if (va.custom)
                  OutlinedButton.icon(
                    icon: Icon(
                        va.archived ? Icons.unarchive : Icons.archive,
                        size: 18),
                    label: Text(va.archived
                        ? 'Gendan variant'
                        : 'Arkivér variant'),
                    onPressed: () async {
                      if (!va.archived) {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: Text('Arkivér $selLabel?'),
                            content: const Text(
                                'Varianten forsvinder fra vælgerne og kan '
                                'ikke startes i nye spil. Historiske spil '
                                'og statistik beholder navn og farve, og '
                                'igangværende spil spilles færdige. Kan '
                                'gendannes her når som helst — varianter '
                                'slettes aldrig helt (id\'et står i gamle '
                                'spil).'),
                            actions: <Widget>[
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Annullér')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Arkivér')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                      }
                      if (mounted) {
                        await ref
                            .read(variantCardRulesProvider.notifier)
                            .setArchived(selId, !va.archived);
                      }
                    },
                  ),
                if (va.custom && va.overrides.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Nulstil kort (følg klassisk)'),
                    onPressed: () async {
                      final bool? ok = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext ctx) => AlertDialog(
                          title: Text('Nulstil $selLabel-kortene?'),
                          content: const Text(
                              'Alle egne kortregler fjernes, og varianten '
                              'følger klassisk igen. Navn, mærke og tema '
                              'bevares.'),
                          actions: <Widget>[
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annullér')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Nulstil kort')),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await ref
                            .read(variantCardRulesProvider.notifier)
                            .resetRules(selId);
                      }
                    },
                  ),
              ],
            ),
            for (final String w in classicWarnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ Klassisk: $w',
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepOrange.shade800)),
              ),
            for (final String w in variantWarnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ $selLabel: $w',
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepOrange.shade800)),
              ),
          ],
        ),
      ),
    );
  }
}
