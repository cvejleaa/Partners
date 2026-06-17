import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/friends_service.dart';

/// Skærm til at søge, tilføje og fjerne venner.
///
/// Følger app-stilen: brun AppBar (`0xFF8B5E3C`) og mørkegrøn baggrund
/// (`0xFF0E2A1A`) — som hjemskærmen.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<UserRef> _results = const <UserRef>[];
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const <UserRef>[];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final res = await ref.read(friendsServiceProvider).searchUsers(query);
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = '$e';
      });
    }
  }

  Future<void> _addFriend(UserRef u) async {
    try {
      await ref.read(friendsServiceProvider).addFriend(u.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${u.displayName} tilføjet som ven')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke tilføje: $e')),
      );
    }
  }

  Future<void> _removeFriend(FriendRef f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern ven'),
        content: Text('Vil du fjerne ${f.displayName} fra dine venner?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fjern')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(friendsServiceProvider).removeFriend(f.uid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke fjerne: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsStreamProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: const Text('Mine venner'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _searchField(),
              const SizedBox(height: 12),
              if (_searchCtrl.text.trim().length >= 2) _searchResults(),
              if (_searchCtrl.text.trim().length >= 2) const SizedBox(height: 16),
              const Text(
                'Dine venner',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: friendsAsync.when(
                  data: (friends) {
                    if (friends.isEmpty) {
                      return const _EmptyHint(
                        text: 'Du har ingen venner endnu. Søg efter navn eller '
                            'e-mail ovenfor for at tilføje nogen.',
                      );
                    }
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (_, i) => _friendTile(friends[i]),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _EmptyHint(text: 'Fejl: $e'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Søg på navn eller e-mail',
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (_searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                  )
                : null),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF8B5E3C), width: 2),
        ),
      ),
    );
  }

  Widget _searchResults() {
    if (_searchError != null) {
      return _EmptyHint(text: 'Fejl: $_searchError');
    }
    if (_searching && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_results.isEmpty) {
      return const _EmptyHint(text: 'Ingen brugere fundet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'Søgeresultater',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        for (final u in _results) _resultTile(u),
      ],
    );
  }

  Widget _resultTile(UserRef u) {
    return Card(
      color: Colors.white.withValues(alpha: 0.92),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(u.displayName),
        subtitle: Text(u.email.isEmpty ? '—' : u.email),
        trailing: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B5E3C),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Tilføj'),
          onPressed: () => _addFriend(u),
        ),
      ),
    );
  }

  Widget _friendTile(FriendRef f) {
    return Card(
      color: Colors.white.withValues(alpha: 0.92),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(f.displayName),
        subtitle: Text(f.email.isEmpty ? '—' : f.email),
        trailing: IconButton(
          tooltip: 'Fjern ven',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _removeFriend(f),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}
