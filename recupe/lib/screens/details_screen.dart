import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/projet_model.dart';
import '../services/storage_service.dart';
import '../widgets/image_carousel.dart';

class DetailsScreen extends StatefulWidget {
  final Projet projet;

  const DetailsScreen({Key? key, required this.projet}) : super(key: key);

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  // Sous-dossiers à créer (relatifs au cheminDossier du projet)
  static const _structure = [
    'Autre',
    'Pdf',
    'Source',
    'Png',
    'Png/Plans',
    'Png/1080x1350_4-5_Portrait',
    'Png/1920x1080_16-9_Landscape',
  ];

  bool _structureExiste = false;
  bool _estimTypeExiste = false;

  late Projet _projet;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _projet = widget.projet;
    _verifierStructure();
  }

  void _verifierStructure() {
    final sep = Platform.pathSeparator;
    final base = _projet.cheminDossier;
    final existe = _structure.every((rel) =>
        Directory(base + sep + rel.replaceAll('/', sep)).existsSync());
    if (mounted) {
      setState(() => _structureExiste = existe);
      if (existe) _verifierEstimType();
    }
  }

  void _verifierEstimType() {
    final sep = Platform.pathSeparator;
    final chemin =
        '${_projet.cheminDossier}${sep}Autre${sep}EstimType.xlsx';
    if (mounted) setState(() => _estimTypeExiste = File(chemin).existsSync());
  }

  Future<void> _ouvrirDossier() async {
    final uri = Uri.file(_projet.cheminDossier);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _verifierOuCreerStructure() async {
    final sep = Platform.pathSeparator;
    final base = _projet.cheminDossier;

    // Vérifie si tous les dossiers existent déjà
    bool tousExistants = true;
    for (final rel in _structure) {
      final chemin = base + sep + rel.replaceAll('/', sep);
      if (!Directory(chemin).existsSync()) {
        tousExistants = false;
        break;
      }
    }

    if (tousExistants) {
      if (!mounted) return;
      _showResultat(
        message: 'Structure déjà existante',
        icon: Icons.folder_special_rounded,
        color: const Color(0xFFE67E22),
      );
      return;
    }

    // Crée les dossiers manquants
    for (final rel in _structure) {
      final chemin = base + sep + rel.replaceAll('/', sep);
      await Directory(chemin).create(recursive: true);
    }

    if (!mounted) return;
    setState(() => _structureExiste = true);
    _verifierEstimType();
    _showResultat(
      message: 'Structure créée avec succès',
      icon: Icons.check_circle_rounded,
      color: const Color(0xFF2E7D32),
    );
  }

  String get _cheminEstimType {
    final sep = Platform.pathSeparator;
    return '${_projet.cheminDossier}${sep}Autre${sep}EstimType.xlsx';
  }

  Future<void> _onEstimTypeTap() async {
    // Si le fichier existe déjà → ouvrir directement
    if (_estimTypeExiste) {
      final uri = Uri.file(_cheminEstimType);
      if (await canLaunchUrl(uri)) await launchUrl(uri);
      return;
    }

    // Sinon → copier depuis la racine Habitation
    final cataloguePath = StorageService().getCataloguePath();
    if (cataloguePath == null) return;

    final sep = Platform.pathSeparator;
    final source = '$cataloguePath${sep}EstimType.xlsx';

    if (!File(source).existsSync()) {
      _showResultat(
        message: 'EstimType.xlsx introuvable à la racine Habitation',
        icon: Icons.error_rounded,
        color: Colors.red,
      );
      return;
    }

    await File(source).copy(_cheminEstimType);
    if (!mounted) return;
    setState(() => _estimTypeExiste = true);
    _showResultat(
      message: 'EstimType.xlsx créé avec succès',
      icon: Icons.check_circle_rounded,
      color: const Color(0xFF2E7D32),
    );
  }

  Future<void> _copierCheminEstimType() async {
    await Clipboard.setData(ClipboardData(text: _cheminEstimType));
    if (!mounted) return;
    _showResultat(
      message: 'Chemin copié dans le presse-papiers',
      icon: Icons.check_rounded,
      color: const Color(0xFF3B8ED0),
    );
  }

  Future<void> _editerInfosJson() async {
    final sep = Platform.pathSeparator;
    final jsonFile = File('${_projet.cheminDossier}${sep}infos.json');
    if (!jsonFile.existsSync()) {
      _showResultat(
        message: 'Fichier infos.json introuvable',
        icon: Icons.error_rounded,
        color: Colors.red,
      );
      return;
    }

    String currentJson = '';
    try {
      currentJson = await jsonFile.readAsString();
      // On le reformate pour être propre
      final obj = jsonDecode(currentJson);
      currentJson = const JsonEncoder.withIndent('  ').convert(obj);
    } catch (e) {
      _showResultat(
        message: 'Erreur lecture infos.json: $e',
        icon: Icons.error_rounded,
        color: Colors.red,
      );
      return;
    }

    final jsonCtrl = TextEditingController(text: currentJson);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Modifier infos.json (Avancé)', style: TextStyle(color: Color(0xFF2C3E50), fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: jsonCtrl,
              maxLines: 25,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Éditez le JSON ici...',
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B8ED0), foregroundColor: Colors.white),
              child: const Text('Sauvegarder'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonCtrl.text);
        
        // Formatter avant de sauvegarder
        const encoder = JsonEncoder.withIndent('  ');
        final strToSave = encoder.convert(decoded);
        await jsonFile.writeAsString(strToSave);
        
        // Mettre à jour l'état local
        setState(() {
          _projet = Projet.fromJson(
            decoded,
            _projet.cheminDossier,
            _projet.categorie,
            _projet.images,
            archicadPath: _projet.archicadPath,
            twinmotionPath: _projet.twinmotionPath,
            estimTypePath: _projet.estimTypePath,
          );
        });

        _showResultat(message: 'Informations sauvegardées avec succès', icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32));
      } catch (e) {
        _showResultat(message: 'JSON Invalide, sauvegarde annulée. Erreur : $e', icon: Icons.error_rounded, color: Colors.red);
      }
    }
  }

  void _showResultat({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 340,
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B8ED0)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '← Retour à la galerie',
            style: TextStyle(
              color: Color(0xFF3B8ED0),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Modifier les infos',
            icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF3B8ED0)),
            onPressed: _editerInfosJson,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 1100;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: ImageCarousel(images: _projet.images),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.only(
                        top: 20, right: 20, bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildInfoContent(),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: ImageCarousel(images: _projet.images),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    padding: const EdgeInsets.all(25),
                    child: _buildInfoContent(),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildInfoContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTag(_projet.categorie),
            if (_projet.usage.isNotEmpty) _buildTag(_projet.usage),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          _projet.nomProjet,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 10),
        
        // --- Description rabattable ---
        if (_projet.descriptionMarketing.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedCrossFade(
                  firstChild: Text(
                    _projet.descriptionMarketing,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey[800]),
                  ),
                  secondChild: Text(
                    _projet.descriptionMarketing,
                    style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey[800]),
                  ),
                  crossFadeState: _descriptionExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
                if (_projet.descriptionMarketing.length > 150) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _descriptionExpanded ? 'Réduire' : 'Lire la suite',
                        style: const TextStyle(
                          color: Color(0xFF3B8ED0),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(height: 25),
        ],
        // --- Fin de la description ---

        const Text(
          'CARACTÉRISTIQUES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xFF3B8ED0),
          ),
        ),
        const Divider(height: 20),
        ..._buildRecursiveDetails(_projet.rawJson),
        const Divider(height: 30),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            const Text(
              'Coût estimé',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              _projet.budgetFormate,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),

        // Bouton ouvrir dossier
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _ouvrirDossier,
            icon: const Icon(Icons.folder_open),
            label: const Flexible(
              child: Text(
                'OUVRIR LE DOSSIER COMPLET',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B8ED0),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Bouton créer structure de dossiers
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _verifierOuCreerStructure,
            icon: Icon(
              _structureExiste
                  ? Icons.check_circle_rounded
                  : Icons.create_new_folder_rounded,
              size: 18,
              color: _structureExiste
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF5F6368),
            ),
            label: Flexible(
              child: Text(
                'CRÉER LA STRUCTURE DOSSIERS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _structureExiste
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF5F6368),
                ),
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _structureExiste
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF5F6368),
              side: BorderSide(
                color: _structureExiste
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFDDE1E7),
                width: 1.5,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Bouton EstimType + bouton copier chemin
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _structureExiste ? _onEstimTypeTap : null,
                  icon: Icon(
                    _estimTypeExiste
                        ? Icons.check_circle_rounded
                        : Icons.close_rounded,
                    size: 18,
                    color: !_structureExiste
                        ? Colors.grey[300]
                        : _estimTypeExiste
                            ? const Color(0xFF2E7D32)
                            : Colors.grey[500],
                  ),
                  label: Flexible(
                    child: Text(
                      'EstimType.xlsx',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: !_structureExiste
                            ? Colors.grey[300]
                            : _estimTypeExiste
                                ? const Color(0xFF2E7D32)
                                : Colors.grey[500],
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _estimTypeExiste
                        ? const Color(0xFF2E7D32)
                        : Colors.grey[500],
                    disabledForegroundColor: Colors.grey[300],
                    side: BorderSide(
                      color: !_structureExiste
                          ? Colors.grey.withValues(alpha: 0.15)
                          : _estimTypeExiste
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Bouton copier le chemin
            SizedBox(
              height: 46,
              width: 46,
              child: Tooltip(
                message: 'Copier le chemin',
                child: OutlinedButton(
                  onPressed:
                      _estimTypeExiste ? _copierCheminEstimType : null,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: const Color(0xFF3B8ED0),
                    disabledForegroundColor: Colors.grey[300],
                    side: BorderSide(
                      color: _estimTypeExiste
                          ? const Color(0xFF3B8ED0).withValues(alpha: 0.5)
                          : Colors.grey.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Icon(
                    Icons.file_copy_outlined,
                    size: 18,
                    color: _estimTypeExiste
                        ? const Color(0xFF3B8ED0)
                        : Colors.grey[300],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  // --- Construit dynamiquement les caractéristiques ---
  List<Widget> _buildRecursiveDetails(Map<String, dynamic> map, {int depth = 0}) {
    List<Widget> rows = [];
    
    // Ignorer certaines clés racine qu'on affiche déjà en gros (nom_projet, description_marketing, tags, financier)
    final ignoreKeys = (depth == 0) ? ['nom_projet', 'description_marketing', 'financier', 'tags'] : [];

    map.forEach((key, value) {
      if (ignoreKeys.contains(key) || value == null) return;

      // Nettoyer la clé (remplacer les underscores par des espaces)
      final cleanKey = key.replaceAll('_', ' ');
      final titleKey = cleanKey.substring(0, 1).toUpperCase() + cleanKey.substring(1);

      if (value is Map) {
        // En-tête pour les structures imbriquées
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4, left: depth * 15.0),
            child: Text(
              titleKey.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5F6368), fontSize: 11),
            ),
          ),
        );
        rows.addAll(_buildRecursiveDetails(Map<String, dynamic>.from(value), depth: depth + 1));
      } else if (value is List) {
        if (value.isNotEmpty) {
          rows.add(_buildDetailRow(titleKey, value.join(', '), depth: depth));
        }
      } else {
        // Si c'est un champ vide, on ne l'affiche pas
        if (value.toString().isNotEmpty) {
          rows.add(_buildDetailRow(titleKey, value.toString(), depth: depth));
        }
      }
    });

    return rows;
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD3E3FD),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF174EA6),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {int depth = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: 6, left: depth * 15.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF5F6368)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF202124),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
