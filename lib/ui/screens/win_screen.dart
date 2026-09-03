import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/card_rules.dart';
import '../../models/variant_config.dart';
import '../../online/online_service.dart';
import '../../services/feedback_service.dart';
import '../../stats/records.dart';
import '../../stats/stats_repository.dart';
import '../../stats/user_stats.dart';
import '../../state/variant_card_rules_controller.dart';
import '../widgets/card_mix_block.dart';
import '../widgets/variant_badge.dart';

/// Skal skærmen FEJRE — konfetti og fanfare?
///
/// BRUGERFUND: konfettien faldt også når man havde tabt, og sejrsfanfaren
/// lød ubetinget. En fejring man ikke er med i er ikke bare overflødig; den
/// gør nederlaget værre.
///
/// [viewerWon] null = seeren sad ikke med (tilskuer, eller et spil hvor
/// pladsen ikke kunne bestemmes). Så er der stadig en vinder at fejre, bare
/// ikke seeren selv — og en stille skærm ville se ud som en fejl.
bool celebrateWin(bool? viewerWon) => viewerWon == true;

class WinScreen extends ConsumerStatefulWidget {
  const WinScreen({
    super.key,
    required this.winningTeamIndex,
    this.fromOnline = false,
    this.boardImage,
    this.marginFields,
    this.viewerWon,
    this.winnerNames = const <String>[],
    this.winnerColors = const <Color>[],
    this.onRematch,
    this.rematchLabel,
    this.variant,
    this.gameCode,
    this.archived = false,
    this.playedAt,
    this.cardMix,
    this.cardMixRules,
  });

  final int winningTeamIndex;

  /// Sand efter et ONLINE-spil — så nulstiller vi ikke den lokale AI-autosave.
  final bool fromOnline;

  /// PNG af slutstillingen (fanget lige før navigation). Vises som billede.
  final Uint8List? boardImage;

  /// Hvor mange felter det tabende hold manglede — marginen.
  final int? marginFields;

  /// Om den spiller der ser skærmen selv var på vinderholdet.
  final bool? viewerWon;

  final List<String> winnerNames;
  final List<Color> winnerColors;

  /// Spillets kode. Når den er sat, hentes rekorderne for PRÆCIS dét spil
  /// (målt som de så ud dengang) i stedet for "dit seneste spil".
  final String? gameCode;

  /// Åbnet fra arkivet (en gammel slutrapport) frem for lige efter spillet.
  /// Så: ingen sejrsfanfare (den ville lyde selv når man TABTE), og
  /// luk-knappen fører tilbage til listen i stedet for helt ud på forsiden.
  final bool archived;

  /// Hvornår partiet blev spillet — vises kun i arkiv-visningen, hvor man
  /// ellers ikke kan kende partierne fra hinanden.
  final DateTime? playedAt;

  /// Kortregnskabet for PRÆCIS dette parti (mit par mod modstanderparret),
  /// beregnet af kalderen, som allerede har spil-doc'et. null = ingen blok —
  /// fx et solospil mod computeren, hvor et heldregnskab intet siger.
  final UserStats? cardMix;

  /// Spillets opløste regler — kun til underteksten under tallene.
  final CardRules? cardMixRules;

  /// Kald for at starte en revanche (online) / nyt spil (AI). Vises som knap
  /// hvis sat.
  final Future<void> Function(BuildContext context)? onRematch;
  final String? rematchLabel;

  /// Hvilken variant spillet var — vises som badge ("vi vandt et 25 år-spil").
  /// null = ukendt (ingen badge).
  final VariantConfig? variant;

  @override
  ConsumerState<WinScreen> createState() => _WinScreenState();
}

