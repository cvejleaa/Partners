import 'package:flutter/material.dart';

import '../../models/board.dart';
import '../../models/game_state.dart';
import 'board_view.dart';

/// Brættet som det så ud, da trækket blev lavet — med brikken der flyttede.
///
/// Genbruger husets eget [BoardView] frem for at tegne en ny slags diagram:
/// spilleren har set den runde skive hele partiet, og en anden, lineær
/// repræsentation midt i en besked ville være et tredje visuelt sprog at lære
/// (spil-rådgiverens fund). [viewerIndex] drejer brættet så min egen plads
/// vender nedad — samme orientering som under spillet.
///
/// Brættet BÆRER ikke beskeden alene: felt-tallene er for små at læse ved
/// denne størrelse, så sætningen ved siden af siger hvor brikken kom fra og
/// hen. Grafikken viser HVOR på brættet, teksten siger HVAD.
class ReplayBoardView extends StatefulWidget {
  const ReplayBoardView({
    super.key,
    required this.board,
    required this.moves,
    required this.viewerIndex,
    this.highlight = const <String>{},
    this.colorOffset = 0,
    this.size = 220,
  });

  /// Stillingen FØR trækket.
  final GameState board;

  /// Brikkerne der flyttede, fra → til.
  final Map<String, ({PiecePosition from, PiecePosition to})> moves;

  final int viewerIndex;

  /// Brikker der skal fremhæves — den der flyttede, og den der blev slået.
  final Set<String> highlight;

  /// Skal være DEN SAMME som spille-brættets, ellers skifter spillerne farve
  /// mellem replayen og brættet nedenunder. Se [colorOffsetFor].
  final int colorOffset;

  final double size;

  @override
  State<ReplayBoardView> createState() => _ReplayBoardViewState();
}

class _ReplayBoardViewState extends State<ReplayBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _play();
  }

  void _play() {
    if (widget.moves.isEmpty) return;
    // Et kort ophold før brikken går, så man når at se HVOR den stod.
    _anim
      ..value = 0
      ..forward();
  }

  @override
  void didUpdateWidget(covariant ReplayBoardView old) {
    super.didUpdateWidget(old);
    // Nyt skridt valgt → spil bevægelsen igen.
    if (old.moves != widget.moves) _play();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => BoardView(
          state: widget.board,
          viewerIndex: widget.viewerIndex < 0 ? 0 : widget.viewerIndex,
          highlightedPieceIds: widget.highlight,
          colorOffset: widget.colorOffset,
          // Samme drejning som det levende bræt nedenunder: siddende
          // spillere ser brættet kvart-drejet, tilskueren gør ikke. Ellers
          // står de to brætter en anelse skævt i forhold til hinanden.
          quarterTurn: widget.viewerIndex >= 0,
          animation: widget.moves.isEmpty
              ? null
              : BoardAnimation(widget.moves, _anim.value),
        ),
      ),
    );
  }
}
