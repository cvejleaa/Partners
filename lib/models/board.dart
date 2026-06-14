/// Brættets geometri.
///
/// Banen er en ring med [trackLength] felter (default 60 = 4 udgangsfelter +
/// 14 mellemfelter mellem hver). Hver spiller har et udgangsfelt på
/// `playerIndex * 15` (dvs. 0, 15, 30, 45). Hjemstrækket har 4 felter.
class BoardGeometry {
  const BoardGeometry({this.trackLength = 60, this.homeStretchLength = 4});

  final int trackLength;
  final int homeStretchLength;

  int startTrackIndexFor(int playerIndex) =>
      (playerIndex * (trackLength ~/ 4)) % trackLength;

  /// Antal felter brik med playerIndex skal "have rejst" fra sit eget
  /// udgangsfelt for at være klar til at gå ind i hjemstrækket.
  int get fullLap => trackLength;
}

/// Brikkens placering. En brik er enten i sin start-bås, ude på banen, i
/// hjemstrækket eller (efter spillets logik) den sidste hjem-position.
sealed class PiecePosition {
  const PiecePosition();
}

class StartPosition extends PiecePosition {
  const StartPosition(this.ownerIndex, this.slot);
  final int ownerIndex; // 0..3
  final int slot; // 0..3

  @override
  bool operator ==(Object other) =>
      other is StartPosition &&
      other.ownerIndex == ownerIndex &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash('start', ownerIndex, slot);
}

class TrackPosition extends PiecePosition {
  const TrackPosition(this.index);
  final int index; // 0..trackLength-1

  @override
  bool operator ==(Object other) =>
      other is TrackPosition && other.index == index;

  @override
  int get hashCode => Object.hash('track', index);
}

class HomeStretchPosition extends PiecePosition {
  const HomeStretchPosition(this.ownerIndex, this.slot);
  final int ownerIndex; // 0..3
  final int slot; // 0..homeStretchLength-1, 0 = nærmest indgang

  @override
  bool operator ==(Object other) =>
      other is HomeStretchPosition &&
      other.ownerIndex == ownerIndex &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash('home', ownerIndex, slot);
}
