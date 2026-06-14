import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/palette.dart';
import '../../app.dart';
import 'game_screen.dart';
import 'self_test_screen.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final List<TextEditingController> _names = <TextEditingController>[
    TextEditingController(text: 'Du'),
    TextEditingController(text: 'AI 1'),
    TextEditingController(text: 'AI 2 (makker)'),
    TextEditingController(text: 'AI 3'),
  ];

  final List<int> _colorIdx = <int>[0, 1, 2, 3];

  @override
  void dispose() {
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool unique = _colorIdx.toSet().length == 4;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partners — Opsætning'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Kør selvtest',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const SelfTestScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Indtast navn og vælg farve for hver spiller. '
              'Spiller 1 er menneske; Spiller 3 er din makker. '
              'Spillere overfor hinanden danner hold.',
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < 4; i++) ...<Widget>[
              _PlayerRow(
                index: i,
                nameController: _names[i],
                colorIdx: _colorIdx[i],
                onColorChanged: (int c) =>
                    setState(() => _colorIdx[i] = c),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            if (!unique)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Vælg fire forskellige farver.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: unique
                    ? () {
                        final List<PlayerSetup> setups = <PlayerSetup>[
                          for (int i = 0; i < 4; i++)
                            PlayerSetup(
                              name: _names[i].text.trim().isEmpty
                                  ? 'Spiller ${i + 1}'
                                  : _names[i].text.trim(),
                              color: kPalette[_colorIdx[i]].color,
                              isHuman: i == 0,
                            ),
                        ];
                        ref.read(gameProvider.notifier).startGame(setups);
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const GameScreen(),
                          ),
                        );
                      }
                    : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Start spil'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.index,
    required this.nameController,
    required this.colorIdx,
    required this.onColorChanged,
  });

  final int index;
  final TextEditingController nameController;
  final int colorIdx;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 90,
          child: Text('Spiller ${index + 1}'),
        ),
        Expanded(
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Navn',
            ),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: colorIdx,
          items: <DropdownMenuItem<int>>[
            for (int i = 0; i < kPalette.length; i++)
              DropdownMenuItem<int>(
                value: i,
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: kPalette[i].color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(kPalette[i].name),
                  ],
                ),
              ),
          ],
          onChanged: (int? v) {
            if (v != null) onColorChanged(v);
          },
        ),
      ],
    );
  }
}
