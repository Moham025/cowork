// lib/services/storage_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _kCataloguePathKey = 'catalogue_path';
  static const _kRecentlyViewedKey = 'recently_viewed_paths';

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String? getCataloguePath() {
    return _prefs?.getString(_kCataloguePathKey);
  }

  Future<void> saveCataloguePath(String path) async {
    await init();
    await _prefs!.setString(_kCataloguePathKey, path);
  }

  Future<void> clearCataloguePath() async {
    await init();
    await _prefs!.remove(_kCataloguePathKey);
  }

  // --- Recently viewed dossiers ---

  List<String> getRecentlyViewedPaths() {
    return _prefs?.getStringList(_kRecentlyViewedKey) ?? [];
  }

  Future<void> addRecentlyViewed(String cheminDossier) async {
    await init();
    List<String> paths = getRecentlyViewedPaths();
    paths.remove(cheminDossier);
    paths.insert(0, cheminDossier);
    if (paths.length > 5) paths = paths.take(5).toList();
    await _prefs!.setStringList(_kRecentlyViewedKey, paths);
  }

  Future<void> clearRecentlyViewed() async {
    await init();
    await _prefs!.remove(_kRecentlyViewedKey);
  }
}
