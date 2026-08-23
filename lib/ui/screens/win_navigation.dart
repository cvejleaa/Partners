import 'dart:async';
import 'dart:typed_data';

/// Orkestrering af "spillet er slut → vis sejrsskærmen", udskilt fra
/// spilskærmene så den kan testes uden Firestore og uden at montere spilfladen.
///
/// FEJLEN DEN RETTER (rapporteret fra produktion: kun den spiller der lagde
/// det afsluttende træk så fejringen): guard-flaget blev sat FØR den
/// asynkrone hale (vent → fang brætbillede → naviger). Nåede halen ikke
/// igennem, blev klienten hængende på brættet for altid — låsen var brændt,
/// og `status:'over'` er den SIDSTE skrivning til spil-doc'et, så der kommer
/// aldrig et nyt snapshot at prøve på. Netop de spillere der IKKE trak, har
/// typisk appen i baggrunden, hvor `toImage()` aldrig får en frame og derfor
/// venter i det uendelige.
///
/// Kontrakten her — hvert punkt er låst af en test:
///  1. låsen sættes FØRST når navigationen faktisk er udført,
///  2. brætbilledet har en TIMEOUT og er valgfrit (billedet er pynt,
///     fejringen er pointen),
///  3. et mislykket forsøg må prøves igen ved næste rebuild,
///  4. et lykkedes forsøg gentages aldrig.
class WinNavigator {
  WinNavigator({
    this.settleDelay = const Duration(milliseconds: 560),
    this.captureLimit = const Duration(seconds: 2),
  });

  /// Ventetid så brik-animationen (480 ms) er faldet til ro, før billedet
  /// tages — ellers viser det et øjebliksbillede midt i bevægelsen.
  final Duration settleDelay;

  /// Loft på brætbilledet. En baggrundsfane tegner ingen frames, så
  /// `toImage()` kan vente for evigt; uden dette loft nås navigationen aldrig.
  final Duration captureLimit;

  bool _navigated = false;
  bool _running = false;

  /// True når sejrsskærmen ER vist (så senere rebuilds ikke gør det igen).
  bool get navigated => _navigated;

  /// Kør ét forsøg. Returnerer true hvis navigationen blev udført.
  ///
  /// [stillMounted] tjekkes efter hver await — skærmen kan være revet ned
  /// undervejs (fx når livscyklus-håndteringen genindlæser strømmen).
  Future<bool> run({
    required bool gameOver,
    required bool Function() stillMounted,
    required Future<Uint8List?> Function() capture,
    required void Function(Uint8List? boardImage) navigate,
  }) async {
    if (!gameOver || _navigated || _running) return false;
    _running = true;
    try {
      await Future<void>.delayed(settleDelay);
      if (!stillMounted()) return false;
      Uint8List? shot;
      try {
        shot = await capture().timeout(captureLimit);
      } catch (_) {
        // Timeout eller fejl: fejringen vises UDEN billede frem for slet ikke.
        shot = null;
      }
      if (!stillMounted()) return false;
      navigate(shot);
      _navigated = true;
      return true;
    } finally {
      _running = false;
    }
  }
}
