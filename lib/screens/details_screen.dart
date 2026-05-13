import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/projet_model.dart';
import '../services/storage_service.dart';
import '../widgets/image_carousel.dart';
import 'estim_batiment_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Projet projet;
  /// Source image initiale : 'A' = Portrait, 'B' = Landscape, 'P' = Plans, null = défaut
  final String? initialImageSource;
  const DetailsScreen({Key? key, required this.projet, this.initialImageSource}) : super(key: key);

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  // ── Structure dossiers (éditables, persistées) ────────────────────────────
  static const _kPrefKey = 'folder_structure_v1';
  static const _defaultStructure = [
    'Autre',
    'Pdf',
    'Source',
    'Png',
    'Png/Plans',
    'Png/1080x1350_4-5_Portrait',
    'Png/1920x1080_16-9_Landscape',
  ];
  List<String> _structure = List.of(_defaultStructure);

  // ── Flags structure ───────────────────────────────────────────────────────
  bool _structureExiste = false;
  bool _estimTypeExiste = false;
  bool _hasInfosJson    = false;

  // ── Projet ────────────────────────────────────────────────────────────────
  late Projet _projet;

  // ── UI ────────────────────────────────────────────────────────────────────
  bool _descriptionExpanded    = false;
  bool _caracteristiquesExpanded = false; // rabattu par défaut

  // ── Image carousel ───────────────────────────────────────────────────────
  List<String> _currentImages = [];
  String? _activeImageSource; // null=défaut, 'A', 'B', 'P'

  // ── Scan dossier ─────────────────────────────────────────────────────────
  List<Directory> _sousDossiers = [];
  List<File>      _pdfFiles     = [];
  bool _pngAExists = false, _pngBExists = false, _pngPExists = false;

  // ── Fichiers spéciaux (extensions connues) ────────────────────────────────
  File? _plnFile, _bpnFile, _tmFile, _xlsxFile;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _projet        = widget.projet;
    _currentImages = List.of(_projet.images);
    // Source image initiale (nouveau projet → portrait)
    if (widget.initialImageSource != null) {
      _activeImageSource = widget.initialImageSource;
    }
    // Vérifier si infos.json existe
    _hasInfosJson = File(
      '${_projet.cheminDossier}${Platform.pathSeparator}infos.json',
    ).existsSync();
    _loadStructure();
    _verifierStructure();
    _scanDossier();
  }

  // ── Persistance structure ─────────────────────────────────────────────────
  Future<void> _loadStructure() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kPrefKey);
    if (saved != null && mounted) setState(() => _structure = saved);
  }

  Future<void> _saveStructure(List<String> v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKey, v);
    if (mounted) setState(() => _structure = v);
  }

  // ── Vérifications ────────────────────────────────────────────────────────
  void _verifierStructure() {
    final sep  = Platform.pathSeparator;
    final base = _projet.cheminDossier;
    final ok   = _structure.every(
        (rel) => Directory(base + sep + rel.replaceAll('/', sep)).existsSync());
    if (mounted) {
      setState(() => _structureExiste = ok);
      if (ok) _verifierEstimType();
    }
  }

  void _verifierEstimType() {
    final chemin = _cheminEstimType;
    if (mounted) setState(() => _estimTypeExiste = File(chemin).existsSync());
  }

  // ── Scan complet du dossier projet ────────────────────────────────────────
  void _scanDossier() {
    final sep  = Platform.pathSeparator;
    final base = _projet.cheminDossier;
    if (!Directory(base).existsSync()) return;

    final sousDossiers = <Directory>[];
    final pdfFiles     = <File>[];
    bool  pngA = false, pngB = false, pngP = false;
    File? pln, bpn, tm, xlsx;
    final rootImages   = <String>[];
    const imgExts = {'.jpg', '.jpeg', '.png', '.JPG', '.JPEG', '.PNG'};

    try {
      for (final e in Directory(base).listSync()) {
        if (e is Directory) sousDossiers.add(e);
        if (e is File) {
          final low = e.path.toLowerCase();
          if (low.endsWith('.pln'))  pln  = e;
          if (low.endsWith('.bpn'))  bpn  = e;
          if (low.endsWith('.tm'))   tm   = e;
          if (low.endsWith('.xlsx')) xlsx = e;
          // Images dans le dossier racine du projet (vignette.png, etc.)
          final ext = e.path.contains('.')
              ? e.path.substring(e.path.lastIndexOf('.'))
              : '';
          if (imgExts.contains(ext)) {
            final nom = e.path.split(sep).last.toLowerCase();
            // vignettes en premier
            if (nom.startsWith('vignette')) {
              rootImages.insert(0, e.path);
            } else {
              rootImages.add(e.path);
            }
          }
        }
      }
      // PDF
      final pdfDir = Directory('$base${sep}Pdf');
      if (pdfDir.existsSync()) {
        pdfFiles.addAll(pdfDir.listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf')));
      }
      // PNG sub-dirs
      pngA = Directory('$base${sep}Png${sep}1080x1350_4-5_Portrait').existsSync();
      pngB = Directory('$base${sep}Png${sep}1920x1080_16-9_Landscape').existsSync();
      pngP = Directory('$base${sep}Png${sep}Plans').existsSync();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _sousDossiers = sousDossiers;
        _pdfFiles     = pdfFiles;
        _pngAExists   = pngA;
        _pngBExists   = pngB;
        _pngPExists   = pngP;
        _plnFile      = pln  ?? ((_projet.archicadPath   != null) ? File(_projet.archicadPath!)   : null);
        _bpnFile      = bpn  ?? ((_projet.twinmotionPath != null) ? File(_projet.twinmotionPath!) : null);
        _tmFile       = tm;
        _xlsxFile     = xlsx ?? ((_projet.estimTypePath  != null) ? File(_projet.estimTypePath!)  : null);
        // Mettre à jour le carousel avec les images du dossier racine
        // si on n'est pas en train d'afficher un sous-dossier PNG explicite
        if (rootImages.isNotEmpty && _activeImageSource == null) {
          final existing = Set<String>.from(_currentImages);
          final nouvelles = rootImages.where((p) => !existing.contains(p)).toList();
          if (nouvelles.isNotEmpty || _currentImages.isEmpty) {
            // Vignettes en tête, puis reste
            final vignettes = rootImages.where((p) => p.split(sep).last.toLowerCase().startsWith('vignette')).toList();
            final autres    = rootImages.where((p) => !p.split(sep).last.toLowerCase().startsWith('vignette')).toList();
            _currentImages  = [...vignettes, ...autres];
          }
        }
      });
    }
  }

  // ── Images carousel dynamique ─────────────────────────────────────────────
  void _loadImagesFromPng(String source) {
    final sep     = Platform.pathSeparator;
    final subName = {'A': '1080x1350_4-5_Portrait', 'B': '1920x1080_16-9_Landscape', 'P': 'Plans'}[source]!;
    final dir     = Directory('${_projet.cheminDossier}${sep}Png$sep$subName');
    if (!dir.existsSync()) return;
    final imgs = dir.listSync().whereType<File>().where((f) {
      final l = f.path.toLowerCase();
      return l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg');
    }).map((f) => f.path).toList()..sort();
    if (imgs.isNotEmpty && mounted) setState(() { _currentImages = imgs; _activeImageSource = source; });
  }

  void _resetToDefaultImages() =>
      setState(() { _currentImages = List.of(_projet.images); _activeImageSource = null; });

  // ── Actions fichiers ──────────────────────────────────────────────────────
  Future<void> _ouvrirFichier(String chemin) async {
    final uri = Uri.file(chemin);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _ouvrirDossier() => _ouvrirFichier(_projet.cheminDossier);

  Future<void> _ouvrirSousDossier(Directory dir) => _ouvrirFichier(dir.path);

  Future<void> _ouvrirIllustrator() =>
      _ouvrirFichier(r'H:\Mon Drive\Catalogue\MODIFIER.ai');

  void _ouvrirEstimBat() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => EstimBatimentScreen(fichierInitial: _cheminEstimType),
    ));
  }

  Future<void> _verifierOuCreerStructure() async {
    final sep  = Platform.pathSeparator;
    final base = _projet.cheminDossier;
    final tous = _structure.every(
        (r) => Directory(base + sep + r.replaceAll('/', sep)).existsSync());
    if (tous) {
      _showResultat(message: 'Structure déjà existante',
          icon: Icons.folder_special_rounded, color: const Color(0xFFE67E22));
      return;
    }
    for (final r in _structure) {
      await Directory(base + sep + r.replaceAll('/', sep)).create(recursive: true);
    }
    if (!mounted) return;
    setState(() => _structureExiste = true);
    _verifierEstimType();
    _scanDossier();
    _showResultat(message: 'Structure créée avec succès',
        icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32));
  }

  String get _cheminEstimType {
    final sep = Platform.pathSeparator;
    return '${_projet.cheminDossier}${sep}Autre${sep}EstimType.xlsx';
  }

  Future<void> _creerEstimType() async {
    final sep        = Platform.pathSeparator;
    final destination = _cheminEstimType;

    // Template à la racine du catalogue
    final catalogueRoot = StorageService().getCataloguePath();
    if (catalogueRoot == null) {
      _showResultat(
        message: 'Chemin du catalogue introuvable. Configurez-le d\'abord.',
        icon: Icons.error_rounded, color: Colors.red);
      return;
    }

    // Cherche EstimType.xlsx OU EstimType2.xlsx à la racine du catalogue
    File? template;
    for (final name in ['EstimType.xlsx', 'EstimType2.xlsx', 'estim_type.xlsx']) {
      final f = File('$catalogueRoot$sep$name');
      if (f.existsSync()) { template = f; break; }
    }
    if (template == null) {
      _showResultat(
        message: 'Modèle EstimType.xlsx introuvable à la racine du catalogue.',
        icon: Icons.error_rounded, color: Colors.red);
      return;
    }

    // Si déjà présent, demander confirmation
    if (File(destination).existsSync()) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remplacer EstimType.xlsx ?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: const Text('Un fichier EstimType.xlsx existe déjà dans Autre/.'
              '\nVoulez-vous le remplacer par le modèle du catalogue ?',
              style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    try {
      // Créer le dossier Autre/ si absent
      final autreDir = Directory('${_projet.cheminDossier}${sep}Autre');
      if (!autreDir.existsSync()) await autreDir.create(recursive: true);

      await template.copy(destination);
      if (mounted) {
        setState(() {
          _estimTypeExiste = true;
          _xlsxFile = File(destination);
        });
        _showResultat(
          message: 'EstimType.xlsx créé dans Autre/',
          icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32));
      }
    } catch (e) {
      if (mounted) {
        _showResultat(message: 'Erreur : $e',
            icon: Icons.error_rounded, color: Colors.red);
      }
    }
  }

  Future<void> _creerInfosJson() async {
    final sep      = Platform.pathSeparator;
    final jsonFile = File('${_projet.cheminDossier}${sep}infos.json');

    final emptyData = <String, dynamic>{'nom_projet': _projet.nomProjet};
    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _JsonEditorPage(
          data: emptyData,
          titre: _projet.nomProjet,
          pageTitle: 'Créer les informations',
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        await jsonFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(result));
        setState(() {
          _hasInfosJson = true;
          _projet = Projet.fromJson(
            result, _projet.cheminDossier, _projet.categorie, _projet.images,
            archicadPath: _projet.archicadPath,
            twinmotionPath: _projet.twinmotionPath,
            estimTypePath: _projet.estimTypePath,
          );
        });
        _showResultat(
          message: 'infos.json créé avec succès',
          icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32));
      } catch (e) {
        _showResultat(
          message: 'Erreur: $e', icon: Icons.error_rounded, color: Colors.red);
      }
    }
  }

  Future<void> _editerInfosJson() async {
    final sep     = Platform.pathSeparator;
    final jsonFile = File('${_projet.cheminDossier}${sep}infos.json');
    if (!jsonFile.existsSync()) {
      _showResultat(message: 'infos.json introuvable',
          icon: Icons.error_rounded, color: Colors.red);
      return;
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      _showResultat(message: 'Erreur lecture: $e',
          icon: Icons.error_rounded, color: Colors.red);
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _JsonEditorPage(data: data, titre: _projet.nomProjet)),
    );
    if (result != null && mounted) {
      try {
        await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
        setState(() {
          _projet = Projet.fromJson(result, _projet.cheminDossier, _projet.categorie,
              _projet.images, archicadPath: _projet.archicadPath,
              twinmotionPath: _projet.twinmotionPath, estimTypePath: _projet.estimTypePath);
        });
        _showResultat(message: 'Sauvegardé',
            icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32));
      } catch (e) {
        _showResultat(message: 'Erreur: $e', icon: Icons.error_rounded, color: Colors.red);
      }
    }
  }

  // ── Dialog paramètres structure ───────────────────────────────────────────
  Future<void> _showStructureSettings() async {
    final ctrl = TextEditingController(text: _structure.join('\n'));
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Structure de dossiers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Un dossier par ligne. Utilisez / pour les sous-dossiers.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5F6368))),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 10,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true, fillColor: const Color(0xFFF5F7FA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDDE1E7))),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 15),
                label: const Text('Restaurer les valeurs par défaut', style: TextStyle(fontSize: 12)),
                onPressed: () { ctrl.text = _defaultStructure.join('\n'); },
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              final lines = ctrl.text.split('\n')
                  .map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
              Navigator.pop(ctx, lines);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B8ED0), foregroundColor: Colors.white, elevation: 0),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != null) await _saveStructure(saved);
  }

  void _showResultat({required String message, required IconData icon, required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, width: 340,
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.white, elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        Icon(icon, color: color, size: 22), const SizedBox(width: 12),
        Expanded(child: Text(message,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B8ED0)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('← Retour à la galerie',
              style: TextStyle(color: Color(0xFF3B8ED0), fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        actions: [
          // Créer infos (quand infos.json n'existe pas encore)
          if (!_hasInfosJson)
            IconButton(
              tooltip: 'Créer les informations (nouveau fichier infos.json)',
              icon: const Icon(Icons.note_add_rounded, color: Color(0xFF2E7D32)),
              onPressed: _creerInfosJson,
            ),
          // Modifier infos (quand infos.json existe)
          if (_hasInfosJson)
            IconButton(
              tooltip: 'Modifier les infos',
              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF3B8ED0)),
              onPressed: _editerInfosJson,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1100;
        final carousel = ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(children: [
            ImageCarousel(
              key: ValueKey(_activeImageSource ?? 'default'),
              images: _currentImages,
            ),
            if (_activeImageSource != null)
              Positioned(
                top: 10, left: 10,
                child: GestureDetector(
                  onTap: _resetToDefaultImages,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        _activeImageSource == 'A' ? 'Portrait 4:5'
                            : _activeImageSource == 'B' ? 'Paysage 16:9'
                            : 'Plans',
                        style: const TextStyle(color: Colors.white, fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        );

        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3,
                child: Padding(padding: const EdgeInsets.all(20), child: carousel)),
            Expanded(flex: 1,
              child: Container(
                margin: const EdgeInsets.only(top: 20, right: 20, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildInfoContent(),
                ),
              ),
            ),
          ]);
        }
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: Padding(padding: const EdgeInsets.all(15), child: carousel),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              ),
              padding: const EdgeInsets.all(25),
              child: _buildInfoContent(),
            ),
          ]),
        );
      }),
    );
  }

  // ── Panneau droit ──────────────────────────────────────────────────────────
  Widget _buildInfoContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tags
        Wrap(spacing: 8, runSpacing: 8, children: [
          _buildTag(_projet.categorie),
          if (_projet.usage.isNotEmpty) _buildTag(_projet.usage),
        ]),
        const SizedBox(height: 12),
        // Titre
        Text(_projet.nomProjet,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const SizedBox(height: 10),

        // Description rabattable
        if (_projet.descriptionMarketing.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedCrossFade(
                firstChild: Text(_projet.descriptionMarketing,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[800])),
                secondChild: Text(_projet.descriptionMarketing,
                    style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[800])),
                crossFadeState: _descriptionExpanded
                    ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
              if (_projet.descriptionMarketing.length > 120) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(_descriptionExpanded ? 'Réduire' : 'Lire la suite',
                        style: const TextStyle(color: Color(0xFF3B8ED0),
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Caractéristiques (rabattu par défaut)
        InkWell(
          onTap: () => setState(() => _caracteristiquesExpanded = !_caracteristiquesExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Text('CARACTÉRISTIQUES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      letterSpacing: 1.2, color: Color(0xFF3B8ED0))),
              const Spacer(),
              Icon(_caracteristiquesExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: const Color(0xFF3B8ED0)),
            ]),
          ),
        ),
        if (_caracteristiquesExpanded) ...[
          const Divider(height: 12),
          ..._buildRecursiveDetails(_projet.rawJson),
        ],
        const Divider(height: 20),

        // Coût estimé
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Coût estimé', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          Text(_projet.budgetFormate,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32))),
        ]),
        const SizedBox(height: 16),

        // ── Barre d'actions : 3 icônes ────────────────────────────────────────
        Row(children: [
          _actionBtn(
            icon: Icons.folder_open_rounded,
            tooltip: 'Ouvrir le dossier',
            color: const Color(0xFF3B8ED0),
            onTap: _ouvrirDossier,
          ),
          const SizedBox(width: 8),
          _actionBtn(
            icon: _structureExiste ? Icons.check_circle_rounded : Icons.create_new_folder_rounded,
            tooltip: _structureExiste ? 'Structure déjà créée' : 'Créer la structure de dossiers',
            color: _structureExiste ? const Color(0xFF2E7D32) : const Color(0xFF607D8B),
            onTap: _verifierOuCreerStructure,
          ),
          const SizedBox(width: 8),
          _actionBtn(
            icon: Icons.tune_rounded,
            tooltip: 'Paramètres de la structure',
            color: const Color(0xFF9E9E9E),
            onTap: _showStructureSettings,
          ),
        ]),
        const SizedBox(height: 12),

        // ── Explorateur ───────────────────────────────────────────────────────
        _buildExplorer(),

        const SizedBox(height: 12),

        // ── Boutons AI + ES ───────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: _wideBtn(
              icon: Icons.brush_rounded,
              label: 'AI',
              tooltip: 'Ouvrir MODIFIER.ai',
              color: const Color(0xFF7B1FA2),
              onTap: _ouvrirIllustrator,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _wideBtn(
              icon: Icons.calculate_rounded,
              label: 'ES',
              tooltip: 'EstimBatiment',
              color: _estimTypeExiste ? const Color(0xFF2E7D32) : const Color(0xFF78909C),
              onTap: _ouvrirEstimBat,
            ),
          ),
          // Bouton créer EstimType.xlsx — visible seulement quand absent
          if (!_estimTypeExiste) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Créer EstimType.xlsx dans Autre/ (copie du modèle catalogue)',
              child: InkWell(
                onTap: _creerEstimType,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_chart_rounded,
                      size: 18, color: Color(0xFF2E7D32)),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Explorateur visuel ────────────────────────────────────────────────────
  Widget _buildExplorer() {
    final hasSpecial = _plnFile != null || _bpnFile != null || _tmFile != null || _xlsxFile != null;
    final hasPng     = _pngAExists || _pngBExists || _pngPExists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fichiers spéciaux
        if (hasSpecial) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (_plnFile != null)
              _fileChip(label: 'Pln', icon: Icons.architecture_rounded,
                  color: const Color(0xFF1565C0), onTap: () => _ouvrirFichier(_plnFile!.path)),
            if (_bpnFile != null)
              _fileChip(label: 'Bpn', icon: Icons.view_in_ar_rounded,
                  color: const Color(0xFF00695C), onTap: () => _ouvrirFichier(_bpnFile!.path)),
            if (_tmFile != null)
              _fileChip(label: 'Tm', icon: Icons.threed_rotation_rounded,
                  color: const Color(0xFF37474F), onTap: () => _ouvrirFichier(_tmFile!.path)),
            if (_xlsxFile != null)
              _fileChip(label: 'Excel', icon: Icons.table_chart_rounded,
                  color: const Color(0xFF2E7D32), onTap: () => _ouvrirFichier(_xlsxFile!.path)),
          ]),
          const SizedBox(height: 10),
        ],

        // Dossiers présents
        if (_sousDossiers.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final dir in _sousDossiers)
              _folderChip(dir),
          ]),
          const SizedBox(height: 10),
        ],

        // Contenu PDF
        if (_pdfFiles.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in _pdfFiles)
              Tooltip(
                message: f.path.split(Platform.pathSeparator).last,
                child: InkWell(
                  onTap: () => _ouvrirFichier(f.path),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF9A9A)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFC62828)),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: Text(
                          f.path.split(Platform.pathSeparator).last.replaceAll('.pdf', ''),
                          style: const TextStyle(fontSize: 11, color: Color(0xFFC62828),
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
        ],

        // Boutons PNG A / B / P
        if (hasPng) ...[
          Row(children: [
            if (_pngAExists) ...[
              _pngBtn(label: 'A', tooltip: 'Portrait 4:5 (1080×1350)',
                  active: _activeImageSource == 'A', onTap: () => _loadImagesFromPng('A')),
              const SizedBox(width: 6),
            ],
            if (_pngBExists) ...[
              _pngBtn(label: 'B', tooltip: 'Paysage 16:9 (1920×1080)',
                  active: _activeImageSource == 'B', onTap: () => _loadImagesFromPng('B')),
              const SizedBox(width: 6),
            ],
            if (_pngPExists) ...[
              _pngBtn(label: 'P', tooltip: 'Plans',
                  active: _activeImageSource == 'P', onTap: () => _loadImagesFromPng('P')),
            ],
          ]),
        ],
      ],
    );
  }

  // ── Widgets helpers ───────────────────────────────────────────────────────

  Widget _actionBtn({required IconData icon, required String tooltip,
      required Color color, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Widget _wideBtn({required IconData icon, required String label,
      required String tooltip, required Color color, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _fileChip({required String label, required IconData icon,
      required Color color, required VoidCallback onTap}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _folderChip(Directory dir) {
    final name = dir.path.split(Platform.pathSeparator).last;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: () => _ouvrirSousDossier(dir),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDADCE0)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_rounded, size: 14, color: Color(0xFFE8A000)),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(name,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF3C4043)),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pngBtn({required String label, required String tooltip,
      required bool active, required VoidCallback onTap}) {
    const activeColor = Color(0xFF0D47A1);
    final color       = active ? activeColor : const Color(0xFF607D8B);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: active ? activeColor : const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? activeColor : const Color(0xFFDADCE0)),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: active ? Colors.white : color)),
          ),
        ),
      ),
    );
  }

  // ── Caractéristiques récursives ───────────────────────────────────────────
  List<Widget> _buildRecursiveDetails(Map<String, dynamic> map, {int depth = 0}) {
    final rows       = <Widget>[];
    final ignoreKeys = depth == 0
        ? ['nom_projet', 'description_marketing', 'financier', 'tags'] : <String>[];
    map.forEach((key, value) {
      if (ignoreKeys.contains(key) || value == null) return;
      final tk = (key.replaceAll('_', ' ')).replaceFirst(key[0], key[0].toUpperCase());
      if (value is Map) {
        rows.add(Padding(
          padding: EdgeInsets.only(top: 8, bottom: 2, left: depth * 14.0),
          child: Text(tk.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold,
                  color: Color(0xFF5F6368), fontSize: 10)),
        ));
        rows.addAll(_buildRecursiveDetails(
            Map<String, dynamic>.from(value), depth: depth + 1));
      } else if (value is List) {
        if (value.isNotEmpty) rows.add(_buildDetailRow(tk, value.join(', '), depth: depth));
      } else {
        if (value.toString().isNotEmpty) {
          rows.add(_buildDetailRow(tk, value.toString(), depth: depth));
        }
      }
    });
    return rows;
  }

  Widget _buildTag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: const Color(0xFFD3E3FD), borderRadius: BorderRadius.circular(6)),
    child: Text(text.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
            color: Color(0xFF174EA6))),
  );

  Widget _buildDetailRow(String label, String value, {int depth = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: 5, bottom: 5, left: depth * 14.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(flex: 3,
              child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF5F6368)))),
          const SizedBox(width: 10),
          Flexible(flex: 4,
            child: Text(value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF202124))),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Éditeur JSON intelligent
