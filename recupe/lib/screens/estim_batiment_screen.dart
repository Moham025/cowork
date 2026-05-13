// lib/screens/estim_batiment_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/estim_api_service.dart';

class ProjectCacheGroup {
  final String baseName;
  EstimCacheEntry? estim;
  EstimCacheEntry? detail;

  ProjectCacheGroup(this.baseName);

  DateTime get modified {
    if (estim != null && detail != null) {
      return estim!.modified.isAfter(detail!.modified) ? estim!.modified : detail!.modified;
    }
    return estim?.modified ?? detail!.modified;
  }

  int get size => (estim?.size ?? 0) + (detail?.size ?? 0);
}

class EstimBatimentScreen extends StatefulWidget {
  const EstimBatimentScreen({super.key});

  @override
  State<EstimBatimentScreen> createState() => _EstimBatimentScreenState();
}

class _EstimBatimentScreenState extends State<EstimBatimentScreen> {
  final _api = EstimApiService();

  // Serveur
  bool _serverOk = false;
  bool _serverStarting = false;

  // Fichier sélectionné
  String? _fichierPath;

  // Traitement
  bool _processing = false;
  String? _erreur;

  // Résultats courants
  List<EstimRow> _rows = [];
  String? _resultFilename;
  int _blocsCount = 0;
  Map<String, List<EstimRow>> _blockDetails = {}; // roman → lignes data

  // Détail matériaux
  List<DetailRow> _detailRows = [];
  String? _detailFilename;
  bool _detailProcessing = false;
  bool _showDetail = false;

  // Restart serveur
  bool _restarting = false;

  // Cache
  List<EstimCacheEntry> _cache = [];

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  // ─── Démarrage serveur ──────────────────────────────────────────────────────

  Future<void> _initServer() async {
    setState(() => _serverStarting = true);
    final ok = await _api.demarrerServeur();
    if (mounted) {
      setState(() {
        _serverOk = ok;
        _serverStarting = false;
      });
      if (ok) _chargerCache();
    }
  }

  // ─── Cache ──────────────────────────────────────────────────────────────────

  void _construireBlockDetails() {
    final map = <String, List<EstimRow>>{};
    String? bloc;
    for (final row in _rows) {
      if (row.type == 'block_hdr') {
        bloc = row.numero;
        map[bloc] = [];
      } else if (row.type == 'data' && bloc != null) {
        map[bloc]!.add(row);
      }
    }
    _blockDetails = map;
  }

  Future<void> _chargerCache() async {
    try {
      final entries = await _api.listerCache();
      if (mounted) setState(() => _cache = entries);
    } catch (_) {}
  }

  Future<void> _ouvrirDepuisCacheGroup(ProjectCacheGroup group) async {
    setState(() { _processing = true; _erreur = null; _rows = []; _detailRows = []; _resultFilename = null; _detailFilename = null; });
    try {
      if (group.estim != null) {
        final result = await _api.chargerDepuisCache(group.estim!.name);
        if (mounted) {
          setState(() {
            _rows = result.rows;
            _resultFilename = result.filename;
            _blocsCount = result.rows.where((r) => r.type == 'block_hdr').length;
          });
          _construireBlockDetails();
        }
      }
      if (group.detail != null) {
        final detail = await _api.chargerDetailDepuisCache(group.detail!.name);
        if (mounted) {
          setState(() {
            _detailRows = detail.rows;
            _detailFilename = detail.filename;
          });
        }
      }
      if (mounted) {
        setState(() { _processing = false; _showDetail = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = e.toString(); _processing = false; });
    }
  }

  Future<void> _supprimerCacheGroup(ProjectCacheGroup group) async {
    if (group.estim != null) await _api.supprimerCache(group.estim!.name);
    if (group.detail != null) await _api.supprimerCache(group.detail!.name);
    _chargerCache();
    if ((group.estim != null && _resultFilename == group.estim!.name) ||
        (group.detail != null && _detailFilename == group.detail!.name)) {
      if (mounted) {
        setState(() { _rows = []; _detailRows = []; _resultFilename = null; _detailFilename = null; _blocsCount = 0; });
      }
    }
  }

  Future<void> _viderCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vider le cache ?'),
        content: const Text('Tous les résultats sauvegardés seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vider', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _api.viderCache();
      if (mounted) setState(() { _cache = []; _rows = []; _resultFilename = null; });
    }
  }

