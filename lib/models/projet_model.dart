// lib/models/projet_model.dart

class Projet {
  final String nomProjet;
  final String categorie;
  final double surfaceHabitable;
  final String descriptionMarketing;
  final int nombreEtages;
  final Map<String, dynamic> detailsTechniques;
  final double coutConstruction;
  final String cheminDossier;
  final List<String> images;
  final String usage;
  // Chemins vers fichiers source (null = absent)
  final String? archicadPath;
  final String? twinmotionPath;
  final String? estimTypePath;

  // Stockage complet du raw json
  final Map<String, dynamic> rawJson;

  Projet({
    required this.nomProjet,
    required this.categorie,
    required this.surfaceHabitable,
    required this.descriptionMarketing,
    required this.nombreEtages,
    required this.detailsTechniques,
    required this.coutConstruction,
    required this.cheminDossier,
    required this.images,
    this.usage = '',
    this.archicadPath,
    this.twinmotionPath,
    this.estimTypePath,
    required this.rawJson,
  });

  // Création depuis JSON
  factory Projet.fromJson(
    Map<String, dynamic> json,
    String dossierProjet,
    String categorie,
    List<String> images, {
    String? archicadPath,
    String? twinmotionPath,
    String? estimTypePath,
  }) {
    return Projet(
      nomProjet: json['nom_projet'] ?? 'Projet sans nom',
      categorie: categorie,
      surfaceHabitable: double.tryParse(
              (json['surface_habitable_m2'] ?? 0).toString()) ?? 0.0,
      descriptionMarketing: json['description_marketing'] ?? '',
      nombreEtages: json['nombre_etages'] ?? 1,
      detailsTechniques: json['details_techniques'] ?? {},
      coutConstruction: double.tryParse(
              (((json['financier'] ?? {})['cout_construction_estime_fcfa']) ?? 0)
                  .toString()) ?? 0.0,
      cheminDossier: dossierProjet,
      images: images,
      usage: json['usage'] ?? '',
      archicadPath: archicadPath,
      twinmotionPath: twinmotionPath,
      estimTypePath: estimTypePath,
      rawJson: json,
    );
  }

  // Getters utiles
  bool get hasArchicad => archicadPath != null;
  bool get hasTwinmotion => twinmotionPath != null;
  bool get hasEstimType => estimTypePath != null;

  int get nombreChambres => detailsTechniques['chambres'] ?? 0;
  int get nombreSalons => detailsTechniques['salons'] ?? 0;

  String get budgetFormate {
    if (coutConstruction == 0) return 'Non renseigné';
    return '${coutConstruction.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ')} FCFA';
  }

  String get imageVignette => images.isNotEmpty ? images.first : '';
  bool get hasImages => images.isNotEmpty;
}
