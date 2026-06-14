import 'package:flutter/material.dart';

import '../../game/self_test.dart';

class SelfTestScreen extends StatefulWidget {
  const SelfTestScreen({super.key});

  @override
  State<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends State<SelfTestScreen> {
  bool _running = false;
  double _progress = 0;
  String _label = '';
  SelfTestReport? _report;
  int _gameCount = 20;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _progress = 0;
      _label = 'Starter…';
      _report = null;
    });
    final report = await runSelfTest(
      games: _gameCount,
      onProgress: (double p, String l) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _label = l;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
      _label = 'Færdig';
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Selvtest af spillet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Selvtesten kører hele spil med 4 AI-spillere og tjekker '
              'reglerne. Den verificerer at spillet altid kan spilles til ende '
              'uden ulovlige træk.',
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Text('Antal spil:'),
                Expanded(
                  child: Slider(
                    value: _gameCount.toDouble(),
                    min: 5,
                    max: 100,
                    divisions: 19,
                    label: '$_gameCount',
                    onChanged: _running
                        ? null
                        : (double v) =>
                            setState(() => _gameCount = v.round()),
                  ),
                ),
                SizedBox(width: 40, child: Text('$_gameCount')),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Kører…' : 'Kør selvtest'),
            ),
            const SizedBox(height: 16),
            if (_running) ...<Widget>[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(_label, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (report != null) _buildReport(context, report),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(BuildContext context, SelfTestReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: r.allPassed
                ? Colors.green.withOpacity(0.12)
                : Colors.red.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: r.allPassed ? Colors.green : Colors.red,
              width: 2,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                r.allPassed ? Icons.check_circle : Icons.error,
                color: r.allPassed ? Colors.green : Colors.red,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      r.allPassed
                          ? 'ALLE TESTS BESTÅET'
                          : 'NOGLE TESTS FEJLEDE',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${r.passedCount}/${r.checks.length} tjek bestået · '
                      '${r.durationMs} ms',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Tjek', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final CheckResult c in r.checks)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              c.passed ? Icons.check : Icons.close,
              color: c.passed ? Colors.green : Colors.red,
            ),
            title: Text(c.name),
            subtitle: c.detail.isEmpty ? null : Text(c.detail),
          ),
        const SizedBox(height: 16),
        Text('Statistik', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        _statRow('Spil spillet', '${r.gamesPlayed}'),
        _statRow('Hold A vandt', '${r.teamAWins}'),
        _statRow('Hold B vandt', '${r.teamBWins}'),
        _statRow('Uafsluttede spil', '${r.unfinishedGames}'),
        _statRow('Gns. hænder pr. spil', r.avgHands.toStringAsFixed(1)),
        _statRow('Træk i alt', '${r.totalMoves}'),
        _statRow('Slag i alt', '${r.totalCaptures}'),
        _statRow('Kort smidt i alt', '${r.totalDiscards}'),
        _statRow('Ulovlige træk', '${r.illegalMoves}',
            warn: r.illegalMoves > 0),
      ],
    );
  }

  Widget _statRow(String label, String value, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: warn ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }
}
