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

/// Ejeren ud af et brik-id.
///
/// Id'et dannes som `p<ejer>.<nummer>` af alle skrivere (app.dart,
/// online_service.dart, replay-motoren, selvtesten). Formatet er brikkens
/// egen kontrakt, så opslaget hører hjemme her — ikke i to kopier ude i
/// statistikken og replay-teksten.
///
/// DEFENSIV: statistikken parsede før med `split('.').first.substring(1)`,
/// som KASTER på et id uden 'p' eller uden punktum. Her er svaret null.
int? ownerOfPieceId(String? id) {
  if (id == null || id.length < 2 || !id.startsWith('p')) return null;
  final int dot = id.indexOf('.');
  return int.tryParse(dot < 0 ? id.substring(1) : id.substring(1, dot));
}
