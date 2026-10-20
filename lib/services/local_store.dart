import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data.dart';

class LocalStore {
  LocalStore({String? namespace})
    : _key = 'fideli.app_data.v2.${_safeNamespace(namespace)}';

  final String _key;

  static String _safeNamespace(String? value) {
    final normalized = (value ?? 'guest').trim().toLowerCase();
    if (normalized.isEmpty) return 'guest';
    return normalized.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  }

  Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return AppData.initial();
    try {
      return AppData.decode(raw);
    } catch (_) {
      return AppData.initial();
    }
  }

  Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, data.encode());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
