import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/variant_config.dart';

// Tekst og afstand til trækvalg, paneler og byttefase — rene funktioner af
// spillets state, så de kan testes uden widgets. Det meste gør først en
// forskel i varianter, hvor en spiller styrer flere pladser (Duo).

/// Den lige vej [from]→[to] i tællende felter (UD tæller ikke, §6). Uden
/// tilbageslag i målet er det kortets afstand.
int straightStepDistance(
    GameState state, PiecePosition from, PiecePosition to) {
  final int len = state.geometry.trackLength;
  final int q = len ~/ state.geometry.segments;
  if (from is TrackPosition && to is TrackPosition) {
    int idx = from.index;
    int count = 0;
    while (idx != to.index && count <= len) {
      idx = (idx + 1) % len;
      if (idx % q == 0) continue; // UD-felt: tæller ikke
      count++;
      if (idx == to.index) break;
    }
    return count;
  }
  if (from is TrackPosition && to is HomeStretchPosition) {
    final int entry = state.geometry.startTrackIndexFor(to.ownerIndex);
    int idx = from.index;
    int count = 0;
    // Gå frem til feltet lige før ejerens eget UD (entry); UD-felter
    // undervejs tæller ikke. Drej så ind i hjemstrækket: +1 for at nå slot 0
    // og + slot for resten.
    while (count <= len) {
      final int next = (idx + 1) % len;
      if (next == entry) return count + to.slot + 1;
      idx = next;
      if (idx % q == 0) continue; // fremmed UD
      count++;
    }
    return count + to.slot + 1;
  }
  if (from is HomeStretchPosition && to is HomeStretchPosition) {
    return to.slot - from.slot;
  }
  return 0;
}

/// Kortets afstand for et step: motorens tal i varianter med tilbageslag
/// (dér afslører fra→til ikke afstanden), ellers den lige vej.
int stepDistance(GameState state, MoveStep s) {
  if (state.variant.goalBounce && s.distance != null) return s.distance!;
  return straightStepDistance(state, s.from, s.to);
}

/// Duo: et træk, der slår tilbage i målet, beskrives med kortets afstand
/// og ordet "baglæns" — ellers ville "hjem (felt 2)" eller "1 tilbage"
/// skjule, at hele kortet blev brugt. Genkendes positivt: motoren oplyser
/// afstanden, og den passer ikke med den lige vej fra→til. null = ikke et
/// tilbageslag.
String? describeBounce(GameState state, MoveStep s) {
  final int? d = s.distance;
  if (!state.variant.goalBounce || d == null) return null;
  if (s.from is StartPosition) return null;
  if (straightStepDistance(state, s.from, s.to) == d) return null;
  final to = s.to;
  return to is HomeStretchPosition
      ? '$d frem — baglæns til målfelt ${to.slot + 1}'
      : '$d frem — baglæns ud af målet igen';
}

/// Hvem byttekortet går til, som det står i byttefasen.
String exchangeTargetLabel(VariantConfig v) =>
    v.exchangeRule == ExchangeRule.opponentSwap ? 'din modstander' : 'din makker';

/// Navnet på brikkens ejer i trækteksterne. Styrer en spiller to sæt i samme
/// farve og med samme navn (Duo), ville et byt ellers stå som "Byt
/// Anna-brikken med Anna-brikken". Klassisk: bare navnet.
String pieceOwnerLabel(GameState state, Piece piece) {
  final VariantConfig v = state.variant;
  final String name = state.players[piece.ownerIndex].name;
  if (!v.seatsShareController) return name;
  return v.hasHand(piece.ownerIndex) ? '$name (ring)' : '$name (prik)';
}

/// "○ x/3 · ● y/3" — brikker i mål for hvert sæt, [p] styrer (ring = sættet
/// ved hånd-pladsen, prik = det andet). null for klassisk, for håndløse
/// pladser (de har intet panel) og hvis [p] ikke styrer præcis to sæt.
String? setProgressLabel(GameState state, Player p) {
  final VariantConfig v = state.variant;
  if (!v.seatsShareController || !v.hasHand(p.index)) return null;
  final List<int> seats = v.seatsControlledBy(p.index);
  if (seats.length != 2) return null;
  final int other = seats.firstWhere((int s) => s != p.index);
  assert(other >= 0);
  final int total = v.piecesPerPlayer;
  int home(int seat) => state.players[seat].pieces
      .where((Piece pc) => pc.position is HomeStretchPosition)
      .length;
  return '○ ${home(p.index)}/$total · ● ${home(p.index)}/$total';
}

/// Navnene i "Venter på: …" i byttefasen — kun pladser med en hånd (en
/// håndløs plads afgiver intet og må ikke stå som en ekstra "Anna").
List<String> exchangeWaitingNames(GameState state) => <String>[
      for (final Player p in state.players)
        if (state.variant.hasHand(p.index) &&
            !state.exchangeBuffer.containsKey(p.index))
          p.name,
    ];

/// Vindernes pladser, én pr. SPILLER: hånd-pladserne på vinderholdet (Duo:
/// kun den plads, der styrer begge sæt — ikke "Anna og Anna").
List<int> winnerSeats(GameState state, int winningTeam) => <int>[
      for (int i = 0; i < state.players.length; i++)
        if (i % 2 == winningTeam && state.variant.hasHand(i)) i,
    ];
