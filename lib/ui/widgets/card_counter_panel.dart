import 'package:flutter/material.dart';

import '../../models/game_state.dart';
import '../../models/playing_card.dart';

/// Lille udviklings-panel der viser hvor mange af hvert kort der er givet i den
/// aktuelle kortgiver-cyklus (3 runder før kortene blandes om).
///
/// Beregning: hver "kort-type" (rank eller UD-kort) har 4 stk. i et frisk dæk.
/// Antal givet = 4 − antal tilbage i [state.deck]. Reset sker automatisk når
/// dækket genfyldes ved en ny kortgiver-cyklus.
class CardCounterPanel extends StatelessWidget {
  const CardCounterPanel({super.key, required this.state});

  final GameState state;

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

  String _label(Rank r) => PlayingCard(r, Suit.spades).rankLabel;

  Map<String, int> _remainingByKind(GameState s) {
    final m = <String, int>{};
    for (final c in s.deck) {
      final key = c.isExit ? 'UD' : c.rankLabel;
      m[key] = (m[key] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingByKind(state);
    final cards = <Map<String, dynamic>>[
      for (final r in _order)
        <String, dynamic>{
          'label': _label(r),
          'dealt': 4 - (remaining[_label(r)] ?? 0),
          'isExit': false,
        },
      <String, dynamic>{
        'label': 'UD ♥',
        'dealt': 4 - (remaining['UD'] ?? 0),
        'isExit': true,
      },
    ];
    final totalDealt = cards.fold<int>(
        0, (acc, c) => acc + (c['dealt'] as int));
    final totalRemaining = 56 - totalDealt;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('Givet i cyklus',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              Text('$totalDealt / 56',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final c in cards) _chip(c),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dæk: $totalRemaining tilbage · runde ${state.starterStreak + 1}/3',
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _chip(Map<String, dynamic> c) {
    final dealt = c['dealt'] as int;
    final bool exit = c['isExit'] as bool;
    final Color bg = dealt == 0
        ? Colors.grey.shade100
        : dealt >= 4
            ? Colors.red.shade100
            : Colors.amber.shade50;
    final Color borderColor = exit ? Colors.red : Colors.black26;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            c['label'] as String,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: exit ? Colors.red : Colors.black87),
          ),
          const SizedBox(width: 3),
          Text(
            '$dealt',
            style: TextStyle(
                fontSize: 11,
                color: dealt >= 4 ? Colors.red : Colors.black54),
          ),
        ],
      ),
    );
  }
}
