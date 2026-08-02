import '../models/board.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/player.dart';

/// Hvor mange TÆLLENDE felter en brik mangler for at nå sit hjemstræk (= være
/// "færdig", jf. GameState.teamHasWon som kun kræver at brikken er i
/// hjemstrækket). En brik der allerede er i hjemstrækket mangler 0.
///
/// Bruges til margin-statistikken: "vundet/tabt med N felter".
int fieldsToFinish(BoardGeometry geo, int owner, PiecePosition pos) {
  final int len = geo.trackLength;
  final int quarter = len ~/ 4;
  final int entry = (owner * quarter) % len;

  if (pos is HomeStretchPosition) return 0;

  // Fra eget UD hele ringen rundt (UD-felter tæller ikke) + 1 ind i hjem.
  final int fromEntry = (len - 4) + 1; // 60-ring → 57

  if (pos is StartPosition) {
    // Skal først ud af start (1) og derefter hele vejen rundt.
    return 1 + fromEntry;
  }

  if (pos is TrackPosition) {
    int idx = pos.index;
    int count = 0;
    for (int step = 0; step <= len; step++) {
      final int next = (idx + 1) % len;
      if (next == entry) return count + 1; // drej ind i hjem
      idx = next;
      if (idx % quarter == 0) continue; // fremmed UD tæller ikke
      count++;
    }
    return count;
  }
  return 0;
}

/// Samlet antal felter et hold mangler for at være helt i mål.
int teamFieldsToFinish(GameState state, int teamIndex) {
  int sum = 0;
  for (final Player p in state.players) {
    if (p.teamIndex != teamIndex) continue;
    for (final Piece pc in p.pieces) {
      sum += fieldsToFinish(state.geometry, p.index, pc.position);
    }
  }
  return sum;
}

/// Margin for et afsluttet spil: hvor mange felter det TABENDE hold manglede.
/// Vinderne "vandt med" dette tal; taberne "tabte med" samme tal. Returnerer
/// null hvis spillet ikke er afgjort.
int? winMarginFields(GameState state) {
  final int? winner = state.winningTeamIndex;
  if (winner == null) return null;
  final int loser = winner == 0 ? 1 : 0;
  return teamFieldsToFinish(state, loser);
}
