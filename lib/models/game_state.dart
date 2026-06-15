import '../game/card_rules.dart';
import 'board.dart';
import 'piece.dart';
import 'player.dart';
import 'playing_card.dart';

enum GamePhase { setup, exchange, play, handOver, gameOver }

class GameState {
  GameState({
    required this.players,
    required this.geometry,
    required this.deck,
    required this.discard,
    required this.dealerIndex,
    required this.currentPlayerIndex,
    required this.phase,
    required this.handNumber,
    this.winningTeamIndex,
    CardRules? cardRules,
    Map<int, PlayingCard?>? exchangeBuffer,
  })  : cardRules = cardRules ?? CardRules.defaults(),
        exchangeBuffer = exchangeBuffer ?? <int, PlayingCard?>{};

  final List<Player> players;
  final BoardGeometry geometry;
  final List<PlayingCard> deck;
  final List<PlayingCard> discard;
  int dealerIndex;
  int currentPlayerIndex;
  GamePhase phase;
  int handNumber;
  int? winningTeamIndex;

  /// Konfigurerbare kortregler (justeres på admin-skærmen).
  final CardRules cardRules;

  /// Gemmer det kort, hver spiller har valgt at bytte med sin partner, indtil
  /// alle har valgt og byttet kan udføres.
  final Map<int, PlayingCard?> exchangeBuffer;

  Iterable<Piece> get allPieces =>
      players.expand<Piece>((Player p) => p.pieces);

  Piece? pieceAt(PiecePosition position) {
    for (final Piece p in allPieces) {
      if (p.position == position) return p;
    }
    return null;
  }

  /// Alle brikker på et felt (kan være en stak af egne brikker).
  List<Piece> piecesAt(PiecePosition position) =>
      allPieces.where((Piece p) => p.position == position).toList();

  /// Et felt er "beskyttet" (en dobbelt) når der står 2+ brikker på det.
  /// Beskyttede brikker kan ikke slås hjem eller byttes.
  bool isProtected(PiecePosition position) => piecesAt(position).length >= 2;

  Piece pieceById(String id) =>
      allPieces.firstWhere((Piece p) => p.id == id);

  Player get currentPlayer => players[currentPlayerIndex];

  int get nextPlayerIndex => (currentPlayerIndex + 1) % players.length;

  /// Spilleren har vundet for sit hold når både egne brikker og partnerens
  /// brikker alle er i mål (slot 0..3 i hjemstrækket).
  bool teamHasWon(int teamIndex) {
    final List<Piece> teamPieces = players
        .where((Player p) => p.teamIndex == teamIndex)
        .expand<Piece>((Player p) => p.pieces)
        .toList();
    return teamPieces.every((Piece p) => p.position is HomeStretchPosition);
  }
}
