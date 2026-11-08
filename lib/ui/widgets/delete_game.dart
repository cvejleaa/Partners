import 'package:flutter/material.dart';

import '../../online/game_delete.dart';
import '../../online/online_service.dart';

/// "⋮"-menuen i en lobby eller et spil i gang — det ENE sted, et spil kan
/// slettes. Ingen knap i "Mine spil"-listen: dér sad skraldespanden lige ved
/// pilen, der åbner spillet, og var for let at ramme (ejer-fund). Nu kræver
/// det tre bevidste skridt: åbn spillet, åbn menuen, vælg "Slet spil" — og
/// for et spil i gang også spillets kode.
///
/// Vises kun, når [mode] ikke er [DeleteMode.none].
Widget deleteGameMenu({
  required BuildContext context,
  required OnlineService svc,
  required String code,
  required DeleteMode mode,
  required List<String> losers,
}) {
  return PopupMenuButton<String>(
    tooltip: 'Flere valg',
    icon: const Icon(Icons.more_vert),
    itemBuilder: (_) => const <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'delete',
        child: ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('Slet spil'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    onSelected: (_) => _deleteFlow(context, svc, code, mode, losers),
  );
}

Future<void> _deleteFlow(BuildContext context, OnlineService svc, String code,
    DeleteMode mode, List<String> losers) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteGameDialog(code: code, mode: mode, losers: losers),
  );
  if (ok != true || !context.mounted) return;
  // Rækkefølgen: hent rod-messengeren, LUK skærmen, slet. Sletter man, mens
  // skærmen lever, kan værtens AI-træk/heartbeat ramme et dokument, der ikke
  // findes, og skærmen viser kortvarigt en misvisende tekst (QC-fund).
  // Tilbage til der, hvor man kom fra (Online-siden, forsiden, et deep-link).
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pop();
  try {
    await svc.deleteGame(code);
    messenger.showSnackBar(SnackBar(content: Text('Spil $code er slettet.')));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Kunne ikke slette spil $code: $e')));
  }
}

class _DeleteGameDialog extends StatefulWidget {
  const _DeleteGameDialog(
      {required this.code, required this.mode, required this.losers});
  final String code;
  final DeleteMode mode;
  final List<String> losers;

  @override
  State<_DeleteGameDialog> createState() => _DeleteGameDialogState();
}

class _DeleteGameDialogState extends State<_DeleteGameDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ready =>
      widget.mode == DeleteMode.simple ||
      deleteCodeMatches(_typed.text, widget.code);

  @override
  Widget build(BuildContext context) {
    final bool playing = widget.mode == DeleteMode.typeCode;
    final String who = widget.losers.isEmpty
        ? ''
        : (playing
            ? ' ${widget.losers.join(', ')} mister partiet.'
            : ' ${widget.losers.join(', ')} mister pladsen i lobbyen.');
    return AlertDialog(
      title: Text(playing ? 'Slet spil i gang?' : 'Slet lobby?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Spil ${widget.code} slettes for alle, og det kan ikke '
              'fortrydes.$who'),
          if (playing) ...<Widget>[
            const SizedBox(height: 12),
            Text('Skriv spillets kode (${widget.code}) for at slette:'),
            TextField(
              controller: _typed,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Kode'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_ready) Navigator.pop(context, true);
              },
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annullér')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: _ready ? () => Navigator.pop(context, true) : null,
          child: const Text('Slet'),
        ),
      ],
    );
  }
}

/// Det, de ANDRE spillere ser, når værten har slettet spillet: hvad der skete,
/// og en vej tilbage — ikke "Venter på at spillet starter…".
class GameDeletedView extends StatelessWidget {
  const GameDeletedView({super.key, this.dark = false});

  /// Mørk baggrund (spilbordet) → hvid tekst.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color fg = dark ? Colors.white : Colors.black87;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.delete_outline, size: 40, color: fg),
            const SizedBox(height: 12),
            Text('Spillet er slettet af værten.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: fg)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Tilbage'),
            ),
          ],
        ),
      ),
    );
  }
}
