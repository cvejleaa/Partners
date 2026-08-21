import 'dart:ui' show Color;

import '../game/card_rules.dart';
import 'board.dart';
import 'playing_card.dart';

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
    this.description,
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
    this.cardRuleOverrides,
    this.tableColor = const Color(0xFF0E2A1A),
    this.feltColor = const Color(0xFF14331F),
    // Husets grønne (bruges også af "din tur"-chippen): hvid 13px-tekst har
    // 5,1:1 — 0xFF4CAF50 havde kun 2,8:1 og fejlede som informationsbærer.
    this.badgeColor = const Color(0xFF2E7D32),
  });

  /// Stabil identitet (gemmes i spil-dokumentet, se serialisering).
  final String id;
  final String name;

  /// Kort forklaring til variant-vælgeren (fx approksimations-forbehold).
  /// `null` for den selvforklarende klassiske udgave.
  final String? description;

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

  /// Variantens KODE-DEFINEREDE kort-ændringer som overrides oven på de LIVE/
  /// admin-konfigurerede regler. `null` = ingen ændringer (klassisk bruger
  /// admin-reglerne uændret). Dette er kun SEEDET: har admin gemt egne
  /// overrides for varianten (config/cardRules → variants.{id}.rules), vinder
  /// de over dette — se [effectiveCardRules], som er den ENESTE resolver.
  /// Resolves ved oprettelse ind i [GameState.cardRules] (kim), hvorefter
  /// spillets state er runtime-autoritet (kort serialiseres uafhængigt i 'cr',
  /// så en senere ændring rører ikke et igangværende spil).
  final Map<Rank, CardRuleConfig>? cardRuleOverrides;

  /// Variantens visuelle identitet i SPILLET (ambient bekræftelse — badgen
  /// bærer informationen, farven bekræfter den). Klassisk = de eksisterende
  /// grønne (defaults, byte-identisk); 25 år = marineblå som det fysiske sæts
  /// æske. [tableColor] = spil-skærmenes Scaffold-baggrund; [feltColor] =
  /// bræt-canvas + hånd-/status-fladerne. [badgeColor] er en TREDJE farve
  /// valgt til at være læsbar på app-krom (grøn/hvid baggrund) — bord-farverne
  /// selv har ~1,1:1 mod temaet og ville forsvinde som chip-farve.
  final Color tableColor;
  final Color feltColor;
  final Color badgeColor;

  /// Kort badge-etiket ("Klassisk"/"25 år") — det spillerne SIGER ved bordet.
  /// Falder tilbage til navnet for fremtidige varianter uden kort form.
  String get shortLabel =>
      id == 'classic' ? 'Klassisk' : (id == 'p25' ? '25 år' : name);

  /// Tekst til badge-info-dialogen. Domænetekst bor HER (ikke i widgets):
  /// beskrivelsen når den findes, ellers klassisk-forklaringen.
  String get infoText =>
      description ??
      'Den klassiske Partners-udgave: 4 spillere, 2 hold med diagonale '
          'makkere, 4 brikker hver.';

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

/// Partners 25 år (jubilæumsudgave). Strukturelt = klassisk (4 spillere, 2v2,
/// samme bræt), så den spiller og renderer som klassisk. Forskellen er
/// kortsættet: de fem specialkort, EJER-BEKRÆFTET mod det fysiske sæt (docs/
/// partners-varianter.md). Rang-mapping: kort-tal = rang. Bemærk at 4×1
/// ERSTATTER det klassiske 4-kort — 25 år har bekræftet intet −4; eneste
/// baglæns-bevægelse er 7-kortets +2−5. Resten arves fra de LIVE regler
/// (admin kan tilpasse alt; gemte overrides vinder over dette seed).
const VariantConfig partners25 = VariantConfig(
  id: 'p25',
  name: 'Partners 25 år',
  // Marineblå som den fysiske æske. Lysstyrke-MATCHET mod klassisk grøn
  // (relativ luminans 0,0178/0,0260 mod grønnens 0,0182/0,0262), så hvid
  // tekst/kontrast er uændret — men med nok kulør til at læses som blå selv
  // ved dæmpet skærm/nattilstand. (En mørkere navy ville miste kuløren.)
  tableColor: Color(0xFF15243F),
  feltColor: Color(0xFF1B2C4F),
  badgeColor: Color(0xFF3D6DDB),
  description: 'Jubilæumsudgavens fem specialkort — 7/+2−5, byt/9, 11/1×1, '
      '4×1 og 5↷ — er skrevet af efter det fysiske spil. Antallet af hvert '
      'kort er ikke talt op, så kortfordelingen er appens egen.',
  cardRuleOverrides: <Rank, CardRuleConfig>{
    // 4×1: fire enkelttræk fordelt på flere brikker (erstatter klassisk 4).
    Rank.four: CardRuleConfig(splitTotal: 4),
    // 5↷ Hopsakortet: 5 frem, må passere et blokeret startfelt.
    Rank.five: CardRuleConfig(forwardSteps: <int>[5], jumpsBlockade: true),
    // 7 ELLER +2−5: 7 frem, eller 2 frem og så 5 tilbage med samme brik.
    Rank.seven:
        CardRuleConfig(forwardSteps: <int>[7], seqForward: 2, seqBackward: 5),
    // Byt ELLER 9.
    Rank.nine: CardRuleConfig(forwardSteps: <int>[9], swap: true),
    // 11 ELLER 1×1: 11 frem, eller to brikker 1 felt frem hver.
    Rank.jack:
        CardRuleConfig(forwardSteps: <int>[11], multiPieces: 2, multiSteps: 1),
  },
);

