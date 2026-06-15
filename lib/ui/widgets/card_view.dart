import 'package:flutter/material.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';

/// En linje på kortet der viser én funktion (fx "→ 7").
class CardCapability {
  const CardCapability(this.glyph, this.text);
  final String glyph;
  final String text;
}

/// Udled hvad et kort kan, ud fra de aktuelle regler.
List<CardCapability> describeCard(PlayingCard card, CardRules rules) {
  if (card.isExit) {
    return const <CardCapability>[CardCapability('♥', 'Ud')];
  }
  final CardRuleConfig c = rules.forRank(card.rank!);
  final out = <CardCapability>[];
  if (c.exitStart) out.add(const CardCapability('⤴', 'ud'));
  if (c.forwardSteps.isNotEmpty) {
    out.add(CardCapability('→', c.forwardSteps.join('/')));
  }
  if (c.backwardSteps != null) {
    out.add(CardCapability('←', '${c.backwardSteps}'));
  }
  if (c.splitTotal != null) {
    out.add(CardCapability('✂', '${c.splitTotal}'));
  }
  if (c.swap) out.add(const CardCapability('⇄', 'byt'));
  if (out.isEmpty) out.add(const CardCapability('–', ''));
  return out;
}

class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.card,
    required this.rules,
    this.faceUp = true,
    this.selected = false,
    this.onTap,
    this.width = 66,
  });

  final PlayingCard card;
  final CardRules rules;
  final bool faceUp;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final double height = width * 1.5;
    final bool exit = card.isExit;
    final Color accent =
        exit ? const Color(0xFFE53935) : (card.isRed ? const Color(0xFFD32F2F) : const Color(0xFF263238));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        margin: EdgeInsets.only(bottom: selected ? 14 : 0),
        decoration: BoxDecoration(
          gradient: faceUp
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Colors.white, Color(0xFFF3F4F6)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF1B5E8A), Color(0xFF0D3B5C)],
                ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.amber.shade700 : Colors.black26,
            width: selected ? 3 : 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: faceUp ? _buildFace(accent, exit) : null,
      ),
    );
  }

  Widget _buildFace(Color accent, bool exit) {
    final caps = describeCard(card, rules);
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            card.rankLabel,
            style: TextStyle(
              fontSize: width * 0.22,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (exit)
                    Text('♥',
                        style: TextStyle(
                            fontSize: width * 0.5, color: accent))
                  else
                    for (final CardCapability cap in caps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          '${cap.glyph} ${cap.text}'.trim(),
                          style: TextStyle(
                            fontSize: width * 0.22,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          Text(
            exit ? 'UD' : caps.map((c) => c.glyph).join(' '),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: width * 0.18,
              color: accent.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
