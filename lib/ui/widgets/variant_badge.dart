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
    this.interactive = true,
    this.displayName,
  });

  final VariantConfig variant;

  /// Kompakt (AppBar/liste-række): mindre skrift/padding.
  final bool compact;

  /// Slå tap fra hvor badgen sidder OVEN PÅ en primær handling (fx "Mine
  /// spil"-rækken, hvor hele rækken åbner spillet) — en dialog midt i den
  /// handling ville være en dead zone.
  final bool interactive;

  /// Resolvet navn (admins evt. eget, fx fra doc'ets cardRulesVariants-kopi)
  /// til tooltip/dialog. Chip-teksten er ALTID [VariantConfig.shortLabel] —
  /// kort, fast bredde. null = variantens kode-navn.
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    // Egen Material med chippens farve: garanterer Material-forælder uanset
    // placering, og gør ink-splashet synligt PÅ chippen (et splash på
    // materialet under en uigennemsigtig chip ses aldrig).
    final Widget chip = Material(
      color: variant.badgeColor,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: interactive ? () => _showInfo(context) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 10, vertical: compact ? 3 : 5),
          child: Text(
            variant.shortLabel,
            // Custom-varianters shortLabel er deres fulde navn — uden ellipsis
            // ville et langt navn give RenderFlex-overflow i AppBar-rækken.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: displayName ?? variant.name, child: chip);
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(displayName ?? variant.name),
        content: Text(variant.infoText),
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
