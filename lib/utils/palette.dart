import 'package:flutter/material.dart';

class PaletteColor {
  const PaletteColor(this.name, this.color);
  final String name;
  final Color color;
}

const List<PaletteColor> kPalette = <PaletteColor>[
  PaletteColor('Rød', Color(0xFFE53935)),
  PaletteColor('Blå', Color(0xFF1E88E5)),
  PaletteColor('Grøn', Color(0xFF43A047)),
  PaletteColor('Gul', Color(0xFFFDD835)),
  PaletteColor('Lilla', Color(0xFF8E24AA)),
  PaletteColor('Orange', Color(0xFFFB8C00)),
  PaletteColor('Turkis', Color(0xFF00ACC1)),
  PaletteColor('Pink', Color(0xFFEC407A)),
];
