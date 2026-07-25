import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';
import '../../game/ai/ai_player.dart';
import '../../online/online_service.dart';
import '../../state/card_rules_controller.dart';
import '../../state/display_config.dart';

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
    final CardRules rules = ref.watch(cardRulesProvider);
    final ctrl = ref.read(cardRulesProvider.notifier);
    final String saveErr = ref.watch(cardRulesSaveErrorProvider);
    final CardRulesStatus status = ref.watch(cardRulesStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Kortfunktioner'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Hent fra database NU',
            icon: const Icon(Icons.cloud_download, color: Colors.white),
            onPressed: () async {
              await ctrl.refresh();
              if (context.mounted) {
                final s = ref.read(cardRulesStatusProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(s.lastLoadError.isEmpty
                          ? 'Hentet fra ${s.lastLoadSource}'
                          : 'Læsefejl: ${s.lastLoadError}')),
                );
              }
            },
          ),
          TextButton.icon(
            onPressed: () async {
              await ctrl.retrySave();
              if (context.mounted) {
                final err = ref.read(cardRulesSaveErrorProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(err.isEmpty ? 'Gemt' : 'Fejl: $err')),
                );
              }
            },
            icon: const Icon(Icons.cloud_upload, color: Colors.white),
            label: const Text('Gem nu', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () {
              ctrl.resetDefaults();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nulstillet til standardregler')),
              );
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
                      ? 'Hentet fra ${status.lastLoadSource} '
                          '${status.loadedAt != null ? _hhmmss(status.loadedAt!) : ''}'
                      : 'Henter regler fra database…',
                  style: const TextStyle(fontSize: 12),
                ),
                if (status.savedAt != null)
                  Text(
                    'Sidst gemt i database: ${_hhmmss(status.savedAt!)}',
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
          const _BoardMinTile(),
          const _AiLevelsTile(),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Marker hvilke funktioner hvert kort skal have. Ændringer gemmes '
              'automatisk i Firebase. Hvis felterne ser ud som standarder selv '
              'om du har gemt før: tryk på sky-pil-ned (øverst) for at hente '
              'fra databasen nu.',
            ),
          ),
          for (final Rank r in _order)
            _RankTile(
              key: ValueKey<Rank>(r),
              rank: r,
              label: _label(r),
              config: rules.forRank(r),
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

class _RankTile extends ConsumerStatefulWidget {
  const _RankTile({
    super.key,
    required this.rank,
    required this.label,
    required this.config,
  });

  final Rank rank;
  final String label;
  final CardRuleConfig config;

  @override
  ConsumerState<_RankTile> createState() => _RankTileState();
}

class _RankTileState extends ConsumerState<_RankTile> {
  late bool _exitStart;
  late bool _forwardOn;
  late bool _backwardOn;
  late bool _splitOn;
  late bool _swap;

  late TextEditingController _forwardCtrl;
  late TextEditingController _backwardCtrl;
  late TextEditingController _splitCtrl;

  @override
  void initState() {
    super.initState();
    _forwardCtrl = TextEditingController();
    _backwardCtrl = TextEditingController();
    _splitCtrl = TextEditingController();
    _syncFromConfig(widget.config);
  }

  @override
  void didUpdateWidget(_RankTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Når konfigen ændres udefra (fx når Firestore-load fuldfører efter
    // tile'en er bygget, eller efter "Hent fra database NU"-knappen) skal
    // de lokale toggles og felter opdateres.
    if (!_sameConfig(oldWidget.config, widget.config)) {
      _syncFromConfig(widget.config);
    }
  }

  bool _sameConfig(CardRuleConfig a, CardRuleConfig b) {
    if (a.exitStart != b.exitStart) return false;
    if (a.swap != b.swap) return false;
    if (a.backwardSteps != b.backwardSteps) return false;
    if (a.splitTotal != b.splitTotal) return false;
    if (a.forwardSteps.length != b.forwardSteps.length) return false;
    for (int i = 0; i < a.forwardSteps.length; i++) {
      if (a.forwardSteps[i] != b.forwardSteps[i]) return false;
    }
    return true;
  }

  void _syncFromConfig(CardRuleConfig c) {
    _exitStart = c.exitStart;
    _forwardOn = c.forwardSteps.isNotEmpty;
    _backwardOn = c.backwardSteps != null;
    _splitOn = c.splitTotal != null;
    _swap = c.swap;
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
    final List<int> forward = _forwardOn ? _parseForward() : <int>[];
    final int? backward =
        _backwardOn ? (int.tryParse(_backwardCtrl.text.trim()) ?? 4) : null;
    final int? split =
        _splitOn ? (int.tryParse(_splitCtrl.text.trim()) ?? 7) : null;
    final cfg = CardRuleConfig(
      exitStart: _exitStart,
      forwardSteps: forward,
      backwardSteps: backward,
      splitTotal: split,
      swap: _swap,
    );
    ref.read(cardRulesProvider.notifier).updateRank(widget.rank, cfg);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(child: Text(widget.label)),
        title: Text('Kort ${widget.label}'),
        subtitle: Text(_summary()),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: <Widget>[
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
        ],
      ),
    );
  }

  String _summary() {
    final List<String> parts = <String>[];
    if (_exitStart) parts.add('ud');
    if (_forwardOn && _parseForward().isNotEmpty) {
      parts.add('frem ${_parseForward().join('/')}');
    }
    if (_backwardOn) parts.add('tilbage ${_backwardCtrl.text.trim()}');
    if (_splitOn) parts.add('split ${_splitCtrl.text.trim()}');
    if (_swap) parts.add('byt');
    return parts.isEmpty ? 'ingen funktion' : parts.join(' · ');
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
