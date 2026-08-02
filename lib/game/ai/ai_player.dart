import '../../models/move.dart';
import '../../models/playing_card.dart';
import '../../models/game_state.dart';

/// Parametrene der DEFINERER en AI-sværhedsgrad. Admin kan justere dem, så de
/// tre grader kan finpudses uden kodeændring/deploy. Spilleren vælger selv
/// hvilken grad AI-modstanderne skal spille på, når et spil startes.
class AiParams {
  const AiParams({
    required this.noise,
    required this.randomMoveChance,
    required this.protectExitCard,
  });

  /// Støj-amplitude i træk-vurderingen. 0 = vælger altid det bedste træk;
  /// højere = mere kluntede/tilfældige valg.
  final double noise;

  /// Sandsynlighed (0..1) for at vælge et helt TILFÆLDIGT lovligt træk i
  /// stedet for det bedst vurderede.
  final double randomMoveChance;

  /// Om AI'en beholder sit eneste "ud af start"-kort i byttet (true = klog:
  /// forærer det ikke væk og undgår at sidde over).
  final bool protectExitCard;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'noise': noise,
        'randomMoveChance': randomMoveChance,
        'protectExitCard': protectExitCard,
      };

  factory AiParams.fromJson(Map<String, dynamic> j) => AiParams(
        noise: (j['noise'] as num?)?.toDouble() ?? 5.0,
        randomMoveChance: (j['randomMoveChance'] as num?)?.toDouble() ?? 0.0,
        protectExitCard: j['protectExitCard'] as bool? ?? true,
      );

  AiParams copyWith({
    double? noise,
    double? randomMoveChance,
    bool? protectExitCard,
  }) =>
      AiParams(
        noise: noise ?? this.noise,
        randomMoveChance: randomMoveChance ?? this.randomMoveChance,
        protectExitCard: protectExitCard ?? this.protectExitCard,
      );
}

/// Standard-parametre for de tre grader (bruges hvis admin intet har sat).
const AiParams kAiBegynder =
    AiParams(noise: 18.0, randomMoveChance: 0.35, protectExitCard: false);
const AiParams kAiNormal =
    AiParams(noise: 5.0, randomMoveChance: 0.0, protectExitCard: true);
const AiParams kAiSkarp =
    AiParams(noise: 1.0, randomMoveChance: 0.0, protectExitCard: true);

const List<AiParams> kDefaultAiLevels = <AiParams>[
  kAiBegynder,
  kAiNormal,
  kAiSkarp,
];
const List<String> kAiLevelNames = <String>['Begynder', 'Normal', 'Skarp'];

/// Standard-grad (Normal) hvis intet er valgt for et spil.
const int kAiLevelDefault = 1;

abstract class AiPlayer {
  /// Vælg det kort der skal byttes til partneren.
  PlayingCard chooseExchangeCard(GameState state, int playerIndex,
      {AiParams params = kAiNormal});

  /// Vælg et træk eller null hvis intet kort kan spilles (så smides et kort).
  Move? chooseMove(GameState state, int playerIndex,
      {AiParams params = kAiNormal});

  /// Hvis [chooseMove] returnerer null, hvilket kort skal kastes?
  PlayingCard chooseDiscard(GameState state, int playerIndex,
      {AiParams params = kAiNormal});
}
