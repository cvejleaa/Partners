import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/friends_service.dart';
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

  Widget _gameTile(BuildContext context, WidgetRef ref, GameSummary g) {
    final user = FirebaseAuth.instance.currentUser;
    final bool canDelete =
        (user != null && g.hostUid == user.uid) || isAdmin(user);
    return Card(
      child: ListTile(
        leading: Icon(g.isPlaying ? Icons.play_circle : Icons.meeting_room),
        title: Text('Spil ${g.code}  ·  vært: ${g.hostName}'),
        subtitle: Text(g.isLobby
            ? 'Venter i lobby'
            : (g.isPlaying ? 'Tryk for at genindtræde' : 'I gang')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (canDelete)
              IconButton(
                tooltip: 'Slet spil',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, g),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => g.isLobby
                  ? LobbyScreen(code: g.code)
                  : OnlineGameScreen(code: g.code)));
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, GameSummary g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet spil?'),
        content: Text(
            'Sletter "${g.code}" (${g.isLobby ? "lobby" : "i gang"}). '
            'Handlingen kan ikke fortrydes — alle deltagere mister adgangen.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Slet')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(onlineServiceProvider).deleteGame(g.code);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

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
                // Vis først dialog hvor man kan vælge venner at invitere.
                // Brugere uden venner ser blot et hint og kan trykke "Opret".
                final List<FriendRef>? invitees =
                    await showDialog<List<FriendRef>>(
                  context: context,
                  builder: (_) => const _InviteFriendsDialog(),
                );
                if (invitees == null) return; // brugeren annullerede
                final code = await svc.createGame(
                  colorValue: kPalette.first.color.toARGB32(),
                  rules: ref.read(cardRulesProvider),
                );
                // Send invitationer til markerede venner. Fejl pr. ven må ikke
                // forhindre at lobbyen åbnes.
                if (invitees.isNotEmpty) {
                  final friends = ref.read(friendsServiceProvider);
                  for (final f in invitees) {
                    try {
                      await svc.invite(code, f.uid);
                      await friends.sendGameInvite(f.uid, code);
                    } catch (_) {
                      // Ignorér en enkelt fejl — vis evt. snackbar nedenfor.
                    }
                  }
                }
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
                data: (list) {
                  if (list.isEmpty) {
                    return const Text('Ingen aktive spil endnu.');
                  }
                  // Igangværende spil først (så man hurtigt kan genindtræde),
                  // dernæst lobbyer der venter.
                  final playing = list.where((g) => g.isPlaying).toList();
                  final lobbies = list.where((g) => !g.isPlaying).toList();
                  return ListView(
                    children: <Widget>[
                      if (playing.isNotEmpty) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('Igangværende spil',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        for (final g in playing) _gameTile(context, ref, g),
                        const SizedBox(height: 12),
                      ],
                      if (lobbies.isNotEmpty) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('Venter i lobby',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        for (final g in lobbies) _gameTile(context, ref, g),
                      ],
                    ],
                  );
                },
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

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  Timer? _heartbeat;
  bool _navigatedToGame = false;

  String get code => widget.code;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(onlineServiceProvider);
    // ignore: discarded_futures
    svc.heartbeat(code);
    _heartbeat = Timer.periodic(kPresenceInterval, (_) {
      // ignore: discarded_futures
      svc.heartbeat(code);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          if (d['status'] == 'playing' && !_navigatedToGame) {
            _navigatedToGame = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement<void, void>(
                  MaterialPageRoute<void>(
                      builder: (_) => OnlineGameScreen(code: code)));
            });
          }
          final names = (d['names'] as List).map((e) => e as String).toList();
          final uids = d['uids'] as List;
          final colors =
              (d['colors'] as List).map((e) => (e as num).toInt()).toList();
          final ready = (d['ready'] as Map?) ?? const <String, dynamic>{};
          final aiSeats = (d['aiSeats'] as List?) ??
              const <dynamic>[false, false, false, false];
          final bool isHost = d['hostUid'] == svc.uid;
          final int seatOfMe = uids.indexOf(svc.uid);
          final int? mySeat = seatOfMe == -1 ? null : seatOfMe;
          final bool iAmReady =
              svc.uid != null && (ready[svc.uid] as bool? ?? false);

          // Antal optagne pladser (mennesker + AI-markerede).
          final int filledSeats = <int>[
            for (int i = 0; i < 4; i++)
              if (uids[i] != null ||
                  (i < aiSeats.length && aiSeats[i] == true))
                i,
          ].length;
          // Alle menneskelige deltagere skal være klar før start.
          final bool allHumansReady = <bool>[
            for (int i = 0; i < 4; i++)
              if (uids[i] != null) (ready[uids[i]] as bool? ?? false),
          ].every((r) => r);
          final bool canStart = filledSeats >= 2 && allHumansReady;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Del koden $code, eller invitér spillere på email.'),
                const SizedBox(height: 12),
                for (int i = 0; i < 4; i++)
                  _seatCard(context, svc,
                      seat: i,
                      names: names,
                      uids: uids,
                      colors: colors,
                      ready: ready,
                      aiSeats: aiSeats,
                      isHost: isHost,
                      mySeat: mySeat),
                const SizedBox(height: 12),
                if (isHost)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Invitér spiller (email)'),
                    onPressed: () => _invite(context, svc),
                  ),
                if (mySeat != null) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    icon: Icon(iAmReady ? Icons.check_circle : Icons.schedule),
                    label: Text(iAmReady ? 'Du er klar' : 'Marker klar'),
                    onPressed: () => svc.setReady(code, !iAmReady),
                  ),
                ],
                const Spacer(),
                if (isHost)
                  FilledButton(
                    onPressed: canStart ? () => svc.startGameFromLobby(code) : null,
                    child: Text(canStart
                        ? 'Start spil'
                        : (filledSeats < 2
                            ? 'Mindst 2 pladser kræves'
                            : 'Venter på at alle er klar…')),
                  ),
                if (isHost && filledSeats < 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Tomme pladser bliver til computer-spillere ved start.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _seatCard(
    BuildContext context,
    OnlineService svc, {
    required int seat,
    required List<String> names,
    required List uids,
    required List<int> colors,
    required Map ready,
    required List aiSeats,
    required bool isHost,
    required int? mySeat,
  }) {
    final bool isAi = seat < aiSeats.length && aiSeats[seat] == true;
    final bool occupied = uids[seat] != null;
    final bool isReady =
        occupied ? (ready[uids[seat]] as bool? ?? false) : false;
    final String subtitle;
    if (occupied) {
      subtitle = seat == 0
          ? (isReady ? 'Vært · klar' : 'Vært')
          : (isReady ? 'Tilsluttet · klar' : 'Tilsluttet · ikke klar');
    } else if (isAi) {
      subtitle = 'Computer-spiller';
    } else {
      subtitle = 'Åben plads';
    }

    Widget? trailing;
    if (!occupied && !isAi && mySeat == null) {
      trailing = TextButton(
        onPressed: () =>
            svc.joinGame(code: code, seat: seat, colorValue: colors[seat]),
        child: const Text('Tag plads'),
      );
    } else if (!occupied && isHost) {
      // Vært kan slå AI til/fra på tomme pladser.
      trailing = TextButton(
        onPressed: () => svc.fillSeatWithAi(code, seat, ai: !isAi),
        child: Text(isAi ? 'Gør åben' : 'Fyld med AI'),
      );
    } else if (occupied) {
      trailing = Icon(
        isReady ? Icons.check_circle : Icons.schedule,
        color: isReady ? Colors.green : Colors.grey,
      );
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(colors[seat]),
          child: isAi
              ? const Icon(Icons.smart_toy, size: 18, color: Colors.white)
              : null,
        ),
        title: Text(occupied
            ? names[seat]
            : (isAi ? 'Computer' : 'Åben plads')),
        subtitle: Text(subtitle),
        trailing: trailing,
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

// ---------------------------------------------------------------------------
// Dialog: vælg venner at invitere ved oprettelse af nyt spil
// ---------------------------------------------------------------------------

class _InviteFriendsDialog extends ConsumerStatefulWidget {
  const _InviteFriendsDialog();

  @override
  ConsumerState<_InviteFriendsDialog> createState() =>
      _InviteFriendsDialogState();
}

class _InviteFriendsDialogState extends ConsumerState<_InviteFriendsDialog> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsStreamProvider);
    return AlertDialog(
      title: const Text('Inviter venner'),
      content: SizedBox(
        width: 320,
        child: friendsAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Fejl: $e'),
          data: (friends) {
            if (friends.isEmpty) {
              return const Text(
                'Tilføj venner i din profil for at invitere direkte.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (_, i) {
                  final f = friends[i];
                  final picked = _selected.contains(f.uid);
                  return CheckboxListTile(
                    value: picked,
                    title: Text(f.displayName),
                    subtitle: Text(f.email.isEmpty ? '—' : f.email),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(f.uid);
                        } else {
                          _selected.remove(f.uid);
                        }
                      });
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annullér'),
        ),
        FilledButton(
          onPressed: () {
            final friends = ref.read(friendsStreamProvider).valueOrNull ??
                const <FriendRef>[];
            final picked =
                friends.where((f) => _selected.contains(f.uid)).toList();
            Navigator.pop(context, picked);
          },
          child: Text(_selected.isEmpty
              ? 'Opret uden invitationer'
              : 'Opret og inviter (${_selected.length})'),
        ),
      ],
    );
  }
}
