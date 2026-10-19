import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prueba_flutter/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings are restored from local preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await provider.loadPreferences();

    expect(provider.isDarkMode, isFalse);
    expect(provider.languageCode, 'es');
    expect(provider.communityNotifications, isFalse);

    await provider.toggleDarkMode(true);
    await provider.setLanguageCode('en');
    await provider.setCommunityNotifications(true);
    await provider.setTrafficNotifications(true);
    await provider.setPromotionsNotifications(true);

    final restoredProvider = ThemeProvider();
    await restoredProvider.loadPreferences();

    expect(restoredProvider.isDarkMode, isTrue);
    expect(restoredProvider.languageCode, 'en');
    expect(restoredProvider.communityNotifications, isTrue);
    expect(restoredProvider.trafficNotifications, isTrue);
    expect(restoredProvider.promotionsNotifications, isTrue);
  });
}
