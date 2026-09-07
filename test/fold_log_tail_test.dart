// foldLogTail (lib/ui/screens/online_game_screen.dart) — den inkrementelle
// erstatning for den gamle _parseLog, som genscannede HELE spillets log ved
// hvert build (forbrugs-fund #65: O(spillængde²) arbejde på tværs af et
// partis levetid). Her testes den RENE fold-regel (uden Firebase/widget):
// et nyt kald skal give samme resultat som en fuld genscanning ville, uden
// at miste ældre indlæg der ikke er i den nye "hale".

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/ui/screens/online_game_screen.dart';

Map<String, dynamic> _move(int player, PlayingCard card) =>
    <String, dynamic>{'type': 'move', 'player': player, 'card': cardToMap(card)};

const _fourHearts = PlayingCard(Rank.four, Suit.hearts);
const _kingSpades = PlayingCard(Rank.king, Suit.spades);
const _aceClubs = PlayingCard(Rank.ace, Suit.clubs);

void main() {
  group('foldLogTail — inkrementel erstatning for fuld log-scanning', () {
    test('en enkelt hale giver samme resultat som en fuld scanning ville', () {
      final result = foldLogTail(
        <Map<String, dynamic>>[_move(0, _fourHearts), _move(1, _kingSpades)],
        <int, PlayingCard>{},
      );
      expect(result, <int, PlayingCard>{0: _fourHearts, 1: _kingSpades});
    });

    test('bygger videre på et tidligere resultat — mister ikke ældre spillere', () {
      // Kernen i optimeringen: kaldes med KUN de nye indlæg, ikke hele
      // loggen forfra. MUTATION: start altid fra {} → spiller 0's kort
      // ville forsvinde, selvom spiller 0 ikke har spillet siden.
      final afterFirstBuild =
          foldLogTail(<Map<String, dynamic>>[_move(0, _fourHearts)], <int, PlayingCard>{});
      final afterSecondBuild =
          foldLogTail(<Map<String, dynamic>>[_move(1, _kingSpades)], afterFirstBuild);
      expect(afterSecondBuild, <int, PlayingCard>{0: _fourHearts, 1: _kingSpades});
    });

    test('samme spiller igen OVERSKRIVER det forrige kort, den fjerner det ikke', () {
      final result = foldLogTail(
        <Map<String, dynamic>>[_move(0, _kingSpades)],
        <int, PlayingCard>{0: _fourHearts},
      );
      expect(result, <int, PlayingCard>{0: _kingSpades});
    });

    test('ikke-move-indlæg (fx exchange) ændrer ingenting', () {
      final result = foldLogTail(
        <Map<String, dynamic>>[
          <String, dynamic>{'type': 'exchange', 'player': 0},
        ],
        <int, PlayingCard>{1: _aceClubs},
      );
      expect(result, <int, PlayingCard>{1: _aceClubs});
    });

    test('tom hale er en no-op — returnerer det tidligere resultat uændret', () {
      final previous = <int, PlayingCard>{0: _fourHearts};
      expect(foldLogTail(<Map<String, dynamic>>[], previous), previous);
    });
  });

  group('advanceLogCache — skærmens cache-beslutning (Test Manager-fund)', () {
    final log2 = <Map<String, dynamic>>[_move(0, _fourHearts), _move(1, _kingSpades)];

    test('første build folder hele loggen fra 0', () {
      final r = advanceLogCache(log2, <int, PlayingCard>{}, 0);
      expect(r.lastByPlayer, <int, PlayingCard>{0: _fourHearts, 1: _kingSpades});
      expect(r.logLen, 2);
    });

    test('samme længde → identisk cache tilbage, ingen ny fold', () {
      final cache = <int, PlayingCard>{0: _fourHearts, 1: _kingSpades};
      final r = advanceLogCache(log2, cache, 2);
      expect(identical(r.lastByPlayer, cache), isTrue);
      expect(r.logLen, 2);
    });

    test('vokset log → kun halen foldes oven på cachen', () {
      final cache = <int, PlayingCard>{0: _fourHearts, 1: _kingSpades};
      final log3 = <Map<String, dynamic>>[...log2, _move(0, _aceClubs)];
      final r = advanceLogCache(log3, cache, 2);
      expect(r.lastByPlayer, <int, PlayingCard>{0: _aceClubs, 1: _kingSpades});
      expect(r.logLen, 3);
    });

    test('KRYMPET log → cachen bygges forfra af den korte log, ikke fra sublist', () {
      // MUTATION: fjern `log.length < previousLen`-værnet → `from` bliver
      // stående på 2 > log.length, folden kører aldrig, og den GAMLE cache
      // (med spiller 1, som ikke findes i den nye log) returneres uændret.
      final cache = <int, PlayingCard>{0: _fourHearts, 1: _kingSpades};
      final log1 = <Map<String, dynamic>>[_move(0, _aceClubs)];
      final r = advanceLogCache(log1, cache, 2);
      expect(r.lastByPlayer, <int, PlayingCard>{0: _aceClubs});
      expect(r.logLen, 1);
    });
  });
}
