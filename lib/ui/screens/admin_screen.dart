import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';
import '../../state/card_rules_controller.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CardRules rules = ref.watch(cardRulesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Kortfunktioner'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () {
              ref.read(cardRulesProvider.notifier).resetDefaults();
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
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Marker hvilke funktioner hvert kort skal have. Ændringer gemmes '
              'automatisk og bruges næste gang du starter et spil.',
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
    final CardRuleConfig c = widget.config;
    _exitStart = c.exitStart;
    _forwardOn = c.forwardSteps.isNotEmpty;
    _backwardOn = c.backwardSteps != null;
    _splitOn = c.splitTotal != null;
    _swap = c.swap;
    _forwardCtrl =
        TextEditingController(text: c.forwardSteps.join(', '));
    _backwardCtrl =
        TextEditingController(text: (c.backwardSteps ?? 4).toString());
    _splitCtrl =
        TextEditingController(text: (c.splitTotal ?? 7).toString());
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
