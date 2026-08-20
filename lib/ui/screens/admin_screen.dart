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
                // Intet gemt for 25 år (stored=false) = seedet gælder og der
                // skrives bevidst ikke — sig det, frem for at påstå "gemt".
                final bool vStored =
                    ref.read(variantCardRulesProvider).stored;
                final String msg = err.isEmpty && vErr.isEmpty
                    ? (vStored
                        ? 'Gemt (klassisk + 25 år)'
                        : 'Gemt (klassisk) · 25 år følger forsmagen (intet '
                            'at gemme)')
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
                      'mister dine tilpasninger og går tilbage til forsmagen '
                      '(kun Hopsakortet på 5-kortet). Dette kan ikke '
                      'fortrydes.'),
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
              await variantCtrl.resetToSeed();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Nulstillet: klassisk = standard, 25 år = forsmag')));
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
                    '(seed = forsmagen, firestore = dine gemte, prefs = '
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
    final VariantAdminConfig va = ref.watch(variantCardRulesProvider);
    final CardRuleConfig classicCfg = classic.forRank(rank);
    // De EFFEKTIVE 25 år-regler for denne rang — beregnet med SAMME resolver
    // som spil-oprettelsen (effectiveCardRules), så forhåndsvisningen aldrig
    // kan drive fra det spillerne faktisk får.
    final CardRuleConfig p25Cfg =
        effectiveCardRules(partners25, classic, stored: va.overrides)
            .forRank(rank);
    final bool diverges = !CardRules.sameConfig(classicCfg, p25Cfg);
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
                '25 år: ${_configSummary(p25Cfg)}'
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
              title: 'Partners 25 år',
              config: p25Cfg,
              onChanged: (CardRuleConfig cfg) => ref
                  .read(variantCardRulesProvider.notifier)
                  .updateRank(rank, cfg),
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
                            .clearRank(rank),
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

  late TextEditingController _forwardCtrl;
  late TextEditingController _backwardCtrl;
  late TextEditingController _splitCtrl;

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
    _forwardCtrl.text = c.forwardSteps.join(', ');
    _backwardCtrl.text = (c.backwardSteps ?? 4).toString();
    _splitCtrl.text = (c.splitTotal ?? 7).toString();
  }

  @override
  void dispose() {
    _forwardCtrl.dispose();
    _backwardCtrl.dispose();
    _splitCtrl.dispose();
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

/// Header-sektion for 25 år-kolonnen: admins eget navn/beskrivelse (så
/// "(forsmag)" kan afløses når det fysiske sæt er afskrevet), "kopiér
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
  String _syncedName = '';
  String _syncedDesc = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _syncMeta(VariantAdminConfig va) {
    // Synk kun når den EKSTERNE værdi ændrer sig (load/nulstil), så vi ikke
    // overskriver mens admin taster.
    final String n = va.name ?? '';
    final String d = va.description ?? '';
    if (n != _syncedName) {
      _syncedName = n;
      _nameCtrl.text = n;
    }
    if (d != _syncedDesc) {
      _syncedDesc = d;
      _descCtrl.text = d;
    }
  }

  void _commitMeta() {
    // UÆNDRET = ingen skrivning. Ellers ville et klik ind og ud af feltet
    // gøre kode-seedet til "admins gemte valg" (stored=true) og fryse det i
    // databasen — hvorefter en senere kode-ændring af forsmaget ikke slår
    // igennem.
    if (_nameCtrl.text == _syncedName && _descCtrl.text == _syncedDesc) return;
    _syncedName = _nameCtrl.text;
    _syncedDesc = _descCtrl.text;
    ref.read(variantCardRulesProvider.notifier).updateMeta(
          name: _nameCtrl.text,
          description: _descCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final CardRules classic = ref.watch(cardRulesProvider);
    final VariantAdminConfig va = ref.watch(variantCardRulesProvider);
    _syncMeta(va);
    // Samme resolver som spil-oprettelsen — én kilde til "hvad får spillerne".
    final CardRules p25Effective =
        effectiveCardRules(partners25, classic, stored: va.overrides);
    final int divergent = Rank.values
        .where((Rank r) => !CardRules.sameRank(classic, p25Effective, r))
        .length;
    final List<String> classicWarnings = deckSanityWarnings(classic);
    final List<String> p25Warnings = deckSanityWarnings(p25Effective);

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
                const Text('Partners 25 år',
                    style: TextStyle(fontWeight: FontWeight.w700)),
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
            // Tomt felt = variantens indbyggede tekst ("(forsmag)"-forbeholdet).
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Navn i variant-vælgeren',
                hintText: 'Partners 25 år (forsmag)',
                helperText:
                    'Tomt = indbygget navn. Har du afskrevet det fysiske sæt, '
                    'så skriv fx "Partners 25 år".',
                border: OutlineInputBorder(),
              ),
              onEditingComplete: _commitMeta,
              onTapOutside: (_) => _commitMeta(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Beskrivelse i variant-vælgeren',
                hintText:
                    'Tilnærmet jubilæumsudgave … (indbygget tekst når tom)',
                border: OutlineInputBorder(),
              ),
              onEditingComplete: _commitMeta,
              onTapOutside: (_) => _commitMeta(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Kopiér klassisk til 25 år (alle 13 kort)'),
              onPressed: () async {
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext ctx) => AlertDialog(
                    title: const Text('Kopiér klassisk til 25 år?'),
                    content: const Text(
                        'Alle 13 kort får en EGEN regel (den nuværende '
                        'effektive 25 år-regel). Derefter er 25 år et fuldt '
                        'uafhængigt sæt: senere klassisk-ændringer følger '
                        'IKKE med. Brug dette når du afskriver det fysiske '
                        'sæt kort for kort.'),
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
                      .materializeAll(p25Effective);
                }
              },
            ),
            for (final String w in classicWarnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ Klassisk: $w',
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepOrange.shade800)),
              ),
            for (final String w in p25Warnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ 25 år: $w',
                    style: TextStyle(
                        fontSize: 12, color: Colors.deepOrange.shade800)),
              ),
          ],
        ),
      ),
    );
  }
}
