import 'package:shared_preferences/shared_preferences.dart';

class ShopMessageSettings {
  const ShopMessageSettings({
    this.shopName = '',
    this.header = '',
    this.footer = '',
  });

  final String shopName;
  final String header;
  final String footer;

  static const _nameKey = 'shop_message_name';
  static const _headerKey = 'shop_message_header';
  static const _footerKey = 'shop_message_footer';

  static Future<ShopMessageSettings> load() async {
    final prefs = SharedPreferencesAsync();
    return ShopMessageSettings(
      shopName: await prefs.getString(_nameKey) ?? '',
      header: await prefs.getString(_headerKey) ?? '',
      footer: await prefs.getString(_footerKey) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_nameKey, shopName.trim());
    await prefs.setString(_headerKey, header.trim());
    await prefs.setString(_footerKey, footer.trim());
  }
}
