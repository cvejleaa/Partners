import 'package:flutter/material.dart';

import '../../models/playing_card.dart';

class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.card,
    this.faceUp = true,
    this.selected = false,
    this.onTap,
    this.width = 60,
  });

  final PlayingCard card;
  final bool faceUp;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final double height = width * 1.45;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        margin: EdgeInsets.only(bottom: selected ? 12 : 0),
        decoration: BoxDecoration(
          color: faceUp ? Colors.white : const Color(0xFF1B5E8A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.amber.shade700 : Colors.black54,
            width: selected ? 3 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: faceUp
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      card.rankLabel,
                      style: TextStyle(
                        fontSize: width * 0.30,
                        fontWeight: FontWeight.bold,
                        color: card.isRed ? Colors.red : Colors.black,
                      ),
                    ),
                    Text(
                      card.suitSymbol,
                      style: TextStyle(
                        fontSize: width * 0.30,
                        color: card.isRed ? Colors.red : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        card.suitSymbol,
                        style: TextStyle(
                          fontSize: width * 0.45,
                          color: card.isRed ? Colors.red : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}
