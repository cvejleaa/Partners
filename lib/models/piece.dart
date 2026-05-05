import 'board.dart';

class Piece {
  Piece({
    required this.id,
    required this.ownerIndex,
    required this.position,
    this.hasLeftStart = false,
  });

  final String id;
  final int ownerIndex;
  PiecePosition position;

  /// Sand når brikken er kommet ud af start mindst én gang i denne runde.
  /// Bruges til at sikre, at man har "rejst en omgang" før hjemstræk er muligt.
  /// (Når brikken sættes ud på banen, sættes den til true; når den slås retur
  /// til start, sættes den til false.)
  bool hasLeftStart;

  Piece copy() => Piece(
        id: id,
        ownerIndex: ownerIndex,
        position: position,
        hasLeftStart: hasLeftStart,
      );
}