  // ─── Traitement ─────────────────────────────────────────────────────────────

  Future<void> _selectionnerFichier() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      dialogTitle: 'Sélectionner EstimType.xlsx',
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _fichierPath = result.files.single.path);
    }
  }

  Future<void> _traiter() async {
    if (_fichierPath == null) return;
    setState(() { _processing = true; _erreur = null; _rows = []; _detailRows = []; _showDetail = false; });
    try {
      // 1) Calcul estimation
      final result = await _api.traiterFichier(_fichierPath!);
      if (mounted) {
        setState(() {
          _rows = result.rows;
          _resultFilename = result.filename;
          _blocsCount = result.blocsCount;
        });
        _construireBlockDetails();
      }

      // 2) Calcul détail matériaux (en parallèle après estimation)
      try {
        final detail = await _api.calculerDetail(_fichierPath!);
        if (mounted) {
          setState(() {
            _detailRows = detail.rows;
            _detailFilename = detail.filename;
          });
        }
      } catch (e) {
        debugPrint('[EstimBatiment] Détail échoué : $e');
      }

      if (mounted) {
        setState(() { _processing = false; });
        _chargerCache();
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = e.toString(); _processing = false; });
    }
  }

  // ─── Calcul Détail Matériaux ─────────────────────────────────────────────────

  Future<void> _calculerDetail() async {
    if (_fichierPath == null) return;
    setState(() { _detailProcessing = true; _erreur = null; });
    try {
      final result = await _api.calculerDetail(_fichierPath!);
      if (mounted) {
        setState(() {
          _detailRows = result.rows;
          _detailProcessing = false;
          _showDetail = true;
        });
        _chargerCache();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _detailProcessing = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur détail : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Restart Serveur ────────────────────────────────────────────────────────

  Future<void> _restartServer() async {
    setState(() { _restarting = true; _serverOk = false; });
    final ok = await _api.redemarrerServeur();
    if (mounted) {
      setState(() { _restarting = false; _serverOk = ok; });
      if (ok) {
        _chargerCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✔ Serveur redémarré avec succès'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✖ Échec du redémarrage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── Téléchargement ─────────────────────────────────────────────────────────

  /// Fichier à télécharger selon la vue active
  String? get _activeFilename => _showDetail ? _detailFilename : _resultFilename;

  Future<void> _telechargerXlsx() async {
    final fname = _activeFilename;
    if (fname == null) return;
    try {
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le résultat Excel',
        fileName: fname,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (savePath == null) return;
      if (!savePath.toLowerCase().endsWith('.xlsx')) savePath += '.xlsx';

      final bytes = await _api.telechargerFichier(fname);
      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistré : $savePath'), backgroundColor: const Color(0xFF2E7D32)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exporterJson() async {
    final fname = _activeFilename;
    final defaultName = fname != null ? fname.replaceAll('.xlsx', '.json') : (_showDetail ? 'Detail_Materiaux.json' : 'Estimation.json');
    try {
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter en JSON',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (savePath == null) return;
      if (!savePath.toLowerCase().endsWith('.json')) savePath += '.json';

      Map<String, dynamic> export;
      if (_showDetail) {
        // Détail : exporter uniquement le récapitulatif
        final resumeItems = _detailRows
            .where((r) => r.type == 'resume_item')
            .map((r) => {
                  'materiau': r.description,
                  'total': r.totalDisplay ?? '',
                  'commande': r.resultDisplay ?? '',
                })
            .toList();
        export = {
          'fichier_source': _detailFilename ?? '',
          'resume_approvisionnement': resumeItems,
        };
      } else {
        // Estimation : exporter toutes les lignes
        final lignes = _rows.map((r) => {
              'numero': r.numero,
              'description': r.description,
              'unite': r.unite ?? '',
              'quantite': r.quantite,
              'prix_unitaire': r.pu,
              'montant': r.montant,
              'type': r.type,
            }).toList();
        export = {
          'fichier_source': _resultFilename ?? '',
          'lignes': lignes,
        };
      }

      final jsonStr = const JsonEncoder.withIndent('  ').convert(export);
      await File(savePath).writeAsString(jsonStr, encoding: utf8);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON exporté : $savePath'), backgroundColor: const Color(0xFF2E7D32)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur JSON : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exporterPdf() async {
    final fname = _activeFilename;
    if (fname == null) return;
    final defaultName = fname.replaceAll('.xlsx', '.pdf');
    try {
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter en PDF',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savePath == null) return;
      if (!savePath.toLowerCase().endsWith('.pdf')) savePath += '.pdf';
      final bytes = await _api.exporterPdf(fname);
      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF exporté : $savePath'), backgroundColor: const Color(0xFF2E7D32)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur PDF : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _serverStarting
                ? _buildServeurDemarrage()
                : !_serverOk
                    ? _buildServeurErreur()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPanneauGauche(),
                          Expanded(child: _buildPanneauDroit()),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        boxShadow: [BoxShadow(color: Color(0x30000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Tableau de bord',
          ),
          const SizedBox(width: 8),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.calculate_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('EstimBatiment',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Calcul automatique de devis',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
            ],
          ),
          const Spacer(),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_blocsCount bloc${_blocsCount > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          // Bouton Restart Serveur
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Redémarrer le serveur Python (port 8765)',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: (_restarting || _serverStarting) ? null : _restartServer,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _restarting
                          ? Colors.orange.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _restarting
                            ? Colors.orange.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: _restarting
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orange),
                          )
                        : const Icon(Icons.refresh_rounded,
                            color: Colors.white70, size: 18),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── États serveur ───────────────────────────────────────────────────────────

  Widget _buildServeurDemarrage() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF0D47A1)),
          SizedBox(height: 24),
          Text('Démarrage du moteur de calcul…',
              style: TextStyle(fontSize: 15, color: Color(0xFF6B7280))),
          SizedBox(height: 8),
          Text('Cela peut prendre quelques secondes',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _buildServeurErreur() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 56, color: Colors.red[300]),
          const SizedBox(height: 20),
          const Text('Impossible de démarrer le moteur de calcul',
              style: TextStyle(fontSize: 15, color: Color(0xFF374151), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Vérifiez que Python est installé et que les dépendances sont présentes',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text('pip install -r EstimBatiment/requirements.txt',
              style: TextStyle(fontSize: 11, color: Colors.grey[400], fontFamily: 'monospace')),
          if (_api.dernierErreur?.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFB74D)),
              ),
              child: SelectableText(
                _api.dernierErreur!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF5D4037), fontFamily: 'monospace'),
              ),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _initServer,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // Define how we get groups right above _buildPanneauGauche:
  List<ProjectCacheGroup> _getGroupedCache() {
    final map = <String, ProjectCacheGroup>{};
    final reg = RegExp(r'_?(\d{8}_\d{6})');

    for (var c in _cache) {
      String baseName = c.name.replaceAll('.xlsx', '');
      
      final match = reg.firstMatch(baseName);
      String groupId = baseName;
      if (match != null) {
        groupId = match.group(1)!; // The common timestamp (e.g. 20260402_222628)
      } else {
        if (baseName.startsWith('EstimType_')) {
          groupId = baseName.substring(10);
        } else if (baseName.startsWith('Detail_Materiaux_')) {
          groupId = baseName.substring(17);
        }
      }

      map.putIfAbsent(groupId, () => ProjectCacheGroup(groupId));
      
      // Determine if it's the estimation file
      if (c.name.startsWith('Estimation_Resultat_') || c.name.startsWith('EstimType_')) {
        map[groupId]!.estim = c;
      } else {
        map[groupId]!.detail = c;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => b.modified.compareTo(a.modified));
    return list;
  }

  // ─── Panneau gauche ──────────────────────────────────────────────────────────

  Widget _buildPanneauGauche() {
    final nomFichier = _fichierPath != null
        ? _fichierPath!.split(Platform.pathSeparator).last
        : null;
    
    final groupedCache = _getGroupedCache();

    return Container(
      width: 300,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section fichier
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('FICHIER SOURCE'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _selectionnerFichier,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: nomFichier != null
                            ? const Color(0xFF0D47A1).withValues(alpha: 0.35)
                            : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.table_chart_rounded,
                          size: 20,
                          color: nomFichier != null
                              ? const Color(0xFF2E7D32)
                              : Colors.grey[400],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nomFichier ?? 'Aucun fichier sélectionné',
                            style: TextStyle(
                              fontSize: 12,
                              color: nomFichier != null
                                  ? const Color(0xFF1C2B3A)
                                  : Colors.grey[400],
                              fontWeight: nomFichier != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectionnerFichier,
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: const Text('Parcourir'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0D47A1),
                          side: const BorderSide(color: Color(0xFF0D47A1)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_fichierPath != null && !_processing)
                            ? _traiter
                            : null,
                        icon: _processing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(_processing ? 'Calcul…' : 'Calculer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                // Erreur
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _erreur!,
                      style: const TextStyle(fontSize: 11, color: Color(0xFFC62828)),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFF0F4F8)),
          const SizedBox(height: 16),

          // Section cache
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('RÉSULTATS RÉCENTS'),
                if (_cache.isNotEmpty)
                  GestureDetector(
                    onTap: _viderCache,
                    child: Text(
                      'Vider',
                      style: TextStyle(fontSize: 11, color: Colors.red[400]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: groupedCache.isEmpty
                ? Center(
                    child: Text(
                      'Aucun résultat sauvegardé',
                      style: TextStyle(fontSize: 12, color: Colors.grey[350]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: groupedCache.length,
                    itemBuilder: (_, i) => _buildCacheItemGroup(groupedCache[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheItemGroup(ProjectCacheGroup group) {
    final isActive = (group.estim != null && group.estim!.name == _resultFilename) || 
                     (group.detail != null && group.detail!.name == _detailFilename);
                     
    final date = '${group.modified.day.toString().padLeft(2, '0')}/'
        '${group.modified.month.toString().padLeft(2, '0')} '
        '${group.modified.hour.toString().padLeft(2, '0')}:'
        '${group.modified.minute.toString().padLeft(2, '0')}';
    final sizeKb = (group.size / 1024).toStringAsFixed(0);

    return GestureDetector(
      onTap: () => _ouvrirDepuisCacheGroup(group),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF0D47A1).withValues(alpha: 0.07)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0D47A1).withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_copy_rounded,
                size: 16,
                color: isActive ? const Color(0xFF0D47A1) : Colors.grey[400]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.baseName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF0D47A1)
                          : const Color(0xFF374151),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(date,
                          style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      const SizedBox(width: 6),
                      Text('•', style: TextStyle(fontSize: 10, color: Colors.grey[300])),
                      const SizedBox(width: 6),
                      Text('$sizeKb ko',
                          style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _supprimerCacheGroup(group),
              child: Icon(Icons.close_rounded, size: 14, color: Colors.grey[350]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Panneau droit ───────────────────────────────────────────────────────────

  Widget _buildPanneauDroit() {
    if (_processing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF0D47A1)),
            SizedBox(height: 20),
            Text('Calcul en cours…',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_rows_rounded, size: 56, color: Colors.grey[200]),
            const SizedBox(height: 16),
            Text(
              'Sélectionnez un fichier EstimType.xlsx\npuis cliquez sur Calculer',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Barre d'action
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 16, color: Colors.green[600]),
              const SizedBox(width: 8),
              Text(
                '$_blocsCount bloc${_blocsCount > 1 ? 's' : ''} traité${_blocsCount > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151)),
              ),
              const Spacer(),
              // Toggle Estimation / Détail
              if (_detailRows.isNotEmpty) ...[
                _buildViewToggle(),
                const SizedBox(width: 8),
              ],
              // Boutons export
              _exportBtn('XLSX', Icons.table_chart_rounded, const Color(0xFF2E7D32), _telechargerXlsx),
              const SizedBox(width: 6),
              _exportBtn('JSON', Icons.data_object_rounded, const Color(0xFFE65100), _exporterJson),
              const SizedBox(width: 6),
              _exportBtn('PDF', Icons.picture_as_pdf_rounded, const Color(0xFFB71C1C), _exporterPdf),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),

        // Tableau résultats ou détail
        Expanded(
          child: _showDetail && _detailRows.isNotEmpty
              ? _buildDetailView()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) => _buildResultRow(_rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _exportBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        minimumSize: const Size(0, 34),
      ),
    );
  }

  /// Toggle entre la vue Estimation et Détail
  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('Estimation', !_showDetail, () => setState(() => _showDetail = false)),
          _toggleChip('Détail', _showDetail, () => setState(() => _showDetail = true)),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0D47A1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : const Color(0xFF6B7280),
            )),
      ),
    );
  }

  /// Vue détail matériaux
  Widget _buildDetailView() {
    return Column(
      children: [
        // Entête colonnes détail
        Container(
          color: const Color(0xFF0D47A1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: const [
              SizedBox(width: 50, child: Text('N°', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white))),
              Expanded(flex: 4, child: Text('Description',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 36, child: Text('Unité', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 50, child: Text('Qté', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 52, child: Text('Ciment', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 48, child: Text('Brique', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 48, child: Text('Hourdi', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 50, child: Text('Sable', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 50, child: Text('Granite', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 50, child: Text('Planche', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 50, child: Text('Terre', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 44, child: Text('Ha6', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 44, child: Text('Ha8', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 44, child: Text('Ha10', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 44, child: Text('Ha12', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
              SizedBox(width: 44, child: Text('Ha14', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 0),
            itemCount: _detailRows.length,
            itemBuilder: (_, i) => _buildDetailRowWidget(_detailRows[i], i),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRowWidget(DetailRow row, int index) {
    if (row.type == 'section') {
      return Container(
        color: const Color(0xFF1565C0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('${row.numero}  —  ${row.description}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }
    if (row.type == 'total_general') {
      return Container(
        color: const Color(0xFF263238),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          const SizedBox(width: 50),
          const Expanded(flex: 4, child: Text('TOTAL GÉNÉRAL',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
          const SizedBox(width: 36),
          const SizedBox(width: 50),
          ..._matValues(row, bold: true, color: Colors.white),
        ]),
      );
    }
    if (row.type == 'resume_hdr') {
      return Container(
        color: const Color(0xFF2E7D32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(row.description,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }
    if (row.type == 'resume_item') {
      final bg = index % 2 == 0 ? const Color(0xFFE8F5E9) : Colors.white;
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(flex: 3, child: Text(row.description,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 140, child: Text(row.totalDisplay ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 16),
          SizedBox(width: 140, child: Text(row.resultDisplay ?? '',
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20)))),
        ]),
      );
    }
    // data row
    final bg = index % 2 == 0 ? const Color(0xFFFAFAFA) : Colors.white;
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(children: [
        SizedBox(width: 50, child: Text(row.numero, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)))),
        Expanded(flex: 4, child: Text(row.description,
            style: const TextStyle(fontSize: 10, color: Color(0xFF1F2937)))),
        SizedBox(width: 36, child: Text(row.unite ?? '', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)))),
        SizedBox(width: 50, child: Text(_fmtD(row.quantite), textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 9))),
        ..._matValues(row),
      ]),
    );
  }

  List<Widget> _matValues(DetailRow row, {bool bold = false, Color color = const Color(0xFF374151)}) {
    final style = TextStyle(fontSize: 9, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color);
    double? v(double? d) => (d != null && d != 0) ? d : null;
    return [
      SizedBox(width: 52, child: Text(_fmtD(v(row.ciment)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 48, child: Text(_fmtD(v(row.brique)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 48, child: Text(_fmtD(v(row.hourdi)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 50, child: Text(_fmtD(v(row.sable)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 50, child: Text(_fmtD(v(row.granite)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 50, child: Text(_fmtD(v(row.planche)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 50, child: Text(_fmtD(v(row.terre)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 44, child: Text(_fmtD(v(row.ha6)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 44, child: Text(_fmtD(v(row.ha8)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 44, child: Text(_fmtD(v(row.ha10)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 44, child: Text(_fmtD(v(row.ha12)), textAlign: TextAlign.right, style: style)),
      SizedBox(width: 44, child: Text(_fmtD(v(row.ha14)), textAlign: TextAlign.right, style: style)),
    ];
  }

  String _fmtD(double? val) {
    if (val == null) return '';
    if (val == val.roundToDouble()) return val.round().toString();
    return val.toStringAsFixed(2);
  }

  Widget _buildResultRow(EstimRow row) {
    switch (row.type) {
      case 'block_hdr':
        return _RowBlockHeader(row: row);
      case 'total':
        return _RowTotal(row: row);
      case 'recap_hdr':
        return _RowRecapHeader(row: row);
      case 'grand_total':
        return _RowGrandTotal(row: row);
      case 'recap_item':
        return _RowRecapItem(
          row: row,
          detailRows: _blockDetails[row.numero] ?? [],
        );
      case 'note':
        return _RowNote(row: row);
      default:
        return _RowData(row: row);
    }
  }

  // ─── Helper ─────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}

// ─── Widgets de ligne ─────────────────────────────────────────────────────────

String _fmt(double? val) {
  if (val == null) return '-';
  final n = val.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u202F');
    buf.write(s[i]);
  }
  return n < 0 ? '-${buf.toString()}' : buf.toString();
}

class _RowBlockHeader extends StatelessWidget {
  final EstimRow row;
  const _RowBlockHeader({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1, top: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(6), topRight: Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(row.numero,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                row.description,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowData extends StatelessWidget {
  final EstimRow row;
  const _RowData({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: const BoxDecoration(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(row.numero,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ),
            Expanded(
              flex: 5,
              child: Text(row.description,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937))),
            ),
            SizedBox(
              width: 44,
              child: Text(row.unite ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ),
            SizedBox(
              width: 72,
              child: Text(_fmt(row.quantite),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
            ),
            SizedBox(
              width: 80,
              child: Text(_fmt(row.pu),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
            ),
            SizedBox(
              width: 96,
              child: Text(_fmt(row.montant),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C2B3A))),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTotal extends StatelessWidget {
  final EstimRow row;
  const _RowTotal({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFBBDEFB),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(row.numero,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D47A1))),
            ),
            Text(_fmt(row.montant),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1))),
          ],
        ),
      ),
    );
  }
}

class _RowRecapHeader extends StatelessWidget {
  final EstimRow row;
  const _RowRecapHeader({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 1),
      decoration: const BoxDecoration(
        color: Color(0xFF263238),
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(6), topRight: Radius.circular(6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(row.description,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5)),
    );
  }
}

class _RowRecapItem extends StatefulWidget {
  final EstimRow row;
  final List<EstimRow> detailRows;
  const _RowRecapItem({required this.row, required this.detailRows});

  @override
  State<_RowRecapItem> createState() => _RowRecapItemState();
}

class _RowRecapItemState extends State<_RowRecapItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasDetail = widget.detailRows.isNotEmpty;
    return Column(
      children: [
        // ── Ligne récapitulatif ──────────────────────────────────────────
        GestureDetector(
          onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 1),
            color: _expanded ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(widget.row.numero,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D47A1))),
                  ),
                  Expanded(
                    child: Text(widget.row.description,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937))),
                  ),
                  Text(_fmt(widget.row.montant),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0D47A1))),
                  if (hasDetail) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more_rounded,
                          size: 18, color: Color(0xFF6B7280)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ── Détail expandable ────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _expanded
              ? Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    border: Border(
                      left: BorderSide(
                          color: const Color(0xFF0D47A1).withValues(alpha: 0.35),
                          width: 3),
                    ),
                  ),
                  child: Column(
                    children: [
                      // En-tête colonnes détail
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                        child: Row(
                          children: const [
                            SizedBox(width: 52,
                                child: Text('N°',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)))),
                            Expanded(flex: 5,
                                child: Text('Description',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)))),
                            SizedBox(width: 44,
                                child: Text('Unité', textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 9, color: Color(0xFF6B7280)))),
                            SizedBox(width: 72,
                                child: Text('Qté', textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 9, color: Color(0xFF6B7280)))),
                            SizedBox(width: 80,
                                child: Text('P.U.', textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 9, color: Color(0xFF6B7280)))),
                            SizedBox(width: 96,
                                child: Text('Montant', textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 9, color: Color(0xFF6B7280)))),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFDDE8F0)),
                      ...widget.detailRows.map((r) => _RowData(row: r)),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _RowNote extends StatelessWidget {
  final EstimRow row;
  const _RowNote({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFEE58).withValues(alpha: 0.6)),
      ),
      child: Text(
        row.description,
        style: const TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Color(0xFF5D4037),
        ),
      ),
    );
  }
}

class _RowGrandTotal extends StatelessWidget {
  final EstimRow row;
  const _RowGrandTotal({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.summarize_rounded, size: 16, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(row.description,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            Text(_fmt(row.montant),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
