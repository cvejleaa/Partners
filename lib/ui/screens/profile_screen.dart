import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/card_rules.dart';
import '../../models/variant_config.dart';
import '../../online/online_service.dart';
import '../../stats/badges.dart';
import '../../state/variant_card_rules_controller.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';
import '../../utils/avatars.dart';
import '../widgets/badge_chip.dart';
import '../widgets/card_mix_block.dart';
import '../widgets/variant_badge.dart';
import 'friends_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _repo = StatsRepository();
  bool _recomputing = false;
  String? _error;

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(onlineServiceProvider);
    final current = await svc.myProfileStream().first;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _EditProfileSheet(
        initialName: current.displayName,
        initialAvatarId: current.avatar,
        onSave: (name, avatarId) async {
          await svc.updateProfile(displayName: name, avatar: avatarId);
        },
      ),
    );
  }

  Future<void> _recompute() async {
    setState(() {
      _recomputing = true;
      _error = null;
    });
    try {
      // Skriv kun min egen stats-doc (Firestore-reglerne tillader ikke at
      // skrive andres). Admin-genberegning af alle sker fra statistik-skærmen.
      final uid = ref.read(authStateProvider).valueOrNull?.uid;
      if (uid != null) {
        await _repo.recomputeAndSaveOwn(uid);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: Text('Log ind for at se din profil')),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Builder(
            builder: (context) {
              final p = ref.watch(myProfileProvider).valueOrNull;
              final name = p?.displayName ?? 'Min profil';
              final emoji = avatarEmoji(p?.avatar);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(name, overflow: TextOverflow.ellipsis)),
                ],
              );
            },
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Rediger navn & avatar',
              icon: const Icon(Icons.edit),
              onPressed: () => _editProfile(context, ref),
            ),
            IconButton(
              tooltip: 'Mine venner',
              icon: const Icon(Icons.people),
              onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const FriendsScreen())),
            ),
            IconButton(
              tooltip: 'Genberegn stats',
              icon: _recomputing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _recomputing ? null : _recompute,
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Sidste spil'),
              Tab(text: 'I alt'),
            ],
          ),
        ),
        body: Builder(builder: (BuildContext _) {
          // Config-doc'ets variants-map (fra controlleren) opløser custom-
          // varianters navn/tema på chips og badges — ellers står der rå id'er.
          final dynamic variantsRaw =
              ref.watch(variantCardRulesProvider).toRawJson();
          return TabBarView(
            children: <Widget>[
              _LastGameTab(
                  uid: user.uid, repo: _repo, variantsRaw: variantsRaw),
              _AllTimeTab(
                  uid: user.uid,
                  repo: _repo,
                  error: _error,
                  variantsRaw: variantsRaw),
            ],
          );
        }),
      ),
    );
  }
}