class _WinScreenState extends ConsumerState<WinScreen>
    with SingleTickerProviderStateMixin {
  final _repo = StatsRepository();
  List<GameRecord> _records = const <GameRecord>[];
  late final AnimationController _confetti;
  bool _rematchBusy = false;

  /// Langtidssnittet kortregnskabet måles mod. null indtil det er hentet —
  /// tallene vises uden anker så længe.
  UserStats? _cardMixAnchor;

  /// Er kortblokken foldet ud? I den friske rapport starter den LUKKET: et
  /// heldregnskab serveret i samme sekund som nederlaget er en
  /// undskyldnings-maskine, og man skal selv bede om det. I arkivet, hvor man
  /// kigger tilbage i ro, står den åben.
  late bool _cardMixOpen = widget.archived;

  @override
  void initState() {
    super.initState();
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    // Kører kun når der faktisk falder konfetti — ellers er det en evig
    // animation ingen ser.
    if (celebrateWin(widget.viewerWon)) _confetti.repeat();
    _loadRecords();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fanfaren hører til ØJEBLIKKET (i arkivet ville den lyde hver gang man
      // åbner en gammel rapport) — OG til en sejr. Den lød før ubetinget,
      // også når man havde tabt.
      if (!widget.archived && celebrateWin(widget.viewerWon)) {
        ref.read(feedbackProvider).win();
      }
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    try {
      // Custom-varianters mærke opløses fra config-doc'ets variants-map, så
      // rekord-teksten siger "Ny rekord i Familie!" og ikke id'et.
      final dynamic variantsRaw =
          ref.read(variantCardRulesProvider).toRawJson();
      final String Function(String) label =
          (String vid) => variantFromRaw(vid, variantsRaw).shortLabel;
      // Kendes spillets kode, måles rekorderne på PRÆCIS dét spil, som de så
      // ud dengang — ellers ville en gammel rapport vise rekorder fra et
      // senere parti.
      // Rekorder OG kortregnskabets anker kommer ud af SAMME hentning, når
      // koden kendes (GameReport) — ingen ekstra læsning for ankeret.
      final GameReport report = widget.gameCode != null
          ? await _repo.recordsForGame(uid, widget.gameCode!, labelFor: label)
          : GameReport(
              records: await _repo.lastGameRecordsFor(uid, labelFor: label));
      if (!mounted) return;
      setState(() {
        if (report.records.isNotEmpty) _records = report.records;
        _cardMixAnchor = report.anchor;
      });
    } catch (_) {}
  }

  /// "14. aug. 2026 kl. 20.15" — dansk, kort, uden ekstra pakker.
  static String _playedAtLabel(DateTime t) {
    const List<String> m = <String>[
      'jan.', 'feb.', 'mar.', 'apr.', 'maj', 'jun.',
      'jul.', 'aug.', 'sep.', 'okt.', 'nov.', 'dec.',
    ];
    final String hh = t.hour.toString().padLeft(2, '0');
    final String mm = t.minute.toString().padLeft(2, '0');
    return '${t.day}. ${m[t.month - 1]} ${t.year} kl. $hh.$mm';
  }

  List<Color> get _confettiColors {
    if (widget.winnerColors.isNotEmpty) return widget.winnerColors;
    return const <Color>[
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFDD835),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Ved bordet siger man navnene, ikke "Hold A" — og i en rapport man ser
    // uger senere er holdet ellers uidentificerbart.
    final String teamLabel = widget.winnerNames.isEmpty
        ? (widget.winningTeamIndex == 0 ? 'Hold A' : 'Hold B')
        : widget.winnerNames.join(' & ');
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    final int? margin = widget.marginFields;

    String headline;
    if (widget.viewerWon == true) {
      headline = 'Du vandt! 🎉';
    } else if (widget.viewerWon == false) {
      headline = '$teamLabel vandt';
    } else {
      headline = '$teamLabel vandt! 🎉';
    }

    return Scaffold(
      // Variantens bordfarve når kendt — så bræt-billedet og skærmen matcher.
      backgroundColor:
          widget.variant?.tableColor ?? const Color(0xFF0E2A1A),
      body: Stack(
        children: <Widget>[
          // Konfetti bag indholdet — kun når der er noget at fejre.
          if (!reduceMotion && celebrateWin(widget.viewerWon))
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _confetti,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(_confetti.value, _confettiColors),
                ),
              ),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('🏆', style: TextStyle(fontSize: 64)),
                    if (widget.variant != null) ...<Widget>[
                      const SizedBox(height: 6),
                      // "Vi vandt et 25 år-spil" — badgen er en del af
                      // samtalen om sejren, ikke pynt.
                      VariantBadge(variant: widget.variant!),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.archived && widget.playedAt != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        _playedAtLabel(widget.playedAt!),
                        style: const TextStyle(
                            color: Color(0xFF9C8B73), fontSize: 13),
                      ),
                    ],
                    if (margin != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        widget.viewerWon == false
                            ? 'Tabt med $margin felter'
                            : 'Vundet med $margin felter',
                        style: const TextStyle(
                            color: Color(0xFFC9B896), fontSize: 16),
                      ),
                    ],
                    if (widget.winnerNames.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (int i = 0; i < widget.winnerNames.length; i++)
                            _winnerChip(widget.winnerNames[i],
                                i < widget.winnerColors.length
                                    ? widget.winnerColors[i]
                                    : Colors.white24),
                        ],
                      ),
                    ],
                    if (widget.boardImage != null) ...<Widget>[
                      const SizedBox(height: 18),
                      _boardShot(widget.boardImage!),
                    ],
                    if (_records.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      for (final r in _records) _RecordBanner(record: r),
                    ],
                    if (widget.cardMix != null &&
                        CardMixBlock.homeHitsLine(widget.cardMix!) !=
                            null) ...<Widget>[
                      const SizedBox(height: 14),
                      // Hjemslag står ÅBENT: det er historien om spillet, og
                      // den er der ingen grund til at gemme bag et tryk.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Text(
                          '🏠 ${CardMixBlock.homeHitsLine(widget.cardMix!)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                    if (widget.cardMix != null &&
                        CardMixBlock.hasData(widget.cardMix!)) ...<Widget>[
                      const SizedBox(height: 16),
                      _cardMixSection(widget.cardMix!),
                    ],
                    const SizedBox(height: 26),
                    if (widget.onRematch != null)
                      SizedBox(
                        width: 260,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF43A047),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _rematchBusy ? null : _doRematch,
                          icon: _rematchBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.replay),
                          label: Text(widget.rematchLabel ?? 'Revanche',
                              style: const TextStyle(fontSize: 17)),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 260,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          if (!widget.fromOnline) {
                            ref.read(gameProvider.notifier).reset();
                          }
                          if (widget.archived) {
                            // Fra arkivet: ét skridt tilbage til listen, så
                            // man kan åbne næste rapport. (popUntil dur IKKE
                            // her: prædikatet ville være sandt for rapportens
                            // egen rute og poppe nul gange.)
                            Navigator.of(context).pop();
                          } else {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          }
                        },
                        child: Text(widget.archived
                            ? 'Tilbage til listen'
                            : 'Tilbage til forsiden'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doRematch() async {
    setState(() => _rematchBusy = true);
    try {
      await widget.onRematch!(context);
    } catch (e) {
      if (mounted) {
        setState(() => _rematchBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke starte revanche: $e')));
      }
    }
  }

  /// "Sådan faldt kortene" — kortregnskabet, foldet sammen i den friske
  /// rapport og åbent i arkivet (se [_cardMixOpen]).
  ///
  /// Bredden bindes som brætbilledets, så de fire tal ikke wrapper på en
  /// telefon.
  Widget _cardMixSection(UserStats mix) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      // Material, IKKE en farvet Container: ExpansionTile indeholder en
      // ListTile, og en ListTile inde i en DecoratedBox med baggrundsfarve
      // gør Flutter indsigelse imod (dens blæk-effekter males på nærmeste
      // Material og ville blive skjult). Den indsigelse er en assertion —
      // usynlig i release, men den vælter enhver widget-test af skærmen.
      child: Material(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          // ExpansionTile tegner sine egne skillelinjer oven i kortet.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _cardMixOpen,
            onExpansionChanged: (bool open) => _cardMixOpen = open,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            // Rapporten tegner på variantens bordfarve — altid mørk, uanset
            // om appen kører lyst eller mørkt tema. Farverne sættes derfor
            // eksplicit; temaets tekstfarver ville være næsten sorte her.
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            title: const Text('Sådan faldt kortene',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            children: <Widget>[
              CardMixBlock(
                stats: mix,
                rules: widget.cardMixRules,
                anchor: _cardMixAnchor,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _winnerChip(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _boardShot(Uint8List bytes) {
    return Column(
      children: <Widget>[
        const Text('Slutstilling',
            style: TextStyle(color: Color(0xFFC9B896), fontSize: 13)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8B5E3C), width: 2),
            ),
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}

/// Let konfetti: farvede rektangler der drysser ned og roterer. Deterministisk
/// (ingen Random pr. frame) — partiklerne udledes af deres indeks.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.colors);
  final double t; // 0..1, gentages
  final List<Color> colors;
  static const int _count = 70;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int i = 0; i < _count; i++) {
      final double seed = i / _count;
      final double speed = 0.6 + (i % 5) * 0.12;
      final double phase = (seed * 7.13) % 1.0;
      final double prog = (t * speed + phase) % 1.0;
      final double x =
          (seed * 1.37 % 1.0) * size.width + math.sin((prog + seed) * 6.28) * 14;
      final double y = prog * (size.height + 40) - 20;
      final Color c = colors[i % colors.length];
      paint.color = c.withValues(alpha: 0.9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((prog + seed) * 6.28);
      final double w = 6 + (i % 3) * 2;
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Festligt banner der fejrer en personlig rekord.
class _RecordBanner extends StatelessWidget {
  const _RecordBanner({required this.record});
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C4A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF43A047), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(record.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                record.message,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
