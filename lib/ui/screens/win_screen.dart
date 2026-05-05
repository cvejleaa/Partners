import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';

class WinScreen extends ConsumerWidget {
  const WinScreen({super.key, required this.winningTeamIndex});

  final int winningTeamIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamLabel = winningTeamIndex == 0 ? 'Hold A' : 'Hold B';
    return Scaffold(
      appBar: AppBar(title: const Text('Spillet er slut')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$teamLabel vandt!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                ref.read(gameProvider.notifier).reset();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Tilbage til opsætning'),
            ),
          ],
        ),
      ),
    );
  }
}
