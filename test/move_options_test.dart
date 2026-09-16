// Klassifikationen bag "kortet kan to ting — vælg én".
//
// BRUGERFUND: "når et kort har flere muligheder skal dialogen om hvilken man
// vælger være mere tydelig ... hvis man ikke vælger en af mulighederne men
// starter med at klikke på en brik, bliver brikken flyttet direkte, selv om
// man måske ønskede at f.eks. bytte 2 brikker".
//
// Reglen lå før regnet forfra TRE steder inde i spillefladen og kunne derfor
// ikke testes uden at rejse hele skærmen. Her er den ét sted.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/move_options.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';

const PlayingCard nine = PlayingCard(Rank.nine, Suit.spades);

/// Et byt: to skridt, to FORSKELLIGE brikker, der bytter plads.
Move swap() => const Move(card: nine, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.0', from: TrackPosition(3), to: TrackPosition(9)),
      MoveStep(pieceId: 'p1.0', from: TrackPosition(9), to: TrackPosition(3)),
    ]);

/// Et almindeligt fremadtræk.
Move fwd() => const Move(card: nine, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.1', from: TrackPosition(3), to: TrackPosition(12)),
    ]);

/// 1×1: to FORSKELLIGE brikker, ét felt hver.
Move multi() => const Move(card: nine, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.0', from: TrackPosition(5), to: TrackPosition(6)),
      MoveStep(pieceId: 'p0.1', from: TrackPosition(40), to: TrackPosition(41)),
    ]);

/// Sekvens (+2−5): to skridt, men SAMME brik. Den skelnen er hele pointen —
/// tælles der på `steps.length`, ser sekvensen ud som et fler-briks-træk.
Move seq() => const Move(card: nine, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.2', from: TrackPosition(3), to: TrackPosition(5)),
      MoveStep(pieceId: 'p0.2', from: TrackPosition(5), to: TrackPosition(60 - 1)),
    ]);

void main() {
  test('både byt og flyt → spilleren SKAL vælge', () {
    final MoveOptions o = MoveOptions.classify(<Move>[swap(), fwd()]);
    expect(o.hasSwap, isTrue);
    expect(o.hasOther, isTrue);
    expect(o.needsChoice, isTrue);
    expect(o.onlyOption, isNull, reason: 'der er intet at vælge FOR spilleren');
  });

  test('kun byt lovligt → intet at spørge om', () {
    // Samme kort, anden stilling. Klassifikationen skal komme af de træk,
    // motoren FANDT — ikke af kortets konfiguration. Et kort med swap:true
    // kan sagtens have nul lovlige byt lige nu.
    final MoveOptions o = MoveOptions.classify(<Move>[swap()]);
    expect(o.needsChoice, isFalse);
    expect(o.onlyOption, isTrue);
  });

  test('kun flyt lovligt → intet at spørge om', () {
    final MoveOptions o = MoveOptions.classify(<Move>[fwd(), fwd()]);
    expect(o.needsChoice, isFalse);
    expect(o.onlyOption, isFalse);
  });

  test('ingen lovlige træk → hverken valg eller automatisk valg', () {
    // Må ikke give onlyOption:false ("flyt"), for der ER intet at flytte.
    // Ellers ville fladen sætte en tilstand på et kort, der ikke kan bruges.
    final MoveOptions o = MoveOptions.classify(const <Move>[]);
    expect(o.hasSwap, isFalse);
    expect(o.hasOther, isFalse);
    expect(o.needsChoice, isFalse);
    expect(o.onlyOption, isNull);
  });

  test('genkender byt POSITIVT, ikke på "to skridt"', () {
    // Sekvens-kortet (+2−5) har også to skridt — men det er SAMME brik.
    // Uden den positive genkendelse ville et sekvenstræk blive talt som et
    // byt, og nieren ville tro den skulle spørge om noget.
    final Move seq = const Move(card: nine, steps: <MoveStep>[
      MoveStep(pieceId: 'p0.2', from: TrackPosition(11), to: TrackPosition(13)),
      MoveStep(pieceId: 'p0.2', from: TrackPosition(13), to: TrackPosition(8)),
    ]);
    final MoveOptions o = MoveOptions.classify(<Move>[seq]);
    expect(o.hasSwap, isFalse);
    expect(o.hasOther, isTrue);
    expect(o.needsChoice, isFalse);
  });

  // ---------------------------------------------------------------------
  // Brik-antal: skellet mellem "11 frem" og "1 frem med to brikker".
  // ---------------------------------------------------------------------

  test('piecesInMove tæller BRIKKER, ikke skridt', () {
    expect(piecesInMove(fwd()), 1);
    expect(piecesInMove(multi()), 2);
    // Kernen: sekvensen har TO skridt, men rører kun ÉN brik. Talte vi
    // steps.length, ville +2−5 blive læst som et fler-briks-træk, og
    // 25 års syver ville få et evne-valg, den ikke har.
    expect(seq().steps, hasLength(2));
    expect(piecesInMove(seq()), 1);
  });

  test('begge brik-antal til stede → der ER to slags træk at skelne', () {
    final MoveOptions o = MoveOptions.classify(<Move>[fwd(), multi()]);
    expect(o.hasSinglePiece, isTrue);
    expect(o.hasMultiPiece, isTrue);
    expect(o.hasBothPieceCounts, isTrue);
  });

  test('kun ét-briks-træk → intet brik-antal at vælge imellem', () {
    final MoveOptions o = MoveOptions.classify(<Move>[fwd(), seq()]);
    expect(o.hasSinglePiece, isTrue);
    expect(o.hasMultiPiece, isFalse,
        reason: 'sekvensen rører kun én brik');
    expect(o.hasBothPieceCounts, isFalse);
  });

  test('et BYT tæller ikke med i brik-antallet', () {
    // Byttet rører to brikker, men det er en tredje slags træk og har sin
    // egen knap. Talte det med her, ville en nier se ud som om den også
    // havde et fler-briks-træk.
    final MoveOptions o = MoveOptions.classify(<Move>[swap(), fwd()]);
    expect(o.hasMultiPiece, isFalse);
    expect(o.hasBothPieceCounts, isFalse);
  });
}