// ═══════════════════════════════════════════════════════════════════════════════

class _JsonEditorPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String titre;
  final String pageTitle;
  const _JsonEditorPage({
    required this.data,
    required this.titre,
    this.pageTitle = 'Modifier les informations',
  });

  @override
  State<_JsonEditorPage> createState() => _JsonEditorPageState();
}

class _JsonEditorPageState extends State<_JsonEditorPage> {
  late Map<String, dynamic> _data;

  // ── SharedPreferences keys pour les modèles ──────────────────────────────
  static const _kTemplateNames = 'editor_template_names';
  static String _kTemplateKey(String name) => 'editor_template_$name';

  @override
  void initState() {
    super.initState();
    _data = jsonDecode(jsonEncode(widget.data)) as Map<String, dynamic>;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static const _kBlue   = Color(0xFF3B8ED0);
  static const _kGreen  = Color(0xFF2E7D32);
  static const _kBg     = Color(0xFFF5F7FA);

  // ─────────────────────────────────────────────────────────────────────────
  // Modèles — Sauvegarde
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController();
    // Pré-remplir avec le titre du projet si disponible
    nameCtrl.text = widget.titre.isNotEmpty ? widget.titre : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.bookmark_add_rounded, color: Color(0xFF3B8ED0), size: 20),
          SizedBox(width: 8),
          Text('Sauvegarder comme modèle',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nom du modèle :',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF5F6368))),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Ex : Villa standard, Bureau type A…',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dCtx, true),
            icon: const Icon(Icons.bookmark_added_rounded, size: 15),
            label: const Text('Enregistrer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (confirmed != true || name.isEmpty || !mounted) return;

    final prefs    = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_kTemplateNames) ?? [];
    if (!existing.contains(name)) existing.add(name);
    await prefs.setStringList(_kTemplateNames, existing);
    // Sauvegarder la structure (sans les valeurs, seulement les clés/types)
    await prefs.setString(_kTemplateKey(name),
        const JsonEncoder().convert(_dataToTemplate(_data)));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, width: 320,
      backgroundColor: Colors.white, elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        const Icon(Icons.bookmark_added_rounded,
            color: Color(0xFF2E7D32), size: 20),
        const SizedBox(width: 10),
        Text('Modèle "$name" enregistré',
            style: const TextStyle(color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    ));
  }

  /// Convertit `_data` en structure-modèle : conserve clés + type, vide les valeurs.
  Map<String, dynamic> _dataToTemplate(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (v is Map) {
        out[k] = _dataToTemplate(Map<String, dynamic>.from(v));
      } else if (v is List) {
        out[k] = v.map((e) => e is Map
            ? _dataToTemplate(Map<String, dynamic>.from(e)) : '').toList();
      } else if (v is bool) {
        out[k] = false;
      } else if (v is num) {
        out[k] = 0;
      } else {
        out[k] = '';
      }
    });
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Modèles — Sélection / Chargement
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _selectTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_kTemplateNames) ?? [];

    if (!mounted) return;
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun modèle enregistré.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // État local du dialog
    String? selectedName = names.first;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.checklist_rounded, color: Color(0xFF3B8ED0), size: 20),
            SizedBox(width: 8),
            Text('Sélectionner un modèle',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          content: SizedBox(
            width: 400,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: names.map((n) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: selectedName == n
                          ? const Color(0xFFE8F0FE) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedName == n
                            ? _kBlue : const Color(0xFFDDE1E7)),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        selectedName == n
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selectedName == n ? _kBlue : Colors.grey,
                        size: 20,
                      ),
                      title: Text(n, style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w500)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 16, color: Color(0xFFEF5350)),
                        tooltip: 'Supprimer ce modèle',
                        onPressed: () async {
                          final del = await showDialog<bool>(
                            context: ctx,
                            builder: (d2) => AlertDialog(
                              title: Text('Supprimer "$n" ?',
                                  style: const TextStyle(fontSize: 14)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d2, false),
                                  child: const Text('Annuler')),
                                TextButton(
                                  onPressed: () => Navigator.pop(d2, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: const Text('Supprimer')),
                              ],
                            ),
                          );
                          if (del != true) return;
                          final p = await SharedPreferences.getInstance();
                          final lst = p.getStringList(_kTemplateNames) ?? [];
                          lst.remove(n);
                          await p.setStringList(_kTemplateNames, lst);
                          await p.remove(_kTemplateKey(n));
                          setS(() {
                            names.remove(n);
                            if (selectedName == n) {
                              selectedName = names.isNotEmpty
                                  ? names.first : null;
                            }
                          });
                        },
                      ),
                      onTap: () => setS(() => selectedName = n),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton.icon(
              onPressed: selectedName == null
                  ? null
                  : () => Navigator.pop(dCtx, true),
              icon: const Icon(Icons.download_rounded, size: 15),
              label: const Text('Charger'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedName == null || !mounted) return;

    final raw = prefs.getString(_kTemplateKey(selectedName!));
    if (raw == null) return;
    try {
      final tpl = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _data = tpl;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erreur chargement du modèle.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF5F6368)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.pageTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            Text(widget.titre,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ),
        actions: [
          // ── Sélectionner un modèle ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Tooltip(
              message: 'Charger un modèle de champs',
              child: OutlinedButton.icon(
                onPressed: _selectTemplate,
                icon: const Icon(Icons.checklist_rounded, size: 16),
                label: const Text('Modèles'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: const BorderSide(color: Color(0xFF3B8ED0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Sauvegarder comme modèle ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Tooltip(
              message: 'Sauvegarder la structure actuelle comme modèle réutilisable',
              child: OutlinedButton.icon(
                onPressed: _saveAsTemplate,
                icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                label: const Text('Sauver modèle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGreen,
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Sauvegarder le projet ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _data),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Sauvegarder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _MapEditor(map: _data, depth: 0, onChanged: () => setState(() {})),
      ),
    );
  }
}

// ── Éditeur d'un Map (récursif) ───────────────────────────────────────────────

class _MapEditor extends StatefulWidget {
  final Map<String, dynamic> map;
  final int depth;
  final VoidCallback onChanged;
  const _MapEditor({required this.map, required this.depth, required this.onChanged});

  @override
  State<_MapEditor> createState() => _MapEditorState();
}

class _MapEditorState extends State<_MapEditor> {
  void _refresh() {
    setState(() {});
    widget.onChanged();
  }

  String _label(String key) {
    final s = key.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  // Copie profonde pour la duplication
  dynamic _deepCopy(dynamic v) {
    if (v is Map)  return Map<String, dynamic>.from(v.map((k, e) => MapEntry(k.toString(), _deepCopy(e))));
    if (v is List) return v.map(_deepCopy).toList();
    return v;
  }

  void _renameKey(String oldKey, String newKey) {
    final trimmed = newKey.trim().replaceAll(' ', '_');
    if (trimmed.isEmpty || trimmed == oldKey || widget.map.containsKey(trimmed)) return;
    final entries = widget.map.entries.toList();
    final idx = entries.indexWhere((e) => e.key == oldKey);
    if (idx < 0) return;
    entries[idx] = MapEntry(trimmed, entries[idx].value);
    widget.map.clear();
    widget.map.addEntries(entries);
    _refresh();
  }

  void _duplicateKey(String key) {
    var suffix = 2;
    var newKey = '${key}_$suffix';
    while (widget.map.containsKey(newKey)) {
      suffix++;
      newKey = '${key}_$suffix';
    }
    final entries = widget.map.entries.toList();
    final idx = entries.indexWhere((e) => e.key == key);
    entries.insert(idx + 1, MapEntry(newKey, _deepCopy(widget.map[key])));
    widget.map.clear();
    widget.map.addEntries(entries);
    _refresh();
  }

  void _onReorder(int oldIdx, int newIdx) {
    setState(() {
      if (newIdx > oldIdx) newIdx--;
      final keys = widget.map.keys.toList();
      final moved = keys.removeAt(oldIdx);
      keys.insert(newIdx, moved);
      final reordered = <String, dynamic>{for (final k in keys) k: widget.map[k]};
      widget.map.clear();
      widget.map.addAll(reordered);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.map.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (keys.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _onReorder,
            children: [
              for (int i = 0; i < keys.length; i++)
                _buildEntry(keys[i], widget.map[keys[i]], i),
            ],
          ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: widget.depth * 16.0),
          child: _AddFieldRow(
            depth: widget.depth,
            onAdd: (key, value) {
              widget.map[key] = value;
              _refresh();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntry(String key, dynamic value, int index) {
    return Container(
      key: ValueKey(key),
      padding: EdgeInsets.only(left: widget.depth * 16.0),
      child: _FieldRow(
        rawKey: key,
        label: _label(key),
        value: value,
        depth: widget.depth,
        index: index,
        parentMap: widget.map,
        onChanged: (v) {
          widget.map[key] = v;
          _refresh();
        },
        onDelete: () {
          widget.map.remove(key);
          _refresh();
        },
        onChildChanged: _refresh,
        onRename: (nk) => _renameKey(key, nk),
        onDuplicate: () => _duplicateKey(key),
      ),
    );
  }
}

// ── Une ligne de champ ────────────────────────────────────────────────────────

class _FieldRow extends StatefulWidget {
  final String rawKey;
  final String label;
  final dynamic value;
  final int depth;
  final int index;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onChildChanged;
  final void Function(String newKey)? onRename;
  final VoidCallback? onDuplicate;
  // Contexte du parent pour l'IA (tous les champs du même niveau)
  final Map<String, dynamic>? parentMap;

  const _FieldRow({
    required this.rawKey,
    required this.label,
    required this.value,
    required this.depth,
    required this.index,
    required this.onChanged,
    required this.onDelete,
    required this.onChildChanged,
    this.onRename,
    this.onDuplicate,
    this.parentMap,
  });

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  late TextEditingController _ctrl;
  late TextEditingController _keyCtrl;
  late FocusNode _numFocus;
  bool _expanded   = true;
  bool _editingKey = false;
  bool _isAiLoading = false;

  static const _kBlue   = Color(0xFF3B8ED0);
  static const _kBorder = Color(0xFFDDE1E7);

  // ─────────────────────────────────────────────────────────────────────────
  // DeepSeek – constantes SharedPreferences
  // ─────────────────────────────────────────────────────────────────────────

  static const _kDsApiKey = 'deepseek_api_key';

  static const _kDsPromptMarketing = 'deepseek_prompt_marketing';
  static const _kDsDefaultMarketing =
      'Tu es un expert en marketing immobilier. '
      'En te basant sur les caractéristiques du projet fournies ci-dessous, '
      'rédige une description marketing concise et attractive (3 à 5 phrases). '
      'Retourne UNIQUEMENT la description rédigée, sans introduction ni explication.\n\n'
      'Données du projet :\n';

  static const _kDsPromptRepartition = 'deepseek_prompt_repartition';
  static const _kDsDefaultRepartition =
      'Tu es un assistant en architecture. '
      'À partir du JSON "superficies_pieces" fourni, pour chaque niveau (RDC, R+1…) '
      'compte les pièces par catégorie (chambres, salons, SDB, cuisine…) et génère '
      'une répartition courte (ex: "3 chambres, 1 salon, 1 cuisine, 2 SDB"). '
      'Les pièces similaires sont regroupées. '
      'Retourne UNIQUEMENT un objet JSON valide avec les mêmes clés de niveaux que le JSON fourni.\n\n'
      'Données :';

  static const _kDsPromptTags = 'deepseek_prompt_tags';
  static const _kDsDefaultTags =
      'Tu es un expert en immobilier. '
      'À partir des caractéristiques du projet ci-dessous, génère une liste de tags '
      'pertinents pour la recherche (type de bien, nombre de pièces, équipements, style…). '
      'Retourne UNIQUEMENT un tableau JSON de chaînes courtes (2-4 mots max par tag), '
      'sans introduction ni commentaire.\n\n'
      'Données du projet :\n';

  static const _kDsPromptDetails = 'deepseek_prompt_details_techniques';
  static const _kDsDefaultDetails =
      'Tu es un assistant en architecture. '
      'À partir du JSON "superficies_pieces" fourni (pièces par niveau), '
      'compte chaque type de pièce sur TOUS les niveaux (chambres, salons, SDB, cuisines, '
      'terrasses, balcons, magasins, etc.) et génère un objet JSON de détails techniques. '
      'Regroupe les pièces similaires (ex: "Chambre principale" + "Chambre 2" = Chambres: 2). '
      'Utilise des clés en français avec majuscule initiale, valeurs numériques entières. '
      'Retourne UNIQUEMENT un objet JSON valide, sans commentaire.\n\n'
      'Données :';

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers DeepSeek
  // ─────────────────────────────────────────────────────────────────────────

  /// Collecte tout le texte du formulaire pour le contexte IA.
  String _collectContext() {
    final buf = StringBuffer();
    void walk(dynamic node, String prefix) {
      if (node is Map) {
        node.forEach((k, v) => walk(v, '$prefix${k.toString().replaceAll('_', ' ')}: '));
      } else if (node is List) {
        if (node.isNotEmpty) buf.writeln('$prefix${node.join(', ')}');
      } else if (node != null) {
        final s = node.toString().trim();
        if (s.isNotEmpty) buf.writeln('$prefix$s');
      }
    }
    walk(widget.parentMap ?? {}, '');
    return buf.toString();
  }

  /// Appel HTTP bas niveau. Retourne le texte brut ou null en cas d'erreur.
  Future<String?> _dsRawCall(String apiKey, String content, {double temp = 0.5}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resp = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [{'role': 'user', 'content': content}],
          'temperature': temp,
        }),
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return null;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return (data['choices'] as List).first['message']['content'] as String;
      }
      final err = jsonDecode(resp.body);
      messenger.showSnackBar(SnackBar(
        content: Text('DeepSeek : ${err['error']?['message'] ?? 'Erreur ${resp.statusCode}'}'),
        backgroundColor: Colors.red[700],
      ));
      return null;
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(
        content: Text('Erreur réseau : $e'), backgroundColor: Colors.red[700]));
      return null;
    }
  }

  /// Récupère la clé API ; ouvre les paramètres si absente. Retourne null si absente.
  Future<String?> _dsGetApiKey(String promptKey, String defaultPrompt, String subtitle) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return null;
    final key = prefs.getString(_kDsApiKey) ?? '';
    if (key.isEmpty) {
      await _showPromptSettings(
        focusApiKey: true, promptKey: promptKey,
        defaultPrompt: defaultPrompt, subtitle: subtitle);
      return null;
    }
    return key;
  }

  /// Extrait un objet JSON `{ }` ou un tableau `[ ]` du texte brut de l'IA.
  dynamic _extractJson(String text) {
    final matchObj = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (matchObj != null) return jsonDecode(matchObj.group(0)!);
    final matchArr = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (matchArr != null) return jsonDecode(matchArr.group(0)!);
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Appels DeepSeek spécialisés
  // ─────────────────────────────────────────────────────────────────────────

  /// Description marketing → STRING.
  Future<void> _callDsMarketing() async {
    final apiKey = await _dsGetApiKey(
        _kDsPromptMarketing, _kDsDefaultMarketing, 'Description Marketing');
    if (apiKey == null) return;
    final prefs  = await SharedPreferences.getInstance();
    if (!mounted) return;
    final prompt = prefs.getString(_kDsPromptMarketing) ?? _kDsDefaultMarketing;

    setState(() => _isAiLoading = true);
    final text = await _dsRawCall(apiKey, '$prompt\n${_collectContext()}', temp: 0.7);
    if (!mounted) return;
    setState(() => _isAiLoading = false);
    if (text == null) return;
    _ctrl.text = text.trim();
    widget.onChanged(text.trim());
  }

  /// Répartition niveaux → JSON MAP remplace les valeurs existantes.
  Future<void> _callDsRepartition(Map<String, dynamic> mapV) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiKey    = await _dsGetApiKey(
        _kDsPromptRepartition, _kDsDefaultRepartition, 'Répartition Niveaux');
    if (apiKey == null) return;

    final superficies = widget.parentMap?['superficies_pieces'];
    if (superficies == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('"superficies_pieces" introuvable dans le formulaire.'),
        backgroundColor: Colors.orange));
      return;
    }
    final prefs  = await SharedPreferences.getInstance();
    if (!mounted) return;
    final prompt = prefs.getString(_kDsPromptRepartition) ?? _kDsDefaultRepartition;
    final ctx    = const JsonEncoder.withIndent('  ').convert(superficies);
    final levels = mapV.keys.join(', ');

    setState(() => _isAiLoading = true);
    final text = await _dsRawCall(
        apiKey, '$prompt\n\nNiveaux attendus : $levels\n\n$ctx', temp: 0.3);
    if (!mounted) return;
    setState(() => _isAiLoading = false);
    if (text == null) return;

    final parsed = _extractJson(text);
    if (parsed is Map) {
      final updated = Map<String, dynamic>.from(mapV);
      (parsed as Map).forEach((k, v) {
        final key = updated.keys.firstWhere(
          (ek) => ek.toLowerCase() == k.toString().toLowerCase(), orElse: () => k.toString());
        updated[key] = v.toString();
      });
      widget.onChanged(updated);
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('DeepSeek : réponse JSON invalide.'),
        backgroundColor: Colors.orange));
    }
  }

  /// Tags → JSON ARRAY, vide la liste et la remplace.
  Future<void> _callDsTags(List list) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiKey    = await _dsGetApiKey(_kDsPromptTags, _kDsDefaultTags, 'Tags');
    if (apiKey == null) return;
    final prefs  = await SharedPreferences.getInstance();
    if (!mounted) return;
    final prompt = prefs.getString(_kDsPromptTags) ?? _kDsDefaultTags;

    setState(() => _isAiLoading = true);
    final text = await _dsRawCall(apiKey, '$prompt\n${_collectContext()}', temp: 0.5);
    if (!mounted) return;
    setState(() => _isAiLoading = false);
    if (text == null) return;

    final parsed = _extractJson(text);
    if (parsed is List) {
      list
        ..clear()
        ..addAll(parsed.map((e) => e.toString()));
      widget.onChanged(list);
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('DeepSeek : réponse JSON invalide (tableau attendu).'),
        backgroundColor: Colors.orange));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Saisie rapide locale (ajoute / remplace) pour les niveaux superficies
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showQuickEditDialog(Map<String, dynamic> mapV) async {
    final ctrl  = TextEditingController();
    String inputText = '';

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF3B8ED0)),
          SizedBox(width: 8),
          Text('Saisie rapide des pièces', style: TextStyle(fontSize: 14)),
        ]),
        content: SizedBox(
          width: 500,
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Commencez par "ajoute" pour ajouter des pièces, ou "remplace" '
              'pour vider et remplacer tout le contenu.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5F6368)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Format : ajoute Chambre principale:12.67; Chambre 2:12.5; Salon:20',
              style: TextStyle(fontSize: 11, color: Color(0xFF9AA0A6),
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 5,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'ajoute Chambre principale:12.67; Chambre 2:12.5; Salon:19.88',
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              inputText = ctrl.text.trim();
              Navigator.pop(dCtx, true);
            },
            icon: const Icon(Icons.check_rounded, size: 15),
            label: const Text('Appliquer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B8ED0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    ctrl.dispose();
    if (confirm != true || inputText.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final lower = inputText.toLowerCase();
    final isReplace = lower.startsWith('remplace');
    final isAdd     = lower.startsWith('ajoute');

    if (!isReplace && !isAdd) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Commencez votre saisie par "ajoute" ou "remplace".'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final prefix = isReplace ? 'remplace' : 'ajoute';
    final rest   = inputText.substring(prefix.length).trim();

    final pairs = <String, dynamic>{};
    for (final part in rest.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx <= 0) continue;
      final key    = trimmed.substring(0, colonIdx).trim();
      final valStr = trimmed.substring(colonIdx + 1).trim().replaceAll(',', '.');
      if (key.isEmpty) continue;
      pairs[key] = double.tryParse(valStr) ?? valStr;
    }

    if (pairs.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Aucune paire clé:valeur reconnue.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    if (isReplace) mapV.clear();
    mapV.addAll(pairs);
    widget.onChanged(mapV);
  }

  /// Détails techniques → JSON MAP, remplace entièrement le contenu.
  Future<void> _callDsDetails(Map<String, dynamic> mapV) async {
    final messenger = ScaffoldMessenger.of(context);
    final apiKey    = await _dsGetApiKey(
        _kDsPromptDetails, _kDsDefaultDetails, 'Détails Techniques');
    if (apiKey == null) return;

    final superficies = widget.parentMap?['superficies_pieces'];
    if (superficies == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('"superficies_pieces" introuvable dans le formulaire.'),
        backgroundColor: Colors.orange));
      return;
    }
    final prefs  = await SharedPreferences.getInstance();
    if (!mounted) return;
    final prompt = prefs.getString(_kDsPromptDetails) ?? _kDsDefaultDetails;
    final ctx    = const JsonEncoder.withIndent('  ').convert(superficies);

    setState(() => _isAiLoading = true);
    final text = await _dsRawCall(apiKey, '$prompt\n\n$ctx', temp: 0.3);
    if (!mounted) return;
    setState(() => _isAiLoading = false);
    if (text == null) return;

    final parsed = _extractJson(text);
    if (parsed is Map) {
      final newMap = <String, dynamic>{};
      (parsed as Map).forEach((k, v) {
        final val = num.tryParse(v.toString()) ?? v.toString();
        newMap[k.toString()] = val;
      });
      widget.onChanged(newMap);
    } else {
      messenger.showSnackBar(const SnackBar(
        content: Text('DeepSeek : réponse JSON invalide.'),
        backgroundColor: Colors.orange));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Widget bouton DeepSeek réutilisable
  // ─────────────────────────────────────────────────────────────────────────

  Widget _dsButton({
    required VoidCallback? onAi,
    required VoidCallback onSettings,
    String label = 'Rédiger',
    String tooltip = 'Générer avec DeepSeek IA',
    String settingsTooltip = 'Paramètres DeepSeek',
  }) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: _isAiLoading ? null : onAi,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isAiLoading ? Colors.grey[700] : const Color(0xFF0E1117),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _isAiLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/icones/Deepseek.png',
                      width: 14, height: 14,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.auto_awesome, size: 13, color: Colors.white)),
                    const SizedBox(width: 4),
                    Text(label,
                        style: const TextStyle(fontSize: 11, color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ]),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Tooltip(
        message: settingsTooltip,
        child: InkWell(
          onTap: onSettings,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.settings_rounded, size: 14, color: Color(0xFF5F6368)),
          ),
        ),
      ),
    ]);
  }

  // ── Dialogue paramètres générique (prompt + clé API) ─────────────────────
  Future<void> _showPromptSettings({
    bool focusApiKey     = false,
    String promptKey     = _kDsPromptMarketing,
    String defaultPrompt = _kDsDefaultMarketing,
    String subtitle      = 'Description Marketing',
  }) async {
    final prefs      = await SharedPreferences.getInstance();
    final keyCtrl    = TextEditingController(text: prefs.getString(_kDsApiKey) ?? '');
    final promptCtrl = TextEditingController(
        text: prefs.getString(promptKey) ?? defaultPrompt);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.settings_rounded, size: 18, color: Color(0xFF3B8ED0)),
          const SizedBox(width: 8),
          Text('DeepSeek — $subtitle', style: const TextStyle(fontSize: 14)),
        ]),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Clé API DeepSeek',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5F6368))),
            const SizedBox(height: 4),
            TextField(
              controller: keyCtrl,
              autofocus: focusApiKey,
              obscureText: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'sk-...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Prompt (instructions pour DeepSeek)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5F6368))),
            const SizedBox(height: 4),
            TextField(
              controller: promptCtrl,
              maxLines: 8,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => promptCtrl.text = defaultPrompt,
              icon: const Icon(Icons.restore_rounded, size: 14),
              label: const Text('Rétablir le prompt par défaut', style: TextStyle(fontSize: 11)),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await prefs.setString(_kDsApiKey, keyCtrl.text.trim());
              await prefs.setString(promptKey, promptCtrl.text);
              if (dCtx.mounted) Navigator.pop(dCtx);
            },
            icon: const Icon(Icons.save_rounded, size: 15),
            label: const Text('Enregistrer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B8ED0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
    keyCtrl.dispose();
    promptCtrl.dispose();
  }

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _ctrl    = TextEditingController(
        text: (v == null || v is bool || v is Map || v is List) ? '' : v.toString());
    _keyCtrl = TextEditingController(text: widget.rawKey);
    _numFocus = FocusNode();
    _numFocus.addListener(() {
      if (!_numFocus.hasFocus && widget.value is num) {
        final committed = widget.value.toString();
        if (_ctrl.text != committed) _ctrl.text = committed;
      }
    });
  }

  @override
  void didUpdateWidget(_FieldRow old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v != old.value && v is! Map && v is! List && v is! bool) {
      final newText = v?.toString() ?? '';
      // Ne réinitialise le contrôleur que si le texte diffère réellement
      // (évite de casser le curseur/IME pendant la saisie sur Windows Desktop)
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _keyCtrl.dispose();
    _numFocus.dispose();
    super.dispose();
  }

  // ── Étiquette de clé modifiable au clic ─────────────────────────────────

  void _commitRename() {
    setState(() => _editingKey = false);
    widget.onRename?.call(_keyCtrl.text);
  }

  Widget _editableKey({bool big = false}) {
    if (_editingKey) {
      return SizedBox(
        height: 28,
        child: TextField(
          controller: _keyCtrl,
          autofocus: true,
          style: TextStyle(
              fontSize: big ? 12 : 13,
              fontWeight: big ? FontWeight.w700 : FontWeight.normal,
              color: big ? const Color(0xFF2C3E50) : const Color(0xFF5F6368)),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            border: UnderlineInputBorder(),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _kBlue)),
          ),
          onSubmitted: (_) => _commitRename(),
          onTapOutside: (_) { if (_editingKey) _commitRename(); },
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(() {
        _editingKey = true;
        _keyCtrl.text = widget.rawKey;
      }),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: big
            ? Text(widget.label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3E50), letterSpacing: 0.5))
            : Text(widget.label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5F6368))),
      ),
    );
  }

  // ── Bouton +▼ (dupliquer en-dessous) ────────────────────────────────────

  Widget _dupBtn() => SizedBox(
    width: 26,
    height: 32,
    child: Tooltip(
      message: 'Dupliquer en dessous',
      child: InkWell(
        onTap: widget.onDuplicate,
        borderRadius: BorderRadius.circular(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 10, color: Colors.grey[500]),
            Icon(Icons.arrow_drop_down, size: 12, color: Colors.grey[500]),
          ],
        ),
      ),
    ),
  );

  // ── Poignée de glissement ────────────────────────────────────────────────

  Widget _dragHandle() => ReorderableDragStartListener(
    index: widget.index,
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey[350]),
      ),
    ),
  );

  // ── Row compact ─────────────────────────────────────────────────────────

  Widget _rowWrap({required Widget child}) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: child);

  Widget _deleteBtn() => SizedBox(
    width: 28,
    height: 32,
    child: IconButton(
      icon: const Icon(Icons.remove_circle_outline, size: 15, color: Color(0xFFEF5350)),
      onPressed: widget.onDelete,
      padding: EdgeInsets.zero,
      tooltip: 'Supprimer',
    ),
  );

  InputDecoration _inputDeco({String? hint}) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _kBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _kBorder)),
  );

  @override
  Widget build(BuildContext context) {
    final v = widget.value;

    // ── BOOL ────────────────────────────────────────────────────────────────
    if (v is bool) {
      return _rowWrap(
        child: Row(children: [
          _dupBtn(),
          _dragHandle(),
          Expanded(child: _editableKey()),
          Switch(
            value: v,
            activeThumbColor: _kBlue,
            onChanged: widget.onChanged,
          ),
          _deleteBtn(),
        ]),
      );
    }

    // ── MAP (section / objet imbriqué) ──────────────────────────────────────
    if (v is Map) {
      final mapV        = Map<String, dynamic>.from(v);
      final rawKeyLower = widget.rawKey.toLowerCase();
      final isRep       = rawKeyLower.contains('repartition');
      final isDetails   = rawKeyLower.contains('details_tech') ||
                          rawKeyLower == 'details_techniques';
      // Niveau superficies (RDC, R+1…) : parent est un map-of-maps
      final isSuperfLevel = !isRep && !isDetails &&
          widget.parentMap != null &&
          widget.parentMap!.values.every((pv) => pv is Map);

      Widget? dsMapBtn;
      if (isRep) {
        dsMapBtn = _dsButton(
          onAi: () => _callDsRepartition(mapV),
          onSettings: () => _showPromptSettings(
            promptKey: _kDsPromptRepartition,
            defaultPrompt: _kDsDefaultRepartition,
            subtitle: 'Répartition Niveaux',
          ),
          tooltip: 'Remplir avec DeepSeek (basé sur Superficies pièces)',
        );
      } else if (isDetails) {
        dsMapBtn = _dsButton(
          onAi: () => _callDsDetails(mapV),
          onSettings: () => _showPromptSettings(
            promptKey: _kDsPromptDetails,
            defaultPrompt: _kDsDefaultDetails,
            subtitle: 'Détails Techniques',
          ),
          tooltip: 'Générer les détails techniques avec DeepSeek',
        );
      }

      // Bouton saisie rapide pour les niveaux superficies (RDC, R+1…)
      Widget? quickEditBtn;
      if (isSuperfLevel) {
        quickEditBtn = Tooltip(
          message: 'Saisie rapide : ajoute ou remplace les pièces',
          child: InkWell(
            onTap: () => _showQuickEditDialog(mapV),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_note_rounded, size: 13, color: Colors.white),
                SizedBox(width: 4),
                Text('Saisie', style: TextStyle(fontSize: 11,
                    color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Column(children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(children: [
                _dupBtn(),
                _dragHandle(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: _kBlue),
                const SizedBox(width: 4),
                Expanded(child: _editableKey(big: true)),
                if (quickEditBtn != null) ...[const SizedBox(width: 4), quickEditBtn],
                if (dsMapBtn != null) ...[const SizedBox(width: 4), dsMapBtn, const SizedBox(width: 2)],
                _deleteBtn(),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _MapEditor(
                map: mapV,
                depth: widget.depth + 1,
                onChanged: () { widget.onChanged(mapV); widget.onChildChanged(); },
              ),
            ),
        ]),
      );
    }

    // ── LIST ────────────────────────────────────────────────────────────────
    if (v is List) {
      final isTags = widget.rawKey == 'tags';

      return Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(children: [
                _dupBtn(),
                _dragHandle(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: _kBlue),
                const SizedBox(width: 4),
                Expanded(child: _editableKey(big: true)),
                Text('  (${v.length})',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                if (isTags) ...[
                  const SizedBox(width: 4),
                  _dsButton(
                    onAi: () => _callDsTags(v),
                    onSettings: () => _showPromptSettings(
                      promptKey: _kDsPromptTags,
                      defaultPrompt: _kDsDefaultTags,
                      subtitle: 'Tags',
                    ),
                    tooltip: 'Générer les tags avec DeepSeek',
                  ),
                  const SizedBox(width: 2),
                ],
                _deleteBtn(),
              ]),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _ListEditor(list: v, onChanged: () {
                widget.onChanged(v);
                widget.onChildChanged();
              }),
            ),
        ]),
      );
    }

    // ── NULL ────────────────────────────────────────────────────────────────
    if (v == null) {
      return _rowWrap(
        child: Row(children: [
          _dupBtn(),
          _dragHandle(),
          Expanded(child: _editableKey()),
          const SizedBox(width: 8),
          Expanded(flex: 2,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: _inputDeco(hint: 'null'),
              onChanged: (s) => widget.onChanged(s.isEmpty ? null : s),
            ),
          ),
          _deleteBtn(),
        ]),
      );
    }

    // ── NUMBER ──────────────────────────────────────────────────────────────
    if (v is num) {
      return _rowWrap(
        child: Row(children: [
          _dupBtn(),
          _dragHandle(),
          Expanded(child: _editableKey()),
          const SizedBox(width: 8),
          Expanded(flex: 2,
            child: TextField(
              controller: _ctrl,
              focusNode: _numFocus,
              style: const TextStyle(fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDeco(),
              onChanged: (s) {
                final n = num.tryParse(s.replaceAll(',', '.'));
                if (n != null) widget.onChanged(n);
              },
            ),
          ),
          _deleteBtn(),
        ]),
      );
    }

    // ── STRING ──────────────────────────────────────────────────────────────
    final isMarketing = widget.rawKey == 'description_marketing';
    final textField   = TextField(
      controller: _ctrl,
      style: const TextStyle(fontSize: 13),
      maxLines: isMarketing ? 5
          : (widget.value is String && (widget.value as String).length > 60 ? 3 : 1),
      decoration: _inputDeco(),
      onChanged: widget.onChanged,
    );

    if (isMarketing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dupBtn(),
            _dragHandle(),
            Expanded(child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _editableKey(),
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: textField),
            _deleteBtn(),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 28),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _dsButton(
                onAi: _callDsMarketing,
                onSettings: _showPromptSettings,
                label: 'Rédiger',
                tooltip: 'Rédiger avec DeepSeek IA',
              ),
            ]),
          ),
        ]),
      );
    }

    return _rowWrap(
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _dupBtn(),
        _dragHandle(),
        Expanded(child: _editableKey()),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: textField),
        _deleteBtn(),
      ]),
    );
  }
}

