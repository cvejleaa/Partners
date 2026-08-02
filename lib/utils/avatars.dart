/// Kurateret liste af avatarer til spiller-profiler.
///
/// Emoji-baseret med vilje: de renderes ens overalt (web, iOS, Android) uden
/// at hente eksterne billeder — ingen CSP-/asset-problemer. Temaet er
/// "brætspils-entusiaster": strateger, detektiver, spil-dyr og klassiske
/// spil-symboler, så folk kan vælge en persona der passer til deres stil.
class GameAvatar {
  const GameAvatar(this.id, this.emoji, this.label);

  /// Stabil nøgle der gemmes i profilen (ændrer sig ikke selv om vi tilføjer
  /// flere avatarer senere).
  final String id;
  final String emoji;
  final String label;
}

/// Standard-avataren når en spiller ikke har valgt en.
const GameAvatar kDefaultAvatar = GameAvatar('meeple', '🧩', 'Brik');

const List<GameAvatar> kAvatars = <GameAvatar>[
  // Spil-symboler
  GameAvatar('meeple', '🧩', 'Brik'),
  GameAvatar('dice', '🎲', 'Terning'),
  GameAvatar('pawn', '♟️', 'Bonde'),
  GameAvatar('crown', '👑', 'Konge'),
  GameAvatar('joker', '🃏', 'Joker'),
  GameAvatar('target', '🎯', 'Bullseye'),
  GameAvatar('trophy', '🏆', 'Vinder'),
  GameAvatar('spades', '♠️', 'Spar'),

  // Personas / entusiaster
  GameAvatar('strategist', '🧙', 'Strateg'),
  GameAvatar('detective', '🕵️', 'Detektiv'),
  GameAvatar('nerd', '🤓', 'Regel-nørd'),
  GameAvatar('cowboy', '🤠', 'Bluff-mester'),
  GameAvatar('ninja', '🥷', 'Snigløber'),
  GameAvatar('royal', '🤴', 'Adel'),
  GameAvatar('queen', '👸', 'Dronning'),
  GameAvatar('wizard', '🧝', 'Alf'),

  // Spil-dyr
  GameAvatar('fox', '🦊', 'Ræv'),
  GameAvatar('owl', '🦉', 'Ugle'),
  GameAvatar('dragon', '🐉', 'Drage'),
  GameAvatar('lion', '🦁', 'Løve'),
  GameAvatar('panda', '🐼', 'Panda'),
  GameAvatar('octopus', '🐙', 'Blæksprutte'),
  GameAvatar('turtle', '🐢', 'Skildpadde'),
  GameAvatar('cat', '🐱', 'Kat'),
];

/// Slå en avatar op på id; falder tilbage til [kDefaultAvatar].
GameAvatar avatarById(String? id) {
  if (id == null) return kDefaultAvatar;
  for (final GameAvatar a in kAvatars) {
    if (a.id == id) return a;
  }
  return kDefaultAvatar;
}

/// Emoji for et avatar-id (bekvemmeligheds-hjælper til visning).
String avatarEmoji(String? id) => avatarById(id).emoji;
