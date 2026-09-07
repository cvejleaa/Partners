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
String danishDate(int ms, DateTime now) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  final String base = _dayMonth(t);
  return t.year == now.year ? base : '$base ${t.year}';
}

/// "14. aug. 2026" — altid med årstal, og derfor UDEN [now].
///
/// Til datoer der står alene og kan læses længe efter (slutrapporten). Var
/// før et `alwaysYear:`-flag på [danishDate], men så skulle kalderen give et
/// [now], funktionen ignorerede — et argument, der ikke betyder noget, er
/// værre end ingen argument (QC-fund).
String danishDateWithYear(int ms) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_dayMonth(t)} ${t.year}';
}

/// "2.–6. sep." / "14. aug. – 6. sep." / "28. dec. 2025 – 6. jan. 2026".
///
/// Tankestregen er den halvlange (–), tæt når venstre side kun er en dag
/// ("2.–6. sep.") og med mellemrum når leddene selv indeholder mellemrum.
/// [fromApprox]/[toApprox] sætter "ca." ved PRÆCIS den ende, der kun er kendt
/// omtrentligt. Ét fælles "ca." foran hele perioden sagde blot at "noget her
/// er usikkert" — og satte det visuelt på den ældste dato, også når det var
/// den nyeste, der var gættet (QC-fund).
String danishPeriod(int fromMs, int toMs, DateTime now,
    {bool fromApprox = false, bool toApprox = false}) {
  const String ca = 'ca. ';
  final String fromCa = fromApprox ? ca : '';
  final String toCa = toApprox ? ca : '';
  final DateTime a = DateTime.fromMillisecondsSinceEpoch(fromMs);
  final DateTime b = DateTime.fromMillisecondsSinceEpoch(toMs);
  // Samme DAG kræver også samme år og måned: 6. sep. 2025 og 6. sep. 2026 er
  // ikke den samme dag, og en regel på `day` alene ville skjule et helt år.
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    // Én dato: der er kun én ende at tage forbehold for.
    return '${fromApprox || toApprox ? ca : ''}${danishDate(toMs, now)}';
  }
  if (a.year != b.year) {
    // Årstal i BEGGE ender. "28. dec. 2025 – 6. jan." lader læseren gætte på,
    // hvilket år den anden ende er.
    return '$fromCa${_dayMonth(a)} ${a.year}'
        ' – $toCa${_dayMonth(b)} ${b.year}';
  }
  // Samme år: årstallet skrives ÉN gang, til sidst — og kun når det ikke er
  // indeværende år ("3.–9. nov. 2025").
  final String year = a.year == now.year ? '' : ' ${a.year}';
  // Den korte fælles-måned-form kan ikke bære et forbehold pr. ende ("ca.
  // 2.–6. sep." ville igen være tvetydig), så er en ende omtrentlig, skrives
  // måneden ud i begge ender.
  if (a.month == b.month && !fromApprox && !toApprox) {
    // Måneden skrives én gang. Kræver samme år, hvilket er sikret ovenfor:
    // ellers ville 6. sep. 2025 → 2. sep. 2026 blive til "6.–2. sep.", som
    // både er meningsløst og ser ud som om enderne var byttet om.
    return '${a.day}.–${b.day}. ${_months[b.month - 1]}$year';
  }
  return '$fromCa${_dayMonth(a)} – $toCa${_dayMonth(b)}$year';
}
