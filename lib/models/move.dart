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

/// Positiv genkendelse af et BYT: to steps, forskellige brikker, der bytter
/// plads (A→Bs felt og B→As felt). ÉN vagt for Move-objekter — brugt af
/// spilfladens routing og lyd-feedback — så reglen ikke findes i kopier, der
/// kan drive fra hinanden. (Log-map-udgaven bor i serialize.dart:
/// isSwapLogSteps.) Aldrig "2 steps = byt": sekvens-træk (+2−5), 1×1 og en
/// delt 7'er har også 2 steps.
bool isSwapMove(Move m) {
  if (m.steps.length != 2) return false;
  final MoveStep a = m.steps[0];
  final MoveStep b = m.steps[1];
  if (a.pieceId == b.pieceId) return false;
  return a.to == b.from && b.to == a.from;
}