/// Bottom-sheet til at redigere navn + vælge avatar.
class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialAvatarId,
    required this.onSave,
  });
  final String initialName;
  final String? initialAvatarId;
  final Future<void> Function(String name, String avatarId) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late String _avatarId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _avatarId = avatarById(widget.initialAvatarId).id;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(name, _avatarId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke gemme: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Rediger profil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Spillernavn',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          const Text('Vælg avatar',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: kAvatars.length,
              itemBuilder: (ctx, i) {
                final a = kAvatars[i];
                final selected = a.id == _avatarId;
                return InkWell(
                  onTap: () => setState(() => _avatarId = a.id),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black26,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(a.emoji,
                          style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Gem'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllTimeTab extends StatefulWidget {
  const _AllTimeTab(
      {required this.uid, required this.repo, this.error, this.variantsRaw});
  final String uid;
  final StatsRepository repo;
  final String? error;

  /// Config-doc'ets variants-map — opløser custom-varianters navn/tema.
  final dynamic variantsRaw;

  @override
  State<_AllTimeTab> createState() => _AllTimeTabState();
}

class _AllTimeTabState extends State<_AllTimeTab> {
  /// Valgt variant-chip. null = "Alle" (top-niveau, som i dag).
  String? _vid;

  /// Chip-listen er DATADREVET: indbyggede varianter + alle nøgler der faktisk
  /// findes i brugerens byVariant (så admin-definerede varianter dukker op af
  /// sig selv, når de får spil — uden at røre denne skærm igen). Selve reglen
  /// bor i variantIdsWithExtras, delt med site-skærmen.
  List<String> _chipVids(UserStatsDoc doc) =>
      variantIdsWithExtras(doc.byVariant.keys);

  Widget _chipRow(UserStatsDoc doc) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        FilterChip(
          label: Text('Alle · ${doc.total.gamesPlayed}'),
          selected: _vid == null,
          onSelected: (_) => setState(() => _vid = null),
        ),
        for (final vid in _chipVids(doc))
          FilterChip(
            // Spil-antallet står PÅ chippen, så man ser stikprøvens størrelse
            // før man læser procenter ("25 år · 3" advarer i sig selv).
            label: Text(
                '${variantFromRaw(vid, widget.variantsRaw).shortLabel} · ${doc.byVariant[vid]?.gamesPlayed ?? 0}'),
            selected: _vid == vid,
            selectedColor: variantFromRaw(vid, widget.variantsRaw).badgeColor,
            checkmarkColor: _vid == vid ? Colors.white : null,
            labelStyle:
                _vid == vid ? const TextStyle(color: Colors.white) : null,
            onSelected: (_) => setState(() => _vid = vid),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserStatsDoc?>(
      stream: widget.repo.watchDoc(widget.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = snap.data;
        if (doc == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ingen stats endnu. Spil et spil til ende, og tryk så '
                    'på refresh-ikonet for at beregne.',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(widget.error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          );
        }
        final UserStats? shown = _vid == null ? doc.total : doc.byVariant[_vid];
        final leading = <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _chipRow(doc),
          ),
          // Sammenligningen på tværs (kun når "Alle" er valgt og der faktisk
          // er noget at sammenligne — én variant er ingen sammenligning).
          if (_vid == null && doc.byVariant.length >= 2)
            _VariantComparisonCard(
                doc: doc,
                chipVids: _chipVids(doc),
                variantsRaw: widget.variantsRaw),
        ];
        if (shown == null || shown.gamesPlayed == 0) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              ...leading,
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    _vid == null
                        ? 'Ingen spil endnu.'
                        : 'Ingen spil i denne variant endnu.',
                    textAlign: TextAlign.center),
              ),
            ],
          );
        }
        return _StatsBody(
          stats: shown,
          singleGame: false,
          leading: leading,
          // Badges er livstids-præstationer og vises kun under "Alle" — under
          // en variant-chip ville et (altid identisk) badge-kort friste til at
          // læse dem som optjent i varianten.
          showBadges: _vid == null,
        );
      },
    );
  }
}

