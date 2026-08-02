import 'board.dart';
import 'playing_card.dart';

/// Et enkelt step i et træk: en brik flytter til en ny position.
class MoveStep {
  const MoveStep({
    required this.pieceId,
    required this.from,
    required this.to,
    this.capturedPieceId,
    this.burnsMover = false,
  });

  final String pieceId;
  final PiecePosition from;
  final PiecePosition to;

  /// Hvis dette step slår en modstanderbrik retur, sættes ID'et her.
  final String? capturedPieceId;

  /// Sand hvis dette step lander på en modstander-"dobbelt" (2+ brikker):
  /// da slås den FLYTTENDE brik selv hjem ([to] er det felt den forsøgte at
  /// lande på, men brikken ender i sin egen startcirkel). Ingen modstander
  /// slås i dette tilfælde.
  final bool burnsMover;
}

/// Et komplet træk fra ét kort. Indeholder en eller flere steps. For 7'eren
/// kan flere brikker flyttes (i alt 7 felter); for andre kort er der kun ét
/// step.
class Move {
  const Move({
    required this.card,
    required this.steps,
    this.exitsStart = false,
  });

  final PlayingCard card;
  final List<MoveStep> steps;

  /// Sand hvis dette træk er "gå ud af start" (Es eller Konge).
  final bool exitsStart;
}
