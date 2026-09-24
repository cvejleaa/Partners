// "Nyt spil" forvælger den variant, man sidst oprettede et online-spil med.
// Den huskes lokalt i Settings — og skal overleve gem/indlæs.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/state/settings_controller.dart';

void main() {
  test('sidst brugte online-variant overlever toJson/fromJson', () {
    const Settings s = Settings(lastOnlineVariantId: 'duo');
    expect(Settings.fromJson(s.toJson()).lastOnlineVariantId, 'duo');
  });

  test('uden gemt variant: null (dialogen falder til klassisk)', () {
    expect(Settings.fromJson(const Settings().toJson()).lastOnlineVariantId,
        isNull);
    expect(
        Settings.fromJson(<String, dynamic>{'lastOnlineVariantId': 7})
            .lastOnlineVariantId,
        isNull);
  });

  test('copyWith bevarer varianten, når noget andet ændres', () {
    const Settings s = Settings(lastOnlineVariantId: 'p25');
    expect(s.copyWith(soundEnabled: false).lastOnlineVariantId, 'p25');
  });
}
