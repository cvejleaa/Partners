/// Danske datoetiketter ÉT sted.
///
/// Månedstabellen fandtes før i to kopier (arkivlisten og slutskærmen), og en
/// tredje var på vej med perioden. To formateringer af samme dato kan drive
/// fra hinanden, og den ene kunne ændres uden at nogen test blev rød.
///
/// [now] gives ALTID af kalderen, aldrig læst her. Det er husets regel — den
/// stod allerede skrevet i online_screens.dart, mens datofunktionen lige
/// ovenover brød den: to etiketter bygget i samme frame må ikke kunne lande på
/// hver sin side af et årsskifte, og en test på "14. aug." skal ikke være grøn
/// hele året og rød 1. januar (QC-fund).
library;

const List<String> _months = <String>[
  'jan.', 'feb.', 'mar.', 'apr.', 'maj', 'jun.',
  'jul.', 'aug.', 'sep.', 'okt.', 'nov.', 'dec.',
];

String _dayMonth(DateTime t) => '${t.day}. ${_months[t.month - 1]}';

/// "14. aug." — med årstal når det ikke er indeværende år.
///
/// [alwaysYear] til steder, hvor datoen står alene og kan læses længe efter
/// (slutrapporten). Et forfalsket [now] ville give samme resultat, men det er
/// et trick — parameteren siger hvad den gør.
String danishDate(int ms, DateTime now, {bool alwaysYear = false}) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  final String base = _dayMonth(t);
  return (alwaysYear && t.year == now.year) ? base : '$base ${t.year}'; // MUTATION (k)
}

/// "2.–6. sep." / "14. aug. – 6. sep." / "28. dec. 2025 – 6. jan. 2026".
///
/// Tankestregen er den halvlange (–), tæt når venstre side kun er en dag
/// ("2.–6. sep.") og med mellemrum når leddene selv indeholder mellemrum.
String danishPeriod(int fromMs, int toMs, DateTime now) {
  final DateTime a = DateTime.fromMillisecondsSinceEpoch(fromMs);
  final DateTime b = DateTime.fromMillisecondsSinceEpoch(toMs);
  // Samme DAG kræver også samme år og måned: 6. sep. 2025 og 6. sep. 2026 er
  // ikke den samme dag, og en regel på `day` alene ville skjule et helt år.
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return danishDate(toMs, now);
  }
  if (a.year != b.year) {
    // Årstal i BEGGE ender. "28. dec. 2025 – 6. jan." lader læseren gætte på,
    // hvilket år den anden ende er.
    return '${_dayMonth(a)} ${a.year} – ${_dayMonth(b)} ${b.year}';
  }
  // Samme år: årstallet skrives ÉN gang, til sidst — og kun når det ikke er
  // indeværende år ("3.–9. nov. 2025").
  final String year = a.year == now.year ? '' : ' ${a.year}';
  if (a.month == b.month) {
    // Måneden skrives én gang. Kræver samme år, hvilket er sikret ovenfor:
    // ellers ville 6. sep. 2025 → 2. sep. 2026 blive til "6.–2. sep.", som
    // både er meningsløst og ser ud som om enderne var byttet om.
    return '${a.day}.–${b.day}. ${_months[b.month - 1]}$year';
  }
  return '${_dayMonth(a)} – ${_dayMonth(b)}$year';
}
