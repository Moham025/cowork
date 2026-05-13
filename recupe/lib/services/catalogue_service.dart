// lib/services/catalogue_service.dart

import 'dart:io';
import 'dart:convert';
import '../models/projet_model.dart';

class CatalogueService {
  // Singleton
  static final CatalogueService _instance = CatalogueService._internal();
  factory CatalogueService() => _instance;
  CatalogueService._internal();

  List<Projet> _projets = [];
  List<String> _categories = ['Tous'];

  List<Projet> get projets => _projets;
  List<String> get categories => _categories;

  // Charger tous les projets depuis un dossier racine
  Future<bool> chargerCatalogue(String cheminRacine) async {
    try {
      final dossierRacine = Directory(cheminRacine);

      if (!await dossierRacine.exists()) {
        print('❌ Dossier inexistant: $cheminRacine');
        return false;
      }

      _projets.clear();
      _categories = ['Tous'];

      // 1. Récupérer les catégories (dossiers directs)
      await for (var entity in dossierRacine.list()) {
        if (entity is Directory) {
          final nomCategorie = entity.path.split(Platform.pathSeparator).last;
          if (!_categories.contains(nomCategorie)) {
            _categories.add(nomCategorie);
          }
        }
      }

      // 2. Scanner récursivement les fichiers infos.json
      final fichiersJson = await _scannerFichiersJson(dossierRacine);

      print('📂 ${fichiersJson.length} fichiers infos.json trouvés');

      // 3. Charger chaque projet
      for (var fichier in fichiersJson) {
        try {
          final contenu = await fichier.readAsString();
          final json = jsonDecode(contenu) as Map<String, dynamic>;

          final dossierProjet = fichier.parent.path;
          final categorie =
              fichier.parent.parent.path.split(Platform.pathSeparator).last;

          // Scanner les images du dossier
          final images = await _scannerImages(fichier.parent);

          // Détecter fichiers ArchiCAD/Twinmotion dans Source/ et EstimType dans Autre/
          final sourceResult = await _scannerSource(fichier.parent);

          final projet = Projet.fromJson(
            json, dossierProjet, categorie, images,
            archicadPath: sourceResult['archicad'],
            twinmotionPath: sourceResult['twinmotion'],
            estimTypePath: sourceResult['estimtype'],
          );
          _projets.add(projet);
        } catch (e) {
          print('⚠️ Erreur chargement ${fichier.path}: $e');
        }
      }

      print(
          '✅ ${_projets.length} projets chargés dans ${_categories.length - 1} catégories');
      return true;
    } catch (e) {
      print('❌ Erreur chargement catalogue: $e');
      return false;
    }
  }

  // Scanner Source/ et Autre/ → chemins réels des fichiers détectés
  Future<Map<String, String?>> _scannerSource(Directory dossierProjet) async {
    final sep = Platform.pathSeparator;
    String? archicadPath;
    String? twinmotionPath;
    String? estimTypePath;

    // Source/ → ArchiCAD (.pln/.bpn) et Twinmotion (.tm)
    final source = Directory('${dossierProjet.path}${sep}Source');
    if (source.existsSync()) {
      try {
        await for (final entity in source.list()) {
          if (entity is File) {
            final lower = entity.path.toLowerCase();
            if (archicadPath == null &&
                (lower.endsWith('.pln') || lower.endsWith('.bpn'))) {
              archicadPath = entity.path;
            }
            if (twinmotionPath == null && lower.endsWith('.tm')) {
              twinmotionPath = entity.path;
            }
          }
          if (archicadPath != null && twinmotionPath != null) break;
        }
      } catch (_) {}
    }

    // Autre/ → EstimType.xlsx
    final estimFile = File('${dossierProjet.path}${sep}Autre${sep}EstimType.xlsx');
    if (estimFile.existsSync()) estimTypePath = estimFile.path;

    return {
      'archicad': archicadPath,
      'twinmotion': twinmotionPath,
      'estimtype': estimTypePath,
    };
  }

  // Scanner récursivement les fichiers infos.json
  Future<List<File>> _scannerFichiersJson(Directory dossier) async {
    final fichiers = <File>[];

    try {
      await for (var entity in dossier.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('infos.json')) {
          fichiers.add(entity);
        }
      }
    } catch (e) {
      print('Erreur scan JSON: $e');
    }

    return fichiers;
  }

  // Scanner les images d'un dossier (vignettes en premier)
  Future<List<String>> _scannerImages(Directory dossier) async {
    final extensions = ['.jpg', '.jpeg', '.png', '.JPG', '.JPEG', '.PNG'];
    final vignettes = <String>[];
    final autres = <String>[];

    try {
      await for (var entity in dossier.list()) {
        if (entity is File) {
          final nom =
              entity.path.split(Platform.pathSeparator).last.toLowerCase();
          final ext = entity.path.substring(entity.path.lastIndexOf('.'));

          if (extensions.contains(ext)) {
            if (nom.startsWith('vignette')) {
              vignettes.add(entity.path);
            } else {
              autres.add(entity.path);
            }
          }
        }
      }
    } catch (e) {
      print('Erreur scan images: $e');
    }

    vignettes.sort();
    autres.sort();
    return [...vignettes, ...autres];
  }

  // Filtrer les projets
  List<Projet> filtrerProjets({
    String categorie = 'Tous',
    String recherche = '',
    double budgetMax = 0,
  }) {
    return _projets.where((projet) {
      // Filtre catégorie
      final matchCategorie =
          categorie == 'Tous' || projet.categorie == categorie;

      // Filtre recherche
      final rechercheLower = recherche.toLowerCase();
      final matchRecherche = recherche.isEmpty ||
          projet.nomProjet.toLowerCase().contains(rechercheLower) ||
          projet.usage.toLowerCase().contains(rechercheLower);

      // Filtre budget
      final matchBudget =
          budgetMax == 0 || projet.coutConstruction <= budgetMax;

      return matchCategorie && matchRecherche && matchBudget;
    }).toList();
  }

  // Vider le cache
  void viderCache() {
    _projets.clear();
    _categories = ['Tous'];
  }
}
