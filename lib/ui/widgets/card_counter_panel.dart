import 'package:flutter/material.dart';

import '../../game/deck.dart';
import '../../models/game_state.dart';

/// Lille udviklings-panel der viser hvor mange af hvert kort der er givet i den
/// aktuelle kortgiver-cyklus (3 runder før kortene blandes om).
///
/// Beregning: antal af hver "kort-type" (rang eller UD-kort) i en frisk bunke
/// for spillets variant ([Deck.countsByKind]: klassisk 4 af hver = 56, Duo 3
/// af 10 rangs = 30). Antal givet = det antal − antal tilbage i [state.deck]. Reset sker automatisk når
/// dækket genfyldes ved en ny kortgiver-cyklus.
class CardCounterPanel extends StatelessWidget {
  const CardCounterPanel({super.key, required this.state});

  final GameState state;

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
    final Map<String, int> full = Deck.countsByKind(state.variant);
    final cards = <Map<String, dynamic>>[
      for (final MapEntry<String, int> e in full.entries)
        <String, dynamic>{
          'label': e.key == 'UD' ? 'UD ♥' : e.key,
          'dealt': e.value - (remaining[e.key] ?? 0),
          'of': e.value,
          'isExit': e.key == 'UD',
        },
    ];
    final int deckSize = full.values.fold<int>(0, (int a, int b) => a + b);
    final totalDealt = cards.fold<int>(
        0, (acc, c) => acc + (c['dealt'] as int));
    final totalRemaining = deckSize - totalDealt;

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
              Text('$totalDealt / $deckSize',
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
        : dealt >= (c['of'] as int)
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
                color: dealt >= (c['of'] as int) ? Colors.red : Colors.black54),
          ),
        ],
      ),
    );
  }
}
