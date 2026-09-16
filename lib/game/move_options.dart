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
  const MoveOptions({required this.hasSwap, required this.hasOther});

  /// Udled af de træk, motoren faktisk har fundet lovlige — aldrig af
  /// kort-konfigurationen. Et kort kan have `swap: true` uden at der findes
  /// et eneste lovligt byt på brættet netop nu, og så er der intet at vælge
  /// imellem.
  factory MoveOptions.classify(List<Move> moves) {
    bool swap = false;
    bool other = false;
    for (final Move m in moves) {
      if (isSwapMove(m)) {
        swap = true;
      } else {
        other = true;
      }
      if (swap && other) break;
    }
    return MoveOptions(hasSwap: swap, hasOther: other);
  }

  /// Findes der mindst ét lovligt BYT?
  final bool hasSwap;

  /// Findes der mindst ét lovligt træk, der ikke er et byt?
  final bool hasOther;

  /// Kan kortet bruges til to forskellige ting? Så SKAL spilleren vælge, og
  /// indtil da må ingenting ske ved et tryk på brættet.
  bool get needsChoice => hasSwap && hasOther;

  /// Kun én mulighed — fladen kan vælge for spilleren uden at spørge.
  /// Null når der enten er valgfrihed eller slet ingen træk.
  bool? get onlyOption {
    if (needsChoice) return null;
    if (hasSwap) return true; // kun byt
    if (hasOther) return false; // kun flyt
    return null; // ingen lovlige træk
  }
}
