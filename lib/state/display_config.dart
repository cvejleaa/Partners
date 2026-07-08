import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
