import 'package:flutter/material.dart';

import '../../models/variant_config.dart';
import 'variant_badge.dart';

/// "Hvad spiller vi" — badge, "Spil:", en dropdown og variantens beskrivelse
/// nedenunder. Den ENE vælger: lokal opsætning, "Nyt spil"-dialogen online og
/// lobbyen bruger den, så de ligner hinanden per konstruktion (QC-fund:
/// tre steder med hver sit udseende).
///
/// [onChanged] null = kun visning (fx en gæst i lobbyen, der ikke må vælge).
/// Er [selected] ikke i [variants] (fx en arkiveret custom, der allerede er
/// valgt), står den alligevel som gyldigt valg.
class VariantPicker extends StatelessWidget {
  const VariantPicker({
    super.key,
    required this.variants,
    required this.selected,
    required this.nameOf,
    this.descriptionOf,
    this.onChanged,
  });

  final List<VariantConfig> variants;
  final VariantConfig selected;
  final String Function(VariantConfig v) nameOf;
  final String? Function(VariantConfig v)? descriptionOf;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final String? desc = descriptionOf?.call(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            VariantBadge(
                variant: selected,
                compact: true,
                displayName: nameOf(selected)),
            const SizedBox(width: 8),
            const Text('Spil:'),
            const SizedBox(width: 12),
            Expanded(
              child: onChanged == null
                  ? Text(nameOf(selected),
                      style: const TextStyle(fontWeight: FontWeight.w600))
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: selected.id,
                      items: <DropdownMenuItem<String>>[
                        for (final VariantConfig v in <VariantConfig>[
                          ...variants,
                        ])
                          DropdownMenuItem<String>(
                              value: v.id,
                              child: Text(nameOf(v),
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (String? id) {
                        if (id != null) onChanged!(id);
                      },
                    ),
            ),
          ],
        ),
        if (desc != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(desc, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