/// "Dine varianter" — én række pr. variant med spil: antal · sejre · snit
/// hænder pr. sejr. Det er sammenligningen der gør pr-variant-statistik
/// værdifuld ("vinder vi hurtigere i 25 år?"), så den står øverst.
class _VariantComparisonCard extends StatelessWidget {
  const _VariantComparisonCard(
      {required this.doc, required this.chipVids, this.variantsRaw});
  final UserStatsDoc doc;
  final List<String> chipVids;
  final dynamic variantsRaw;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final vid in chipVids) {
      final s = doc.byVariant[vid];
      if (s == null || s.gamesPlayed == 0) continue;
      final v = variantFromRaw(vid, variantsRaw);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: v.badgeColor, shape: BoxShape.circle),
            ),
            Expanded(child: Text(v.shortLabel)),
            Text(
              '${s.gamesPlayed} spil · ${s.gamesWon} sejre'
              '${s.avgHandsPerWin > 0 ? ' · ${s.avgHandsPerWin.toStringAsFixed(1)} hænder/sejr' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Dine varianter',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _LastGameTab extends StatefulWidget {
  const _LastGameTab(
      {required this.uid, required this.repo, this.variantsRaw});
  final String uid;
  final StatsRepository repo;
  final dynamic variantsRaw;

  @override
  State<_LastGameTab> createState() => _LastGameTabState();
}

/// Sidste spil + det langtidssnit dets kortregnskab måles mod. Hentes samlet,
/// så skærmen ikke skal jonglere to futures der kan lande i hver sin ende.
class _LastGameView {
  _LastGameView(this.last, this.anchor);
  final LastGameStats? last;
  final UserStats? anchor;
}

class _LastGameTabState extends State<_LastGameTab> {
  Future<_LastGameView>? _future;

  Future<_LastGameView> _load() async {
    final LastGameStats? last = await widget.repo.lastGameStatsFor(widget.uid);
    if (last == null) return _LastGameView(null, null);
    // Ankeret må aldrig vælte skærmen: kan det ikke hentes, vises tallene
    // bare uden snit.
    UserStats? anchor;
    try {
      anchor = await widget.repo.cardMixAnchorFor(widget.uid, last.variantId);
    } catch (_) {
      anchor = null;
    }
    return _LastGameView(last, anchor);
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _future = _load();
        });
        await _future;
      },
      child: FutureBuilder<_LastGameView>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final last = snap.data?.last;
          if (last == null) {
            return ListView(
              children: const <Widget>[
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Du har ikke spillet et færdigspillet spil endnu.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          }
          return _StatsBody(
            stats: last.stats,
            singleGame: true,
            cardRules: last.cardRules,
            cardMixAnchor: snap.data?.anchor,
            leading: <Widget>[
              // Read-only mærke for det SPILS variant (sidste spil HAR en
              // variant — et filter ville ikke give mening her). Ikke
              // interaktivt: info-dialogen kender ikke custom-varianters
              // beskrivelse fra dette sted.
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VariantBadge(
                    variant:
                        variantFromRaw(last.variantId, widget.variantsRaw),
                    interactive: false,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Viser stats. Når [singleGame] er true skjules tværgående tal
/// (streaks, makker-/rival-aggregater) der ikke giver mening for ét spil.
/// [leading] indsættes øverst (variant-chips/badge); [showBadges] slår
/// badge-sektionen fra i variant-visning (badges er livstids, på tværs).
class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.stats,
    required this.singleGame,
    this.leading = const <Widget>[],
    this.showBadges = true,
    this.cardRules,
    this.cardMixAnchor,
  });
  final UserStats stats;
  final bool singleGame;
  final List<Widget> leading;
  final bool showBadges;

  /// Spillets opløste regler — kun til underteksten i kortregnskabet, så den
  /// navngiver de kort DEN variant faktisk havde.
  final CardRules? cardRules;

  /// Langtids-tallene et enkelt partis kortregnskab måles mod. null i
  /// "I alt"-fanen, hvor tallet selv ER snittet.
  final UserStats? cardMixAnchor;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        ...leading,
        if (!singleGame && showBadges) _BadgesSection(stats: s),
        _section('Sejre & resultater', <Widget>[
          _statRow(singleGame ? 'Resultat' : 'Vundne spil',
              singleGame
                  ? (s.gamesWon > 0 ? 'Vundet' : 'Tabt')
                  : '${s.gamesWon}/${s.gamesPlayed}'),
          // Under 5 spil er en procent støj (1/3 → "33 %") — brøken står i
          // rækken ovenfor, og procent-rækken venter til stikprøven kan bære
          // den. (Grænsen 5 er valgt så 2/3-tilfældet — det spil-rådgiveren
          // pegede på — IKKE viser procent.)
          if (!singleGame && s.gamesPlayed >= 5)
            _statRow('Win-rate', '${(s.winRate * 100).toStringAsFixed(0)}%'),
          if (s.shortestWin != null)
            _statRow(singleGame ? 'Antal hænder' : 'Kortest sejr 🏁',
                '${s.shortestWin} hænder'),
          if (singleGame && s.winMarginGames > 0)
            _statRow('Vandt med 🏆', '${s.winMarginSum} felter'),
          if (singleGame && s.lossMarginGames > 0)
            _statRow('Tabte med', '${s.lossMarginSum} felter'),
          if (!singleGame && s.avgWinMargin != null)
            _statRow('Vinder i snit med 🏆',
                '${s.avgWinMargin!.toStringAsFixed(0)} felter'),
          if (!singleGame && s.maxWinMargin != null)
            _statRow('Største sejr 💪', '${s.maxWinMargin} felter'),
          if (!singleGame && s.minWinMargin != null)
            _statRow('Tætteste sejr 😅', '${s.minWinMargin} felter'),
          if (!singleGame && s.avgLossMargin != null)
            _statRow('Taber i snit med',
                '${s.avgLossMargin!.toStringAsFixed(0)} felter'),
          if (!singleGame && s.longestWinStreak > 0)
            _statRow('Længste sejrsstime 📈', '${s.longestWinStreak}'),
          if (!singleGame && s.bestPartner != null)
            _statRow(
                'Bedste makker',
                '${s.bestPartner!.value.displayName} '
                    '(${s.bestPartner!.value.wins}/${s.bestPartner!.value.games})'),
          if (!singleGame && s.worstRival != null)
            _statRow(
                'Værste rival',
                '${s.worstRival!.value.displayName} '
                    '(${s.worstRival!.value.games - s.worstRival!.value.wins}/${s.worstRival!.value.games})'),
          if (singleGame && s.partnerStats.isNotEmpty)
            _statRow('Makker', s.partnerStats.values.first.displayName),
        ]),
        _section('Stil & strategi', <Widget>[
          // "Delekort", ikke "7'er": i 25 år ligger delingen på 4×1-kortet —
          // tallet tælles på reglens form (splitTotal), ikke på rangen.
          if (s.split7Count + s.solid7Count > 0)
            _statRow('Delekort: delt vs samlet ✂️',
                '${(s.split7Ratio * 100).toStringAsFixed(0)}% delt (${s.split7Count}/${s.split7Count + s.solid7Count})'),
          if (s.captureGames > 0)
            _statRow(singleGame ? 'Slag givet ⚔️' : 'Slag pr. spil ⚔️',
                singleGame
                    ? '${s.totalCaptures}'
                    : s.avgCapturesPerGame.toStringAsFixed(1)),
          if (!singleGame && s.maxCapturesInGame > 0)
            _statRow('Brand-mester 🔥', '${s.maxCapturesInGame} slag i ét spil'),
          if (s.timesCaptured > 0)
            _statRow('Slag modtaget', '${s.timesCaptured}'),
          if (s.swapCount > 0)
            _statRow('Byttejunkie 🔀', '${s.swapCount}'),
          if (s.homeStretchEntries > 0)
            _statRow('Hjem-mester 🏠', '${s.homeStretchEntries} brikker i mål'),
          if (s.favoriteOpener != null)
            _statRow(singleGame ? 'Åbnede med 🎴' : 'Yndlingsåbner 🎴',
                s.favoriteOpener!),
        ]),
        _section('Held & uheld', <Widget>[
          if (s.passCount > 0)
            _statRow('Sad over 😴', '${s.passCount} runder'),
          if (s.totalCardsDiscarded > 0)
            _statRow('Døde kort ☠️', '${s.totalCardsDiscarded} smidt'),
          // Kortregnskabet pr. par. Kun i spil hvor alle fire pladser var
          // mennesker — se CardMixBlock.hasData.
          if (CardMixBlock.hasData(s)) ...<Widget>[
            const SizedBox(height: 6),
            Text(singleGame ? 'Sådan faldt kortene' : 'Kortene i alt',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            CardMixBlock(
                stats: s, rules: cardRules, anchor: cardMixAnchor),
          ],
        ]),
        _section('Tempo & adfærd', <Widget>[
          if (!singleGame && s.gamesPlayed > 0) ...<Widget>[
            _statRow('Online vs AI',
                '${s.gamesOnline} online · ${s.gamesAiOnly} med AI'),
            _statRow('Værts-rate 👑',
                '${s.gamesAsHost}/${s.gamesPlayed} spil'),
          ],
          if (singleGame)
            _statRow('Spil-type',
                s.gamesOnline > 0 ? 'Online' : 'Med AI'),
          if (!singleGame && s.avgHandsPerWin > 0)
            _statRow('Snit hænder pr. sejr',
                s.avgHandsPerWin.toStringAsFixed(1)),
          if (s.avgThinkSeconds != null)
            _statRow(singleGame ? 'Tænketid pr. træk ⏱️' : 'Tænketid pr. træk ⏱️',
                '${s.avgThinkSeconds!.toStringAsFixed(1)} s'),
          if (s.fastestThinkSeconds != null)
            _statRow('Lyn-træk ⚡',
                '${s.fastestThinkSeconds!.toStringAsFixed(1)} s'),
          if (singleGame && s.totalMinutesPlayed > 0)
            _statRow('Spilletid',
                '${s.totalMinutesPlayed.toStringAsFixed(0)} min'),
          if (!singleGame && s.totalMinutesPlayed > 0)
            _statRow('Total spilletid',
                '${s.totalMinutesPlayed.toStringAsFixed(0)} min'),
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final filtered = rows.where((w) => w is! SizedBox).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...filtered,
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Viser optjente badges som farverige chips og låste badges nedtonet,
/// grupperet pr. kategori. En lille tæller i toppen viser fremgangen.
class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final unlocked = unlockedBadgeCount(stats);
    final total = kAllBadges.length;
    final groups = badgesByCategory();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Badges 🏆',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('$unlocked/$total',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Optjen badges ved at spille og udvikle din stil. Badges '
                'tæller alle dine spil — også på tværs af varianter.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            for (final entry in groups.entries) ...<Widget>[
              const SizedBox(height: 12),
              Text(entry.key.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final badge in entry.value)
                    BadgeChip(badge: badge, stats: stats),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
