import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../online/online_service.dart';
import '../../services/feedback_service.dart';
import '../../stats/records.dart';
import '../../stats/stats_repository.dart';

class WinScreen extends ConsumerStatefulWidget {
  const WinScreen({super.key, required this.winningTeamIndex});

  final int winningTeamIndex;

  @override
  ConsumerState<WinScreen> createState() => _WinScreenState();
}

class _WinScreenState extends ConsumerState<WinScreen> {
  final _repo = StatsRepository();
  List<GameRecord> _records = const <GameRecord>[];

  @override
  void initState() {
    super.initState();
    _loadRecords();
    // Sejrs-feedback (lyd/haptik) når skærmen vises — styret af indstillinger.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(feedbackProvider).win();
    });
  }

  Future<void> _loadRecords() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return; // ikke logget ind → ingen rekorder, normal skærm
    try {
      // Stats genberegnes når spillet persisteres; vent kort og hent rekorder.
      // Hvis cachen endnu ikke er klar, returneres bare en tom liste.
      final records = await _repo.lastGameRecordsFor(uid);
      if (!mounted) return;
      if (records.isNotEmpty) {
        setState(() => _records = records);
      }
    } catch (_) {
      // Robust: vis bare den normale sejrsskærm hvis noget fejler.
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamLabel = widget.winningTeamIndex == 0 ? 'Hold A' : 'Hold B';
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
            if (_records.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              for (final r in _records) _RecordBanner(record: r),
            ],
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

/// Festligt banner der fejrer en personlig rekord.
class _RecordBanner extends StatelessWidget {
  const _RecordBanner({required this.record});
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(record.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                record.message,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
