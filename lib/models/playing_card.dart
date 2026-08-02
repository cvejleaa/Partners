enum Suit { hearts, diamonds, clubs, spades }

enum Rank {
  ace,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
}

class PlayingCard {
  const PlayingCard(Rank this.rank, Suit this.suit)
      : isExit = false,
        exitId = -1;

  /// Et rent "ud"-kort (markeres med et hjerte). [exitId] 0..3 gør de fire
  /// ud-kort distinkte.
  const PlayingCard.exit(this.exitId)
      : rank = null,
        suit = null,
        isExit = true;

  final Rank? rank;
  final Suit? suit;
  final bool isExit;
  final int exitId;

  String get rankLabel {
    if (isExit) return 'UD';
    switch (rank!) {
      case Rank.ace:
        return 'A';
      case Rank.jack:
        return 'J';
      case Rank.queen:
        return 'Q';
      case Rank.king:
        return 'K';
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
    }
  }

  String get suitSymbol {
    if (isExit) return '♥';
    switch (suit!) {
      case Suit.hearts:
        return '♥';
      case Suit.diamonds:
        return '♦';
      case Suit.clubs:
        return '♣';
      case Suit.spades:
        return '♠';
    }
  }

  bool get isRed => isExit || suit == Suit.hearts || suit == Suit.diamonds;

  /// Mulige fremad-skridt (kun til AI-heuristik; reglerne bruger CardRules).
  List<int> get forwardSteps {
    if (isExit) return const <int>[];
    switch (rank!) {
      case Rank.ace:
        return const <int>[1, 11];
      case Rank.two:
        return const <int>[2];
      case Rank.three:
        return const <int>[3];
      case Rank.four:
        return const <int>[];
      case Rank.five:
        return const <int>[5];
      case Rank.six:
        return const <int>[6];
      case Rank.seven:
        return const <int>[];
      case Rank.eight:
        return const <int>[8];
      case Rank.nine:
        return const <int>[9];
      case Rank.ten:
        return const <int>[10];
      case Rank.jack:
        return const <int>[11];
      case Rank.queen:
        return const <int>[12];
      case Rank.king:
        return const <int>[13];
    }
  }

  bool get canExitStart => isExit || rank == Rank.ace || rank == Rank.king;

  @override
  String toString() => isExit ? 'UD♥' : '$rankLabel$suitSymbol';

  @override
  bool operator ==(Object other) =>
      other is PlayingCard &&
      other.isExit == isExit &&
      other.exitId == exitId &&
      other.rank == rank &&
      other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit, isExit, exitId);
}
