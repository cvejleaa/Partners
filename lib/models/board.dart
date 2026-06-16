/// Brættets geometri.
///
/// Banen er en ren ring med [trackLength] felter (default 56 = 4 spillere ×
/// 14 nummererede felter). Ud-felterne ligger IKKE på ringen — de er kun en
/// visuel markering uden for ringen. Når en brik kommer ud af start, lander
/// den direkte på spillerens første nummererede felt (felt "1"), dvs.
/// ringindeks `playerIndex * 14` (0, 14, 28, 42). Et kort der flytter N felter,
/// flytter præcis N felter på ringen — ud-feltet tælles aldrig med.
/// Hjemstrækket har 4 felter.
class BoardGeometry {
  const BoardGeometry({this.trackLength = 56, this.homeStretchLength = 4});

  final int trackLength;
  final int homeStretchLength;

  int startTrackIndexFor(int playerIndex) =>
      (playerIndex * (trackLength ~/ 4)) % trackLength;

  /// Antal felter brik med playerIndex skal "have rejst" fra sit eget
  /// første felt for at være klar til at gå ind i hjemstrækket.
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

/// Ud-feltet (udgangsfelt) for en spiller — en lomme UDEN for ringen, lige før
/// spillerens felt 1. En brik der kommer ud af start lander her. Den er sikker:
/// andre spillere passerer den ikke og kan ikke slå en brik der. Et fremad-træk
/// på N rykker brikken fra ud-feltet ind på felt N (ud-felt + 1 = felt 1).
class ExitPosition extends PiecePosition {
  const ExitPosition(this.ownerIndex);
  final int ownerIndex; // 0..3

  @override
  bool operator ==(Object other) =>
      other is ExitPosition && other.ownerIndex == ownerIndex;

  @override
  int get hashCode => Object.hash('exit', ownerIndex);
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
