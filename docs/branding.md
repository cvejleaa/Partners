# Partners — branding & ikoner

Kort reference saa app'ens visuelle identitet kan reproduceres og ikoner kan genereres i CI.

## Farver

| Rolle | Hex | Brug |
| --- | --- | --- |
| Primær / brun | `#8B5E3C` | `theme_color`, ikon-baggrund, knapper, app-bar (`colorSchemeSeed` i `lib/app.dart`) |
| Brun mørk (kant) | `#5E3D24` | Ikon-kant / dybde |
| Baggrund mørkegrøn | `#0E2A1A` | Spillets baggrund (`Scaffold backgroundColor`), `background_color` i manifest, loading-overlay |
| Grøn lys (gradient) | `#15412A` | Gradient-top i loading-overlay |
| Creme / pergament | `#F5EAD2` | Tekst paa moerk baggrund, ringe og kanter i ikon |
| Creme dæmpet | `#C9B896` | Sekundær tekst (undertekst i loading) |

### Brik-farver (fra `lib/utils/palette.dart`)

Bruges i ikonets fire brikker:

| Farve | Hex |
| --- | --- |
| Rød | `#E53935` |
| Blå | `#1E88E5` |
| Grøn | `#43A047` |
| Gul | `#FDD835` |

(Den fulde palette har desuden Lilla `#8E24AA`, Orange `#FB8C00`, Turkis `#00ACC1`, Pink `#EC407A`.)

## Ikon-koncept

Fire spillebrikker (rød, blå, grøn, gul) placeret omkring en central creme-farvet ring,
paa app'ens brune baggrund med afrundede hjoerner. Motivet symboliserer Partners' fire
spillere/farver der moedes paa midten af braettet. Rent, fladt og skalerbart.

## Leverede vektor-filer (kilde)

- `web/favicon.svg` — favicon (64×64 viewBox, afrundet brun firkant).
- `web/icons/Icon.svg` — app-ikon, standard (`purpose: any`), 512 viewBox.
- `web/icons/Icon-maskable.svg` — maskerbar variant; motivet er traekket ind i den
  sikre zone (inderste ~80 %) saa det overlever cirkel-/squircle-beskaering.

`web/index.html` har desuden en inline-kopi af favicon-SVG'en i loading-overlayet.

## MANGLER: binær PNG-generering (CI-step)

SVG'er kan ikke daekke alle platforme. Foelgende binære PNG'er skal genereres fra
SVG-kilderne ved build (de kan ikke laves i et rent web-asset-miljoe uden et raster-step):

- `web/favicon.png`
- `web/icons/Icon-192.png`
- `web/icons/Icon-512.png`
- `web/icons/Icon-maskable-192.png`
- `web/icons/Icon-maskable-512.png`

`web/manifest.json` og `web/index.html` refererer allerede baade SVG- og PNG-varianterne,
saa naar PNG'erne findes, virker bade browser-favicon, PWA-installation og Apple touch-icon
overalt. SVG'erne fungerer i moderne browsere imens.

### Forslag til generering

1. **flutter_launcher_icons** (anbefalet i Flutter-projekt): tilfoej config i `pubspec.yaml`
   der peger paa en hoejtoploest PNG/SVG-kilde og koer `dart run flutter_launcher_icons`.
2. **Manuelt / CI raster-step**, fx med rsvg-convert eller ImageMagick:
   ```sh
   rsvg-convert -w 192 -h 192 web/icons/Icon.svg -o web/icons/Icon-192.png
   rsvg-convert -w 512 -h 512 web/icons/Icon.svg -o web/icons/Icon-512.png
   rsvg-convert -w 192 -h 192 web/icons/Icon-maskable.svg -o web/icons/Icon-maskable-192.png
   rsvg-convert -w 512 -h 512 web/icons/Icon-maskable.svg -o web/icons/Icon-maskable-512.png
   rsvg-convert -w 64  -h 64  web/favicon.svg -o web/favicon.png
   ```
