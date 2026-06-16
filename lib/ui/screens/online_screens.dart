import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/online_service.dart';
import '../../state/card_rules_controller.dart';
import '../../utils/palette.dart';
import 'online_game_screen.dart';

// ---------------------------------------------------------------------------
// Login / opret konto
// ---------------------------------------------------------------------------

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _signup = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(onlineServiceProvider);
    try {
      if (_signup) {
        if (_name.text.trim().isEmpty) {
          throw 'Skriv et vist navn';
        }
        if (_pass.text.length < 6) {
          throw 'Adgangskode skal være mindst 6 tegn';
        }
        await svc.signUp(_email.text, _pass.text, _name.text);
      } else {
        await svc.signIn(_email.text, _pass.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => const OnlineHomeScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _humanAuthError(e));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!kIsWeb) {
        throw 'Google-login er kun aktiveret på web i denne version.';
      }
      await ref.read(onlineServiceProvider).signInWithGoogleViaPopup();
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => const OnlineHomeScreen()));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _humanAuthError(e));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email er allerede i brug — log ind i stedet.';
      case 'invalid-email':
        return 'Ugyldig email-adresse.';
      case 'weak-password':
        return 'For svag adgangskode (mindst 6 tegn).';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Forkert email eller adgangskode.';
      case 'user-not-found':
        return 'Ingen konto med den email — opret en konto.';
      case 'network-request-failed':
        return 'Netværksfejl — tjek internet og prøv igen.';
      case 'operation-not-allowed':
        return 'Login-metoden er ikke aktiveret i Firebase.';
      case 'popup-closed-by-user':
        return 'Google-vinduet blev lukket.';
      default:
        return '${e.code}: ${e.message ?? 'ukendt fejl'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_signup ? 'Opret konto' : 'Log ind')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            if (_signup)
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Vist navn', border: OutlineInputBorder()),
              ),
            if (_signup) const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Adgangskode', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_signup ? 'Opret konto' : 'Log ind'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.account_circle),
                label: const Text('Fortsæt med Google'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _signup = !_signup),
              child: Text(_signup
                  ? 'Har du en konto? Log ind'
                  : 'Ny her? Opret konto'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Online-hjem: opret spil + mine spil/invitationer
// ---------------------------------------------------------------------------

class OnlineHomeScreen extends ConsumerWidget {
  const OnlineHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(onlineServiceProvider);
    final games = ref.watch(myGamesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Log ud',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await svc.signOut();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Opret nyt spil'),
              onPressed: () async {
                final code = await svc.createGame(
                  colorValue: kPalette.first.color.toARGB32(),
                  rules: ref.read(cardRulesProvider),
                );
                if (context.mounted) {
                  Navigator.of(context).push<void>(MaterialPageRoute<void>(
                      builder: (_) => LobbyScreen(code: code)));
                }
              },
            ),
            const SizedBox(height: 20),
            const Text('Mine spil & invitationer',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: games.when(
                data: (list) => list.isEmpty
                    ? const Text('Ingen aktive spil endnu.')
                    : ListView(
                        children: <Widget>[
                          for (final g in list)
                            Card(
                              child: ListTile(
                                title: Text('Spil ${g.code}  ·  vært: ${g.hostName}'),
                                subtitle: Text(g.status == 'lobby'
                                    ? 'Venter i lobby'
                                    : 'I gang'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                          builder: (_) => g.status == 'lobby'
                                              ? LobbyScreen(code: g.code)
                                              : OnlineGameScreen(code: g.code)));
                                },
                              ),
                            ),
                        ],
                      ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Fejl: $e'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lobby: pladser, invitér spillere, start
// ---------------------------------------------------------------------------

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(onlineServiceProvider);
    final snap = ref.watch(gameStreamProvider(code));
    return Scaffold(
      appBar: AppBar(title: Text('Lobby — kode $code')),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fejl: $e')),
        data: (doc) {
          final d = doc.data();
          if (d == null) return const Center(child: Text('Spillet findes ikke'));
          if (d['status'] == 'playing') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacement<void, void>(
                  MaterialPageRoute<void>(
                      builder: (_) => OnlineGameScreen(code: code)));
            });
          }
          final names = (d['names'] as List).map((e) => e as String).toList();
          final uids = d['uids'] as List;
          final colors =
              (d['colors'] as List).map((e) => (e as num).toInt()).toList();
          final bool isHost = d['hostUid'] == svc.uid;
          final int? mySeat = uids.indexOf(svc.uid) == -1
              ? null
              : uids.indexOf(svc.uid);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Del koden $code, eller invitér spillere på email.'),
                const SizedBox(height: 12),
                for (int i = 0; i < 4; i++)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Color(colors[i])),
                      title: Text(uids[i] != null ? names[i] : 'Åben plads'),
                      subtitle: Text(uids[i] != null
                          ? (i == 0 ? 'Vært' : 'Tilsluttet')
                          : 'Bliver AI hvis ingen tager pladsen'),
                      trailing: (uids[i] == null && mySeat == null)
                          ? TextButton(
                              onPressed: () => svc.joinGame(
                                  code: code,
                                  seat: i,
                                  colorValue: colors[i]),
                              child: const Text('Tag plads'),
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: 12),
                if (isHost)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Invitér spiller (email)'),
                    onPressed: () => _invite(context, svc),
                  ),
                const Spacer(),
                if (isHost)
                  FilledButton(
                    onPressed: () => svc.start(code),
                    child: const Text('Start spil'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _invite(BuildContext context, OnlineService svc) async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invitér spiller'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email på oprettet spiller'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annullér')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Invitér')),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty) return;
    final user = await svc.findUserByEmail(email);
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingen oprettet spiller med den email')));
      }
      return;
    }
    await svc.invite(code, user['uid']!);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['displayName']} er inviteret')));
    }
  }
}
