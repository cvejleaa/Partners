import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/ai/ai_player.dart';
import '../online/online_service.dart';

/// Standard minimums-brætstørrelse (px) hvis intet er sat i config.
const double kBoardMinDefault = 230.0;

/// Grænser for admin-justering.
const double kBoardMinLower = 140.0;
const double kBoardMinUpper = 420.0;

/// Live minimums-brætstørrelse fra `config/ui.boardMinPx` (admin-justerbar).
///
/// Brættet gøres aldrig mindre end denne værdi — resten af layoutet (paneler,
/// hånd-kort) tilpasser sig, og først når vinduet er for lavt til det, scrolles
/// siden. Ligger i config-collectionen (læsbar af alle, kun admin må skrive),
/// så den kan justeres løbende uden ny deploy.
final boardMinPxProvider = StreamProvider<double>((ref) {
  try {
    return firestore
        .collection('config')
        .doc('ui')
        .snapshots()
        .map((snap) {
      final v = snap.data()?['boardMinPx'];
      if (v is num) {
        return v.toDouble().clamp(kBoardMinLower, kBoardMinUpper);
      }
      return kBoardMinDefault;
    });
  } catch (_) {
    return Stream<double>.value(kBoardMinDefault);
  }
});

/// Skriv ny minimums-brætstørrelse. Kun admin må ifølge Firestore-reglerne.
Future<void> setBoardMinPx(double px) async {
  final double v = px.clamp(kBoardMinLower, kBoardMinUpper);
  await firestore.collection('config').doc('ui').set(
    <String, dynamic>{
      'boardMinPx': v,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

/// Parametrene for de tre AI-sværhedsgrader (Begynder/Normal/Skarp), som admin
/// kan justere, fra `config/ai.levels`. Spilleren vælger selv graden pr. spil;
/// disse parametre bestemmer HVAD hver grad gør. Falder tilbage til defaults
/// hvis intet er sat.
final aiLevelsProvider = StreamProvider<List<AiParams>>((ref) {
  try {
    return firestore.collection('config').doc('ai').snapshots().map((snap) {
      final levels = snap.data()?['levels'];
      if (levels is List && levels.length == kDefaultAiLevels.length) {
        return <AiParams>[
          for (final dynamic l in levels)
            AiParams.fromJson(Map<String, dynamic>.from(l as Map)),
        ];
      }
      return kDefaultAiLevels;
    });
  } catch (_) {
    return Stream<List<AiParams>>.value(kDefaultAiLevels);
  }
});

/// Skriv de tre graders parametre. Kun admin må ifølge Firestore-reglerne.
Future<void> setAiLevels(List<AiParams> levels) async {
  await firestore.collection('config').doc('ai').set(
    <String, dynamic>{
      'levels': <dynamic>[for (final AiParams l in levels) l.toJson()],
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}
