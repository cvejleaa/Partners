/// Brættets geometri.
///
/// Banen er en ring med [trackLength] felter (default 60 = 4 spillere ×
/// (1 UD-felt + 14 nummererede felter)). UD-felterne ligger PÅ ringen ved
/// indeks 0, 15, 30, 45 — dvs. som ringens første felt for hver spiller.
/// Brikker der kommer ud af start lander på spillerens UD-felt
/// (TrackPosition(playerIndex*15)). De næste felter på ringen er felt 1..14.
/// Hjemstrækket har 4 felter og drejes der ind i når brikken er gået en
/// hel omgang og vender tilbage til sit eget UD-felt.
class BoardGeometry {
  const BoardGeometry({
    this.trackLength = 60,
    this.homeStretchLength = 4,
    this.segments = 4,
  });

  final int trackLength;
  final int homeStretchLength;

  /// Antal lige store ringsegmenter = antal UD-felter/indgange på banen. 4 for
  /// klassisk (60/4 = 15 felter pr. segment inkl. UD-feltet), 6 for Partners+.
  /// Default 4 gør `trackLength ~/ segments == trackLength ~/ 4` — dvs. helt
  /// identisk med den tidligere hardcodede firdeling.
  final int segments;

  int startTrackIndexFor(int playerIndex) =>
      (playerIndex * (trackLength ~/ segments)) % trackLength;

  /// Antal felter brik med playerIndex skal "have rejst" fra sit eget
  /// UD-felt for at være klar til at gå ind i hjemstrækket.
  int get fullLap => trackLength;
}

/// Brikkens placering. En brik er enten i sin start-bås, ude på banen eller i
/// hjemstrækket.
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