/// Alle kendte varianter. Registret bruges til at resolve en gemt variant-id
/// tilbage til dens config og til at fylde variant-vælgeren.
const List<VariantConfig> kAllVariants = <VariantConfig>[
  classicVariant,
  partners25,
];

/// Slå en variant op på dens [id]. En manglende eller ukendt id (fx et
/// spil-dokument gemt FØR variant-feltet fandtes, eller en gammel log) resolver
/// til [classicVariant] — det er den hårde bagud-kompat-regel for serialisering.
VariantConfig variantFromId(String? id) {
  for (final VariantConfig v in kAllVariants) {
    if (v.id == id) return v;
  }
  return classicVariant;
}

/// Resolve varianten fra et spil-dokument. DEFENSIV: et 'variantId' der ikke er
/// en string (fx sat til et tal/map af en fjendtlig lobby-deltager) eller er
/// ukendt, klampes til klassisk — så et skævt felt aldrig kan vælte en start.
/// Ét sted, så de flere læsere (lobby-start, revanche, lobby-UI) ikke driver fra
/// hinanden.
VariantConfig variantFromDoc(Map<String, dynamic> doc) =>
    variantFromId(doc['variantId'] is String ? doc['variantId'] as String : null);

/// Den ENE resolver for et spils faktiske kortregler:
/// [base] (de live/admin-regler for klassisk) + variantens overrides ovenpå.
/// Precedens: admin-GEMTE overrides for varianten ([stored]) > variantens
/// kode-seed ([VariantConfig.cardRuleOverrides]) > ingen (klassisk = base
/// uændret). Kaldes ved spil-oprettelse (single-player og online) — motoren
/// og alle andre læser derefter kun [GameState.cardRules].
CardRules effectiveCardRules(
  VariantConfig variant,
  CardRules base, {
  Map<Rank, CardRuleConfig>? stored,
}) {
  final Map<Rank, CardRuleConfig>? overrides =
      stored ?? variant.cardRuleOverrides;
  return overrides == null ? base : base.withOverrides(overrides);
}

/// Rå `variants`-map fra config/cardRules-doc'et (eller lobby-doc'ets kopi
/// `cardRulesVariants`) → gemte overrides for [variantId]. DEFENSIV hele vejen:
/// ikke-map på ethvert niveau → null (fald til kode-seedet). Ren funktion, så
/// klampningen kan unit-testes.
Map<Rank, CardRuleConfig>? storedOverridesFor(
    dynamic variantsRaw, String variantId) {
  if (variantsRaw is! Map) return null;
  final dynamic entry = variantsRaw[variantId];
  if (entry is! Map) return null;
  final dynamic rules = entry['rules'];
  if (rules is! Map) return null;
  return cardRuleOverridesFromJson(Map<String, dynamic>.from(rules));
}

/// Admin kan gemme eget navn/beskrivelse for en variant (fx når 25 år-sættet
/// er afskrevet fra det fysiske spil og "(forsmag)"-forbeholdet ikke længere
/// er sandt). Reglen "admin-tekst vinder, men kun når udfyldt (trimmet)" bor
/// ÉT sted — [variantNameFrom]/[variantDescriptionFrom] — og genbruges af både
/// doc-læserne her og setup-skærmens controller-baserede visning, så de to
/// stier ikke driver fra hinanden.
String variantNameFrom(VariantConfig v, String? adminName) =>
    (adminName != null && adminName.trim().isNotEmpty)
        ? adminName.trim()
        : v.name;

String? variantDescriptionFrom(VariantConfig v, String? adminDescription) =>
    (adminDescription != null && adminDescription.trim().isNotEmpty)
        ? adminDescription.trim()
        : v.description;

/// Doc-læsende varianter (online-lobbyen): træk admin-teksten DEFENSIVT ud af
/// `variants`-mappet og anvend reglen ovenfor.
String variantDisplayName(VariantConfig v, dynamic variantsRaw) =>
    variantNameFrom(v, _metaString(variantsRaw, v.id, 'name'));

String? variantDisplayDescription(VariantConfig v, dynamic variantsRaw) =>
    variantDescriptionFrom(v, _metaString(variantsRaw, v.id, 'description'));

String? _metaString(dynamic variantsRaw, String id, String key) {
  if (variantsRaw is! Map) return null;
  final dynamic entry = variantsRaw[id];
  if (entry is! Map) return null;
  final dynamic value = entry[key];
  return value is String ? value : null;
}
