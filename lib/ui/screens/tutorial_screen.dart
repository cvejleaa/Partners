import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/card_rules.dart';
import '../../models/playing_card.dart';
import '../../state/card_rules_controller.dart';
import '../widgets/card_view.dart';

/// Farver der matcher resten af app'en.
const Color _kBrown = Color(0xFF8B5E3C);
const Color _kBackground = Color(0xFF0E2A1A);

/// En venlig, gennemklikkelig tutorial der forklarer reglerne for Partners.
///
/// Vises som en [PageView] med "sider" man bladrer igennem med Næste/Forrige.
/// Kort-beskrivelserne læses fra de aktuelle [CardRules], så de altid passer
/// med spillets faktiske regler (også hvis admin har justeret et kort).
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CardRules rules = ref.watch(cardRulesProvider);
    final List<Widget> pages = _buildPages(rules);
    final bool isLast = _page == pages.length - 1;
    final bool isFirst = _page == 0;

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: _kBrown,
        foregroundColor: Colors.white,
        title: const Text('Sådan spiller du'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (int i) => setState(() => _page = i),
              children: pages,
            ),
          ),
          _DotsIndicator(count: pages.length, current: _page),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: _kBrown),
                    ),
                    onPressed: isFirst ? null : () => _goTo(_page - 1),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Forrige'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: _kBrown,
                    ),
                    onPressed: isLast
                        ? () => Navigator.of(context).pop()
                        : () => _goTo(_page + 1),
                    icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                    label: Text(isLast ? 'Forstået!' : 'Næste'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPages(CardRules rules) {
    return <Widget>[
      const _TutorialPage(
        emoji: '🤝',
        title: 'Velkommen til Partners',
        sections: <_Section>[
          _Section(
            icon: Icons.flag,
            heading: 'Mål',
            body: 'Partners spilles af 4 spillere i 2 hold. Du og din makker '
                '(spilleren OVERFOR dig) er ét hold. I har fælles mål: at få '
                'alle jeres brikker sikkert i mål i hjemstrækket.',
          ),
          _Section(
            icon: Icons.emoji_events,
            heading: 'Sådan vinder I',
            body: 'Hver spiller har 4 brikker. Holdet vinder, når alle 8 '
                'holdbrikker (dine 4 + makkerens 4) er kommet i mål i '
                'hjemstrækket.',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '🎯',
        title: 'Brættet',
        sections: <_Section>[
          _Section(
            icon: Icons.track_changes,
            heading: 'Banen',
            body: 'Banen er én stor ring med 56 felter — 14 nummererede felter '
                'pr. spiller. Brikkerne bevæger sig hele vejen rundt. Hver '
                'spiller har sit eget udgangsfelt ("felt 1"), hvor brikkerne '
                'kommer ind på banen.',
          ),
          _Section(
            icon: Icons.home,
            heading: 'Hjemstrækket',
            body: 'Når en brik har taget en hel omgang og når tilbage til sit '
                'eget udgangsfelt, drejer den ind i sit hjemstræk — 4 felter '
                'helt for dig selv. Her står brikken sikkert i mål. Du kan ikke '
                'rykke længere end hjemstrækkets bagende.',
          ),
          _Section(
            icon: Icons.inventory_2,
            heading: 'Start',
            body: 'Dine 4 brikker starter i din startcirkel. De skal først ud '
                'på banen, før de kan begynde rejsen mod hjemstrækket.',
          ),
        ],
      ),
      _CardsPage(rules: rules),
      const _TutorialPage(
        emoji: '🚪',
        title: 'Ud af start',
        sections: <_Section>[
          _Section(
            icon: Icons.login,
            heading: 'Sådan kommer du ud',
            body: 'For at få en brik ud af start skal du bruge et UD-kort, et '
                'Es eller en Konge. Brikken sættes på dit eget udgangsfelt '
                '("felt 1").',
          ),
          _Section(
            icon: Icons.block,
            heading: 'Udgangsfeltet spærrer',
            body: 'Så længe du selv har en brik stående PÅ dit udgangsfelt, kan '
                'ingen modstander hverken lande på eller passere det felt — '
                'hverken frem eller tilbage. Du selv spærres aldrig af din egen '
                'brik. Flytter du brikken videre, åbner feltet igen.',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '⚔️',
        title: 'Slag og makker',
        sections: <_Section>[
          _Section(
            icon: Icons.bolt,
            heading: 'Slå hjem',
            body: 'Lander du på et felt med PRÆCIS ÉN modstanderbrik, sendes '
                'den hjem til startcirklen. Sådan sætter du modstanderne '
                'tilbage.',
          ),
          _Section(
            icon: Icons.handshake,
            heading: 'Makkerens brik',
            body: 'Du MÅ godt slå din egen makkers brik hjem — det er bare '
                'sjældent klogt. Dine egne brikker kan derimod stables oven på '
                'hinanden uden at slå hinanden.',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '🛡️',
        title: 'Doubler og passage',
        sections: <_Section>[
          _Section(
            icon: Icons.layers,
            heading: 'To brikker spærrer ikke',
            body: 'Står der 2 eller flere brikker på samme felt, spærrer de '
                'IKKE for nogen — alle må passere forbi.',
          ),
          _Section(
            icon: Icons.local_fire_department,
            heading: 'Pas på modstanderens double',
            body: 'Men lander du på et felt, hvor en MODSTANDER har 2+ brikker '
                '(en "double"), bliver DIN egen brik slået hjem — doublen '
                '"brænder" dig. Tænk dig om, før du lander der!',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '🃏',
        title: 'Særlige kort',
        sections: <_Section>[
          _Section(
            icon: Icons.call_split,
            heading: 'Del en 7\'er',
            body: 'En 7\'er fordeles over en eller flere af dine brikker i '
                'spil — fx 4 + 3 eller 5 + 2. Du SKAL kunne bruge alle 7 træk. '
                'Hver brik rykkes kun én gang. Får du din sidste brik i mål med '
                'færre træk, må resten lægges på MAKKERENS brikker.',
          ),
          _Section(
            icon: Icons.swap_horiz,
            heading: 'Frem og tilbage',
            body: 'En 4\'er kan rykke 4 felter frem ELLER 4 felter tilbage. Et '
                'Es kan gå ud af start eller rykke 1 eller 11 felter. Læs altid '
                'kortets symboler for at se, hvad det kan.',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '🔄',
        title: 'Runden',
        sections: <_Section>[
          _Section(
            icon: Icons.style,
            heading: 'Byt med makkeren',
            body: 'I starten af hver runde får alle 4 kort på hånden. Du vælger '
                'ét skjult kort, som byttes med din makker. Brug det til at '
                'hjælpe hinanden — uden at sige hvad I har!',
          ),
          _Section(
            icon: Icons.do_not_disturb_on,
            heading: 'Når du ikke kan rykke',
            body: 'Kan du ikke lave et lovligt træk med nogen af dine kort, '
                'smider du resten af hånden og sidder over resten af runden. '
                'Derfor er det vigtigt at planlægge.',
          ),
        ],
      ),
      const _TutorialPage(
        emoji: '🏆',
        title: 'Klar til at spille?',
        sections: <_Section>[
          _Section(
            icon: Icons.lightbulb,
            heading: 'Gode råd',
            body: 'Hjælp din makker frem. Hold en brik på dit udgangsfelt for '
                'at spærre modstanderne. Hold øje med deres brikker — og slå '
                'dem hjem, når chancen byder sig.',
          ),
          _Section(
            icon: Icons.sports_esports,
            heading: 'Held og lykke!',
            body: 'Tryk "Forstået!" for at vende tilbage. Du kan altid komme '
                'tilbage hertil fra forsiden, hvis du vil genopfriske reglerne.',
          ),
        ],
      ),
    ];
  }
}

/// En enkelt tekst-side i tutorialen med emoji, titel og sektioner.
class _TutorialPage extends StatelessWidget {
  const _TutorialPage({
    required this.emoji,
    required this.title,
    required this.sections,
  });

  final String emoji;
  final String title;
  final List<_Section> sections;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Text(emoji, style: const TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final _Section s in sections) ...<Widget>[
            _SectionCard(section: s),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Et lille datakort til en sektion (overskrift + brødtekst + ikon).
class _Section {
  const _Section({
    required this.icon,
    required this.heading,
    required this.body,
  });

  final IconData icon;
  final String heading;
  final String body;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBrown.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: _kBrown,
              shape: BoxShape.circle,
            ),
            child: Icon(section.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  section.heading,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Side der viser et udvalg af rigtige spillekort med forklaring, så
/// spilleren lærer at læse kortenes symboler. Teksten genereres dynamisk fra
/// de aktuelle [CardRules], så alt matcher admin-justeringer øjeblikkeligt.
class _CardsPage extends StatelessWidget {
  const _CardsPage({required this.rules});

  final CardRules rules;

  /// Beskriv én rangs FAKTISKE funktion ud fra dens [CardRuleConfig].
  static String describeRank(Rank r, CardRules rules) {
    final CardRuleConfig cfg = rules.forRank(r);
    final List<String> parts = <String>[];
    if (cfg.exitStart) parts.add('ud af start');
    if (cfg.forwardSteps.isNotEmpty) {
      if (cfg.forwardSteps.length == 1) {
        parts.add('${cfg.forwardSteps.first} frem');
      } else {
        parts.add('${cfg.forwardSteps.join(' eller ')} frem');
      }
    }
    if (cfg.backwardSteps != null) parts.add('${cfg.backwardSteps} tilbage');
    if (cfg.splitTotal != null) {
      parts.add('${cfg.splitTotal} træk delt over flere af dine brikker');
    }
    if (cfg.swap) parts.add('byt to brikker');
    if (parts.isEmpty) return 'Ingen funktion.';
    final String body = parts.length == 1
        ? parts.first
        : '${parts.sublist(0, parts.length - 1).join(', ')} eller ${parts.last}';
    return '${body[0].toUpperCase()}${body.substring(1)}.';
  }

  /// Et brugervenligt navn for en rang ("Es", "Knægt", "10" osv.).
  static String rankName(Rank r) {
    switch (r) {
      case Rank.ace:
        return 'Es';
      case Rank.two:
        return '2';
      case Rank.three:
        return '3';
      case Rank.four:
        return '4';
      case Rank.five:
        return '5';
      case Rank.six:
        return '6';
      case Rank.seven:
        return '7';
      case Rank.eight:
        return '8';
      case Rank.nine:
        return '9';
      case Rank.ten:
        return '10';
      case Rank.jack:
        return 'Knægt';
      case Rank.queen:
        return 'Dame';
      case Rank.king:
        return 'Konge';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eksempelkort: vis et lille udvalg af de mest karakteristiske kort.
    // Beskrivelserne genereres fra de aktuelle regler.
    const List<Rank> exampleRanks = <Rank>[
      Rank.ace,
      Rank.king,
      Rank.seven,
      Rank.four,
      Rank.jack,
    ];
    final List<_CardExample> examples = <_CardExample>[
      _CardExample(
        const PlayingCard.exit(0),
        'UD-kortet sender kun en brik ud på dit udgangsfelt.',
      ),
      for (final Rank r in exampleRanks)
        _CardExample(
          PlayingCard(r, Suit.spades),
          '${rankName(r)}: ${describeRank(r, rules)}',
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Center(
            child: Text('🂠', style: TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Kortene',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Hvert kort flytter dine brikker på sin egen måde. Symbolerne '
              'på kortet viser hvad det kan:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          const SizedBox(height: 20),
          for (final _CardExample ex in examples) ...<Widget>[
            _CardRow(example: ex, rules: rules),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          const Text(
            'Alle kort',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          // Den komplette oversigt læses LIVE fra CardRules — ændrer admin et
          // kort, opdaterer denne liste sig automatisk.
          _CardLineRow(
            line: const _CardLine(
                'UD-kort', 'Sender en brik ud på dit udgangsfelt.'),
          ),
          const SizedBox(height: 8),
          for (final Rank r in Rank.values) ...<Widget>[
            _CardLineRow(line: _CardLine(rankName(r), describeRank(r, rules))),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          const Text(
            'Tip: Admin kan justere hvad hvert kort gør. Beskrivelserne her '
            'følger altid den aktuelle opsætning.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// En linje i den komplette kort-oversigt: navn + kort beskrivelse.
class _CardLine {
  const _CardLine(this.name, this.text);
  final String name;
  final String text;
}

class _CardLineRow extends StatelessWidget {
  const _CardLineRow({required this.line});

  final _CardLine line;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            line.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line.text,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _CardExample {
  const _CardExample(this.card, this.text);
  final PlayingCard card;
  final String text;
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.example, required this.rules});

  final _CardExample example;
  final CardRules rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBrown.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          CardView(card: example.card, rules: rules, width: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              example.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Små prikker der viser hvilken side man er på.
class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? _kBrown : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
