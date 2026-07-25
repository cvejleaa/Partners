import '../../models/move.dart';
import '../../models/playing_card.dart';
import '../../models/game_state.dart';

/// AI-smarthed: 0 = Begynder (spiller kluntet, kan forære sit eneste
/// ud-af-start-kort væk), 1 = Normal, 2 = Skarp (bedste heuristik).
const int kAiSmartnessDefault = 1;

abstract class AiPlayer {
  /// Vælg det kort der skal byttes til partneren.
  PlayingCard chooseExchangeCard(GameState state, int playerIndex,
      {int smartness = kAiSmartnessDefault});

  /// Vælg et træk eller null hvis intet kort kan spilles (så smides et kort).
  Move? chooseMove(GameState state, int playerIndex,
      {int smartness = kAiSmartnessDefault});

  /// Hvis [chooseMove] returnerer null, hvilket kort skal kastes?
  PlayingCard chooseDiscard(GameState state, int playerIndex,
      {int smartness = kAiSmartnessDefault});
}
