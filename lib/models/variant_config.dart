import 'board.dart';

/// Hvordan kort-byttet mellem spillere fungerer i en variant.
///
/// Kun [partnerSwap] (klassisk makkerbyt) er implementeret i motoren i fase 1;
/// de øvrige er sømme til senere varianter (Duo, Trio, Partners+ 3v3).
enum ExchangeRule {
  /// Klassisk: byt 1 kort skjult med sin diagonale makker.
  partnerSwap,

  /// Duo: byt 1 kort med modstanderen.
  opponentSwap,

  /// Partners+ 3v3: send 1 kort til holdkammeraten nærmest med uret.
  clockwiseTeammate,

  /// Trio: cirkulær videregivelse — giv 1 videre, modtag 1 fra en anden.
  circularPass,

  /// Ingen bytte.
  none,
}

/// Hvornår et spil er vundet.
enum WinCondition {
  /// Klassisk/Partners+: alle et holds brikker i mål.
  teamAllHome,

  /// Duo/Trio: en enkelt spillers egne brikker i mål.
  ownAllHome,
}

/// Deklarativ beskrivelse af én Partners-udgave oven på den fælles motor.
///
/// Formålet er at flytte de antagelser, der før var hardkodet (4 spillere, 2
/// diagonale hold, 4 brikker, 60 felter …), ud i data — så nye udgaver kan
/// tilføjes uden at ændre den klassiske motor. Klassisk er selv udtrykt som
/// [classicVariant], og ALLE defaults er sat lig de tidligere konstanter, så en
/// build der blot indfører dette lag ikke kan ændre klassisk opførsel.
class VariantConfig {
  const VariantConfig({
    required this.id,
    required this.name,
    this.playerCount = 4,
    this.teams = const <List<int>>[
      <int>[0, 2],
      <int>[1, 3],
    ],
    this.piecesPerPlayer = 4,
    this.segments = 4,
    this.fieldsPerSegment = 14,
    this.goalCircles = 4,
    this.handSize = 4,
    this.dealsPerDealer = 3,
    this.exchangeRule = ExchangeRule.partnerSwap,
    this.forcedPlay = false,
    this.winCondition = WinCondition.teamAllHome,
    this.destinationsPerPlayer = 1,
  });

  /// Stabil identitet (gemmes i spil-dokumentet, se serialisering).
  final String id;
  final String name;

  final int playerCount;

  /// Sæde-grupper (hold). Tom liste = alle mod alle (hver spiller sit eget
  /// "hold"). Klassisk: `[[0,2],[1,3]]` — diagonale makkere.
  final List<List<int>> teams;

  final int piecesPerPlayer;

  /// Lige store ringsegmenter = antal UD-felter/indgange (4 klassisk, 6 plus).
  final int segments;

  /// Nummererede felter pr. segment (14 klassisk/25-år/Travel, 13 Partners+).
  final int fieldsPerSegment;

  /// Antal målcirkler pr. destination (= [BoardGeometry.homeStretchLength]).
  final int goalCircles;

  final int handSize;
  final int dealsPerDealer;
  final ExchangeRule exchangeRule;

  /// Duo: streng spillepligt (kan tvinges til at slå egen brik hjem).
  final bool forcedPlay;

  final WinCondition winCondition;

  /// Duo: 2 briktyper med hver sin start/destination. 1 for alle andre.
  final int destinationsPerPlayer;

  /// Samlet antal felter på ringen: segmenter × (UD-felt + nummererede felter).
  /// Klassisk: 4 × (1 + 14) = 60. Partners+: 6 × (1 + 13) = 84.
  int get trackLength => segments * (fieldsPerSegment + 1);

  /// Brættets geometri udledt af varianten. For klassisk er dette felt-for-felt
  /// lig `const BoardGeometry()` (60 / 4 / segments 4).
  BoardGeometry get geometry => BoardGeometry(
        trackLength: trackLength,
        homeStretchLength: goalCircles,
        segments: segments,
      );

  /// Holdindekset for et sæde. Ved "alle mod alle" (ingen hold) er hver spiller
  /// sit eget hold, så sædet returneres som sit eget holdindeks.
  int teamOf(int seat) {
    for (int i = 0; i < teams.length; i++) {
      if (teams[i].contains(seat)) return i;
    }
    return seat;
  }

  /// Alle sæder på samme hold som [seat] (inkl. seat selv). Uden hold: `[seat]`.
  List<int> teammatesOf(int seat) {
    for (final List<int> group in teams) {
      if (group.contains(seat)) return group;
    }
    return <int>[seat];
  }

  /// Den ENE makker for [seat] i en 2-mands-holdopsætning (klassisk makkerbyt).
  /// Findes ingen makker (alle mod alle), returneres [seat] selv.
  int partnerFor(int seat) {
    for (final int mate in teammatesOf(seat)) {
      if (mate != seat) return mate;
    }
    return seat;
  }
}

/// Den klassiske 4-spiller-udgave, udtrykt som variant. Bruges som default
/// overalt, så et spil uden eksplicit variant opfører sig præcis som før.
const VariantConfig classicVariant = VariantConfig(
  id: 'classic',
  name: 'Partners',
);

/// Alle kendte varianter (indtil videre kun klassisk). Registret bruges til at
/// resolve en gemt variant-id tilbage til dens config.
const List<VariantConfig> kAllVariants = <VariantConfig>[classicVariant];

/// Slå en variant op på dens [id]. En manglende eller ukendt id (fx et
/// spil-dokument gemt FØR variant-feltet fandtes, eller en gammel log) resolver
/// til [classicVariant] — det er den hårde bagud-kompat-regel for serialisering.
VariantConfig variantFromId(String? id) {
  for (final VariantConfig v in kAllVariants) {
    if (v.id == id) return v;
  }
  return classicVariant;
}
