import '../game/card_rules.dart';
import 'board.dart';
import 'piece.dart';
import 'player.dart';
import 'playing_card.dart';
import 'variant_config.dart';

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
    this.starterIndex = 0,
    this.starterStreak = 0,
    List<int>? starterCounts,
    CardRules? cardRules,
    Map<int, PlayingCard?>? exchangeBuffer,
    Map<int, PlayingCard>? givenAway,
    Set<int>? sittingOut,
    VariantConfig? variant,
  })  : cardRules = cardRules ?? CardRules.defaults(),
        starterCounts = starterCounts ?? List<int>.filled(4, 0),
        exchangeBuffer = exchangeBuffer ?? <int, PlayingCard?>{},
        givenAway = givenAway ?? <int, PlayingCard>{},
        sittingOut = sittingOut ?? <int>{},
        variant = variant ?? classicVariant;

  final List<Player> players;
  final BoardGeometry geometry;
  final List<PlayingCard> deck;
  final List<PlayingCard> discard;
  int dealerIndex;
  int currentPlayerIndex;
  GamePhase phase;
  int handNumber;
  int? winningTeamIndex;

  /// Den spiller der starter runden (spiller først). Roterer med uret efter 3
  /// runder som startende.
  int starterIndex;
  int starterStreak;

  /// Hvor mange gange hver spiller har startet en runde (til visning).
  final List<int> starterCounts;

  /// Konfigurerbare kortregler (justeres på admin-skærmen).
  final CardRules cardRules;

  /// Gemmer det kort, hver spiller har valgt at bytte med sin partner, indtil
  /// alle har valgt og byttet kan udføres.
  final Map<int, PlayingCard?> exchangeBuffer;

  /// Hvad hver spiller GAV VÆK i byttet — og som modtageren altså har på
  /// hånden i denne runde.
  ///
  /// Eget felt, ikke en genbrug af [exchangeBuffer]. Bufferen ryddes med
  /// vilje, når byttet er afviklet, og FIRE steder uden for motoren læser den
  /// som "har denne spiller afgivet endnu?" (AI-afgivelse to steder,
  /// venter-på-teksten, og en ændrings-nøgle). De er alle låst inde i
  /// byttefasen i dag — men lod man bufferen stå fyldt ind i spillet, ville de
  /// afhænge af en usagt antagelse, ingen af dem selv udtrykker.
  ///
  /// Ryddes ved hver ny hånd, ligesom bufferen.
  final Map<int, PlayingCard> givenAway;

  /// Spillere der har SMIDT deres hånd (kunne ikke spille noget) og sidder over
  /// resten af runden. Adskiller sig fra en spiller der har lagt sit sidste
  /// kort (tom hånd, men ikke smidt). Nulstilles ved ny hånd.
  final Set<int> sittingOut;

  /// Hvilken Partners-udgave dette spil kører. Default [classicVariant], så et
  /// spil uden eksplicit variant opfører sig præcis som den klassiske motor.
  /// Motoren resolver hold/partner/brik-antal/vinder herfra i stedet for
  /// hardkodede tal.
  final VariantConfig variant;

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
        .where((Player p) => variant.teamOf(p.index) == teamIndex)
        .expand<Piece>((Player p) => p.pieces)
        .toList();
    return teamPieces.every((Piece p) => p.position is HomeStretchPosition);
  }
}
