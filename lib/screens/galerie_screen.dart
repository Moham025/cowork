// lib/screens/galerie_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/projet_model.dart';
import '../services/catalogue_service.dart';
import '../services/storage_service.dart';
import '../widgets/sidebar_filters.dart';
import '../widgets/projet_card.dart';
import 'details_screen.dart';

class GalerieScreen extends StatefulWidget {
  const GalerieScreen({Key? key}) : super(key: key);

  @override
  State<GalerieScreen> createState() => _GalerieScreenState();
}

class _GalerieScreenState extends State<GalerieScreen> {
  final _catalogueService = CatalogueService();
  final _storageService = StorageService();

  String _categorieActive = 'Tous';
  String _recherche = '';
  double _budgetMax = 0;
  List<Projet> _projetsFiltres = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _rafraichirGalerie();
  }

  void _rafraichirGalerie() {
    setState(() {
      _projetsFiltres = _catalogueService.filtrerProjets(
        categorie: _categorieActive,
        recherche: _recherche,
        budgetMax: _budgetMax,
      );
    });
  }

  Future<void> _changerDossier() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Sélectionnez le dossier Habitation',
    );

    if (selectedDirectory != null) {
      setState(() => _isLoading = true);

      final success =
          await _catalogueService.chargerCatalogue(selectedDirectory);

      if (success) {
        await _storageService.saveCataloguePath(selectedDirectory);
        _categorieActive = 'Tous';
        _rafraichirGalerie();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ Catalogue chargé: ${_catalogueService.projets.length} projets'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Erreur lors du chargement du catalogue'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      setState(() => _isLoading = false);
    }
  }

  // ── Créer un nouveau projet ───────────────────────────────────────────────
  Future<void> _creerProjet() async {
    final cataloguePath = _storageService.getCataloguePath();
    if (cataloguePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chargez un catalogue d\'abord.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final root = Directory(cataloguePath);
    if (!root.existsSync()) return;

    // Lister les dossiers-catégories existants
    final dirs = <String>[];
    for (final entity in root.listSync()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('.')) dirs.add(name);
      }
    }
    dirs.sort();

    if (!mounted) return;
    if (dirs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun dossier catégorie trouvé dans le catalogue.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // Compte les sous-dossiers (projets) dans une catégorie
    int countInCategory(String cat) {
      final catDir = Directory(
          '$cataloguePath${Platform.pathSeparator}$cat');
      if (!catDir.existsSync()) return 0;
      return catDir.listSync().whereType<Directory>().length;
    }

    String selectedCat = dirs.first;
    final nameCtrl = TextEditingController(
      text: '${selectedCat.toLowerCase()}_${countInCategory(selectedCat) + 1}',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.create_new_folder_rounded,
                color: Color(0xFF3B8ED0), size: 20),
            SizedBox(width: 8),
            Text('Créer un nouveau projet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Type de projet :',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5F6368))),
                const SizedBox(height: 6),
                // Liste des catégories avec radio
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: dirs.map((d) => InkWell(
                        onTap: () => setS(() {
                          selectedCat = d;
                          nameCtrl.text =
                              '${d.toLowerCase()}_${countInCategory(d) + 1}';
                        }),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 4),
                          child: Row(children: [
                            Icon(
                              selectedCat == d
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: selectedCat == d
                                  ? const Color(0xFF3B8ED0)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(d, style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                      )).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Nom du projet :',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5F6368))),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dCtx, true),
              icon: const Icon(Icons.create_rounded, size: 15),
              label: const Text('Créer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B8ED0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );

    final projectName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (confirmed != true || projectName.isEmpty || !mounted) return;

    final sep         = Platform.pathSeparator;
    final projectPath =
        '$cataloguePath$sep$selectedCat$sep$projectName';

    if (Directory(projectPath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Le dossier "$projectName" existe déjà dans "$selectedCat".'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // Créer l'arborescence de base
    try {
      for (final sub in [
        '',
        'Autre',
        'Pdf',
        'Source',
        'Png',
        'Png${sep}Plans',
        'Png${sep}1080x1350_4-5_Portrait',
        'Png${sep}1920x1080_16-9_Landscape',
      ]) {
        await Directory(
                sub.isEmpty ? projectPath : '$projectPath$sep$sub')
            .create(recursive: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur création dossier : $e'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // Construire un Projet minimal pour la navigation
    final newProjet = Projet(
      nomProjet:            projectName,
      categorie:            selectedCat,
      surfaceHabitable:     0,
      descriptionMarketing: '',
      nombreEtages:         1,
      detailsTechniques:    {},
      coutConstruction:     0,
      cheminDossier:        projectPath,
      images:               [],
      rawJson:              {},
    );

    if (!mounted) return;
    // Ouvrir le détail avec la source portrait active par défaut
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          projet: newProjet,
          initialImageSource: 'A',
        ),
      ),
    );

    // Recharger le catalogue pour inclure le nouveau projet s'il a un infos.json
    await _catalogueService.chargerCatalogue(cataloguePath);
    _rafraichirGalerie();
  }

  Future<void> _viderCacheEtLien() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation'),
        content: const Text(
          'Voulez-vous vraiment :\n\n'
          '🗑️ Vider le cache\n'
          '🔗 Supprimer le lien vers le catalogue\n\n'
          'Le dossier devra être choisi à nouveau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _catalogueService.viderCache();
      await _storageService.clearCataloguePath();
      await _storageService.clearRecentlyViewed();

      setState(() {
        _categorieActive = 'Tous';
        _projetsFiltres = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cache et lien supprimés'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Sidebar fixe à gauche
                SidebarFilters(
                  categorieActive: _categorieActive,
                  categories: _catalogueService.categories,
                  onCategorieChanged: (cat) {
                    setState(() => _categorieActive = cat);
                    _rafraichirGalerie();
                  },
                  onSearchChanged: (search) {
                    setState(() => _recherche = search);
                    _rafraichirGalerie();
                  },
                  budgetMax: _budgetMax,
                  onBudgetChanged: (budget) {
                    setState(() => _budgetMax = budget);
                    _rafraichirGalerie();
                  },
                  onChangerDossier: _changerDossier,
                  onViderCache: _viderCacheEtLien,
                ),

                // Zone principale : titre + grille
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Titre et compteur
                        Row(
                          children: [
                            Tooltip(
                              message: 'Tableau de bord',
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.home_rounded,
                                      size: 22, color: Color(0xFF3B8ED0)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _categorieActive == 'Tous'
                                  ? 'Tous les Projets'
                                  : 'Habitation / $_categorieActive',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '• ${_projetsFiltres.length} projets',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // ── Bouton Créer Projet ──────────────────────
                            Tooltip(
                              message: 'Créer un nouveau projet',
                              child: ElevatedButton.icon(
                                onPressed: _creerProjet,
                                icon: const Icon(Icons.create_new_folder_rounded,
                                    size: 16),
                                label: const Text('Créer projet'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B8ED0),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),

                        // Grille responsive
                        Expanded(
                          child: _projetsFiltres.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.folder_off,
                                          size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 20),
                                      Text(
                                        _catalogueService.projets.isEmpty
                                            ? 'Aucun catalogue chargé\n\nUtilisez "Changer dossier" pour charger un catalogue'
                                            : 'Aucun résultat',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    // Calcul du nombre de colonnes selon largeur disponible
                                    int crossAxisCount = 3;
                                    if (constraints.maxWidth > 1600) {
                                      crossAxisCount = 5;
                                    } else if (constraints.maxWidth > 1300) {
                                      crossAxisCount = 4;
                                    } else if (constraints.maxWidth < 1000) {
                                      crossAxisCount = 2;
                                    }

                                    return GridView.builder(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: 1.35,
                                        crossAxisSpacing: 1.2,
                                        mainAxisSpacing: 20,
                                      ),
                                      itemCount: _projetsFiltres.length,
                                      itemBuilder: (context, index) {
                                        final projet = _projetsFiltres[index];
                                        return ProjetCard(
                                          projet: projet,
                                          onTap: () {
                                            _storageService
                                                .addRecentlyViewed(
                                                    projet.cheminDossier);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    DetailsScreen(
                                                        projet: projet),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
