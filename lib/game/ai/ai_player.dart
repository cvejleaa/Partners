import '../../models/move.dart';
import '../../models/playing_card.dart';
import '../../models/game_state.dart';

abstract class AiPlayer {
  /// Vælg det kort der skal byttes til partneren.
  PlayingCard chooseExchangeCard(GameState state, int playerIndex);

  /// Vælg et træk eller null hvis intet kort kan spilles (så smides et kort).
  Move? chooseMove(GameState state, int playerIndex);

  /// Hvis [chooseMove] returnerer null, hvilket kort skal kastes?
  PlayingCard chooseDiscard(GameState state, int playerIndex);
}
