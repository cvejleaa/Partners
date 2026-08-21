import 'package:flutter/material.dart';

import '../../models/variant_config.dart';

/// Variant-mærket: en fyldt chip med variantens badge-farve og korte navn
/// ("Klassisk" grøn / "25 år" blå). Vises for BEGGE varianter — genkendelse på
/// positiv tilstedeværelse, og det er sådan man LÆRER farve-mappingen (et par
/// læres, en enkelt farve gør ikke). Farve + tekst sammen, aldrig farve alene
/// (farveblind-sikkert, og chippen er læsbar på både grøn og hvid baggrund —
/// bord-farverne selv ville forsvinde mod temaet).
///
/// Ét mærke, samme sted hver gang: spillets AppBar, lobbyen, "Mine spil",
/// vinderskærmen og variant-vælgeren. Tap åbner variantens beskrivelse, så
/// mærket også besvarer det næste spørgsmål ("hvad er anderledes her?").
class VariantBadge extends StatelessWidget {
  const VariantBadge({
    super.key,
    required this.variant,
    this.compact = false,
  });

  final VariantConfig variant;

  /// Kompakt (AppBar/liste-række): mindre skrift/padding.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: variant.badgeColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        variant.shortLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
    return Tooltip(
      message: variant.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showInfo(context),
        child: chip,
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(variant.name),
        content: Text(variant.description ??
            'Den klassiske Partners-udgave: 4 spillere, 2 hold med diagonale '
                'makkere, 4 brikker hver.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