// ── Éditeur de liste ──────────────────────────────────────────────────────────

class _ListEditor extends StatefulWidget {
  final List list;
  final VoidCallback onChanged;
  const _ListEditor({required this.list, required this.onChanged});

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 6, runSpacing: 6,
        children: widget.list.asMap().entries.map((e) {
          final val = e.value;
          if (val is bool) {
            return _chip(
              label: val.toString(),
              color: val ? Colors.green : Colors.orange,
              onDelete: () { widget.list.removeAt(e.key); setState(() {}); widget.onChanged(); },
            );
          }
          return _chip(
            label: val.toString(),
            onDelete: () { widget.list.removeAt(e.key); setState(() {}); widget.onChanged(); },
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _addCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Ajouter un élément…',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFDDE1E7))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFDDE1E7))),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF3B8ED0), size: 20),
          onPressed: () {
            final s = _addCtrl.text.trim();
            if (s.isEmpty) return;
            widget.list.add(s);
            _addCtrl.clear();
            setState(() {});
            widget.onChanged();
          },
        ),
      ]),
    ]);
  }

  Widget _chip({required String label, Color? color, required VoidCallback onDelete}) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color ?? const Color(0xFF2C3E50))),
      deleteIcon: const Icon(Icons.close, size: 13),
      onDeleted: onDelete,
      backgroundColor: const Color(0xFFF0F4FF),
      side: const BorderSide(color: Color(0xFFDDE1E7)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Ajouter un nouveau champ ──────────────────────────────────────────────────

class _AddFieldRow extends StatefulWidget {
  final int depth;
  final void Function(String key, dynamic value) onAdd;
  const _AddFieldRow({required this.depth, required this.onAdd});

  @override
  State<_AddFieldRow> createState() => _AddFieldRowState();
}

class _AddFieldRowState extends State<_AddFieldRow> {
  final _keyCtrl = TextEditingController();
  String _type = 'Texte';
  bool _visible = false;

  static const _types = ['Texte', 'Nombre', 'Booléen', 'Liste', 'Objet'];

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  dynamic _defaultValue() {
    switch (_type) {
      case 'Nombre':   return 0;
      case 'Booléen':  return false;
      case 'Liste':    return [];
      case 'Objet':    return <String, dynamic>{};
      default:         return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_visible)
        TextButton.icon(
          onPressed: () => setState(() => _visible = true),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Ajouter un champ', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF3B8ED0)),
        )
      else
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDE1E7)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _keyCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Nom de la clé (ex: surface_m2)',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _type,
                items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) => setState(() => _type = v!),
                underline: const SizedBox.shrink(),
                isDense: true,
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              ElevatedButton(
                onPressed: () {
                  final k = _keyCtrl.text.trim().replaceAll(' ', '_');
                  if (k.isEmpty) return;
                  widget.onAdd(k, _defaultValue());
                  _keyCtrl.clear();
                  setState(() => _visible = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B8ED0), foregroundColor: Colors.white,
                  elevation: 0, minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Ajouter', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _visible = false),
                child: const Text('Annuler', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ]),
        ),
    ]);
  }
}
