// Hvad kan et kort GØRE lige nu? Ren klassifikation, ingen widgets.
//
// Ligger i lib/game/ og ikke i fladen af to grunde. For det første er det
// spil-logik: "kortet kan to ting" er en egenskab ved trækkene, ikke ved
// skærmen. For det andet — og det er den praktiske — kunne den samme regel
// ellers ikke testes uden at rejse hele spillefladen, og den blev derfor
// regnet forfra tre steder i widget'en (kort-valg, brik-tryk og
// highlightning), hvor de tre kopier kunne drive fra hinanden (QC-fund).
//
// Én vagt, ét sted: har kortet BÅDE byt og noget andet lovligt lige nu,
// kræver det et valg af spilleren — og indtil valget er truffet, må et tryk
// på en brik ikke gøre noget.

import '../models/move.dart';

/// Hvilke slags træk et kort tilbyder i den aktuelle stilling.
class MoveOptions {
  const MoveOptions({
    required this.hasSwap,
    required this.hasOther,
    this.hasSinglePiece = false,
    this.hasMultiPiece = false,
  });

  /// Udled af de træk, motoren faktisk har fundet lovlige — aldrig af
  /// kort-konfigurationen. Et kort kan have `swap: true` uden at der findes
  /// et eneste lovligt byt på brættet netop nu, og så er der intet at vælge
  /// imellem.
  factory MoveOptions.classify(List<Move> moves) {
    bool swap = false;
    bool other = false;
    bool single = false;
    bool multi = false;
    for (final Move m in moves) {
      if (isSwapMove(m)) {
        swap = true;
        continue;
      }
      other = true;
      if (piecesInMove(m) > 1) {
        multi = true;
      } else {
        single = true;
      }
    }
    return MoveOptions(
      hasSwap: swap,
      hasOther: other,
      hasSinglePiece: single,
      hasMultiPiece: multi,
    );
  }

  /// Findes der mindst ét lovligt BYT?
  final bool hasSwap;

  /// Findes der mindst ét lovligt træk, der ikke er et byt?
  final bool hasOther;

  /// Kan kortet bruges til to forskellige ting? Så SKAL spilleren vælge, og
  /// indtil da må ingenting ske ved et tryk på brættet.
  bool get needsChoice => hasSwap && hasOther;

  /// Findes der et træk, der kun rører ÉN brik? (Byt tæller ikke med.)
  final bool hasSinglePiece;

  /// Findes der et træk, der rører FLERE brikker? (Byt tæller ikke med.)
  final bool hasMultiPiece;

  /// Findes begge dele?
  ///
  /// ADVARSEL om hvad dette IKKE betyder. Det er ikke i sig selv "kortet kan
  /// to ting". På en delt syver er "7 på én brik" og "4+3 på to brikker" to
  /// måder at bruge SAMME evne — split-flowet stiller allerede det spørgsmål,
  /// brik for brik. Kalderen skal derfor først have afgjort, at kortet
  /// faktisk HAR to separate evner (fx 25 års knægt: 11 frem ELLER 1×1);
  /// først dér siger dette flag noget om et valg.
  bool get hasBothPieceCounts => hasSinglePiece && hasMultiPiece;

  /// Kun én mulighed — fladen kan vælge for spilleren uden at spørge.
  /// Null når der enten er valgfrihed eller slet ingen træk.
  bool? get onlyOption {
    if (needsChoice) return null;
    if (hasSwap) return true; // kun byt
    if (hasOther) return false; // kun flyt
    return null; // ingen lovlige træk
  }
}

/// Hvor mange FORSKELLIGE brikker rører et træk?
///
/// Ikke `steps.length`: et sekvens-træk (+2−5) har to steps på samme brik og
/// rører altså kun én. Det er netop den forskel, der skiller "11 frem" fra
/// "1 frem med to brikker".
int piecesInMove(Move m) =>
    <String>{for (final MoveStep s in m.steps) s.pieceId}.length;
