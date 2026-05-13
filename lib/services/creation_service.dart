// lib/services/creation_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';

class ProjetCreation {
  final String nom;         // ex: "1_création_villa_1"
  final String categorie;   // ex: "VILLA"
  final String cheminDossier;
  final String? imagePath;  // 1ère image trouvée dans Autre/

  ProjetCreation({
    required this.nom,
    required this.categorie,
    required this.cheminDossier,
    this.imagePath,
  });

  String get label => '$categorie / $nom';
}

class CreationService {
  static final CreationService _instance = CreationService._internal();
  factory CreationService() => _instance;
  CreationService._internal();

  final List<ProjetCreation> _projets = [];
  List<ProjetCreation> get projets => List.unmodifiable(_projets);

  /// Résout le chemin CREATION depuis le chemin Habitation sélectionné
  static String? resoudreCheminCreation(String cheminHabitation) {
    final parent = Directory(cheminHabitation).parent.path;
    final creation = Directory('$parent${Platform.pathSeparator}CREATION');
    return creation.existsSync() ? creation.path : null;
  }

  Future<bool> charger(String cheminHabitation) async {
    final cheminCreation = resoudreCheminCreation(cheminHabitation);
    if (cheminCreation == null) return false;

    _projets.clear();
    final racine = Directory(cheminCreation);

    try {
      // Parcourt chaque catégorie (A NIVEAU, APPARTEMENT, VILLA…)
      await for (final catEntity in racine.list()) {
        if (catEntity is! Directory) continue;
        final nomCat = catEntity.path.split(Platform.pathSeparator).last;
        if (nomCat.startsWith('.')) continue;

        // Parcourt chaque projet dans la catégorie
        await for (final projEntity in catEntity.list()) {
          if (projEntity is! Directory) continue;
          final nomProjet =
              projEntity.path.split(Platform.pathSeparator).last;
          if (nomProjet.startsWith('.')) continue;

          // Cherche une image dans Autre/
          final imagePath = await _trouverImageAutre(projEntity);

          _projets.add(ProjetCreation(
            nom: nomProjet,
            categorie: nomCat,
            cheminDossier: projEntity.path,
            imagePath: imagePath,
          ));
        }
      }

      // Tri alphabétique catégorie puis nom
      _projets.sort((a, b) {
        final cat = a.categorie.compareTo(b.categorie);
        return cat != 0 ? cat : a.nom.compareTo(b.nom);
      });

      return true;
    } catch (e) {
      debugPrint('Erreur chargement création: $e');
      return false;
    }
  }

  Future<String?> _trouverImageAutre(Directory dossierProjet) async {
    final extensions = {
      '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif',
      '.JPG', '.JPEG', '.PNG', '.WEBP', '.BMP', '.GIF',
    };
    final autre = Directory(
        '${dossierProjet.path}${Platform.pathSeparator}Autre');
    if (!autre.existsSync()) return null;
    try {
      await for (final f in autre.list()) {
        if (f is File) {
          final ext = f.path.substring(f.path.lastIndexOf('.'));
          if (extensions.contains(ext)) return f.path;
        }
      }
    } catch (_) {}
    return null;
  }

  void vider() => _projets.clear();
}
