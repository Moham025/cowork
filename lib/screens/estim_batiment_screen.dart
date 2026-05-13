// lib/screens/estim_batiment_screen.dart

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/estim_api_service.dart';

class EstimBatimentScreen extends StatefulWidget {
  /// Si fourni, ce fichier est pré-sélectionné au lancement
  final String? fichierInitial;
  const EstimBatimentScreen({super.key, this.fichierInitial});

  @override
  State<EstimBatimentScreen> createState() => _EstimBatimentScreenState();
}

class _EstimBatimentScreenState extends State<EstimBatimentScreen>
    with SingleTickerProviderStateMixin {
  final _api = EstimApiService();

  // Serveur
  bool _serverOk = false;
  bool _serverStarting = false;

  // Fichier sélectionné
  String? _fichierPath;

  // Traitement
  bool _processing = false;
  String? _erreur;

  // Résultats
  List<EstimOutput> _outputs = [];
  String? _timestamp;

  // Cache
  List<EstimCacheEntry> _cache = [];

  // Onglets
  late TabController _tabController;

  static const _tabIds = [
    'estimation',
    'detail_materiaux',
    'main_oeuvre',
    'gros_oeuvre',
    'finition',
  ];
  static const _tabLabels = [
    'Estimation',
    'Matériaux',
    "Main d'Œuvre",
    'Gros Œuvre',
    'Finition',
  ];
  static const _tabIcons = [
    Icons.receipt_long_rounded,
    Icons.inventory_2_rounded,
    Icons.engineering_rounded,
    Icons.foundation_rounded,
    Icons.format_paint_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabIds.length, vsync: this);
    if (widget.fichierInitial != null) {
      _fichierPath = widget.fichierInitial;
    }
    _initServer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Serveur ─────────────────────────────────────────────────────────────

  Future<void> _initServer() async {
    setState(() => _serverStarting = true);
    final ok = await _api.demarrerServeur();
    if (mounted) {
      setState(() { _serverOk = ok; _serverStarting = false; });
      if (ok) _chargerCache();
    }
  }

  Future<void> _redemarrerServeur() async {
    setState(() { _serverOk = false; _serverStarting = true; });
    final ok = await _api.demarrerServeur();
    if (mounted) {
      setState(() { _serverOk = ok; _serverStarting = false; });
      if (ok) _chargerCache();
    }
  }

  // ─── Cache ───────────────────────────────────────────────────────────────

  Future<void> _chargerCache() async {
    try {
      final entries = await _api.listerCache();
      if (mounted) setState(() => _cache = entries);
    } catch (_) {}
  }

  Future<void> _ouvrirDepuisCache(EstimCacheEntry entry) async {
    setState(() { _processing = true; _erreur = null; });
    try {
      final result = await _api.chargerDepuisCache(entry.timestamp);
      if (mounted) {
        setState(() {
          _outputs = result.outputs;
          _timestamp = result.timestamp;
          _processing = false;
        });
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = e.toString(); _processing = false; });
    }
  }

  Future<void> _supprimerCache(EstimCacheEntry entry) async {
    await _api.supprimerCache(entry.timestamp);
    _chargerCache();
    if (_timestamp == entry.timestamp && mounted) {
      setState(() { _outputs = []; _timestamp = null; });
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
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Vider', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok ?? false) {
      await _api.viderCache();
      if (mounted) setState(() { _cache = []; _outputs = []; _timestamp = null; });
    }
  }

  // ─── Export ──────────────────────────────────────────────────────────────

  bool _exporting = false;

  Future<void> _exporter(String fmt) async {
    if (_outputs.isEmpty || _timestamp == null || _exporting) return;
    final idx    = _tabController.index;
    final id     = _tabIds[idx];
    final label  = _tabLabels[idx];
    final output = _outputs.firstWhere(
      (o) => o.id == id,
      orElse: () => EstimOutput(id: id, label: label, rows: []),
    );

    setState(() => _exporting = true);
    try {
      if (fmt == 'json') {
        final jsonStr = const JsonEncoder.withIndent('  ').convert(output.toJson());
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Exporter $label en JSON',
          fileName: '${label}_$_timestamp.json',
          allowedExtensions: ['json'],
          type: FileType.custom,
        );
        if (path != null) {
          await File(path).writeAsString(jsonStr, encoding: utf8);
          if (mounted) _showSnack('Exporté → $path');
        }
      } else {
        // XLSX via serveur
        final bytes = await _api.exporterXlsx(_timestamp!, id);
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Exporter $label en Excel',
          fileName: '${label}_$_timestamp.xlsx',
          allowedExtensions: ['xlsx'],
          type: FileType.custom,
        );
        if (path != null) {
          await File(path).writeAsBytes(bytes);
          if (mounted) _showSnack('Exporté → $path');
        }
      }
    } catch (e) {
      if (mounted) _showSnack('Erreur export : $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // Noms de fichiers pour chaque onglet (sans espaces ni apostrophes)
  static const _tabFileNames = [
    'Estimation',
    'Materiaux',
    'Main_d_oeuvre',
    'Gros_oeuvre',
    'Finition',
  ];

  Future<void> _exporterToutJson() async {
    if (_outputs.isEmpty || _timestamp == null || _exporting) return;

    // Dossier cible = même dossier que le fichier xlsx sélectionné
    final dossier = _fichierPath != null
        ? File(_fichierPath!).parent.path
        : null;

    if (dossier == null) {
      _showSnack('Sélectionnez d\'abord un fichier EstimType.xlsx', error: true);
      return;
    }

    setState(() => _exporting = true);
    try {
      final sep = Platform.pathSeparator;
      int count = 0;
      for (final output in _outputs) {
        // Trouver le nom de fichier correspondant à l'id
        final idx = _tabIds.indexOf(output.id);
        final fileName = idx >= 0 ? _tabFileNames[idx] : output.id;
        final payload = {
          'timestamp': _timestamp,
          'fichier_source': _fichierPath?.split(sep).last,
          ...output.toJson(),
        };
        final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
        final path = '$dossier$sep${fileName}_$_timestamp.json';
        await File(path).writeAsString(jsonStr, encoding: utf8);
        count++;
      }
      if (mounted) _showSnack('$count fichiers exportés dans $dossier');
    } catch (e) {
      if (mounted) _showSnack('Erreur export : $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 12)),
      backgroundColor: error ? Colors.red[700] : const Color(0xFF1B5E20),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ─── Traitement ──────────────────────────────────────────────────────────

  Future<void> _selectionnerFichier() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      dialogTitle: 'Sélectionner EstimType.xlsx',
    );
    if (result?.files.single.path != null) {
      setState(() => _fichierPath = result!.files.single.path);
    }
  }

  Future<void> _traiter() async {
    if (_fichierPath == null) return;
    setState(() { _processing = true; _erreur = null; _outputs = []; });
    try {
      final result = await _api.traiterFichier(_fichierPath!);
      if (mounted) {
        setState(() {
          _outputs = result.outputs;
          _timestamp = result.timestamp;
          _processing = false;
        });
        _chargerCache();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = e.toString(); _processing = false; });
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

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

  // ─── Header ──────────────────────────────────────────────────────────────

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
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EstimBatiment',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Calcul automatique de devis',
                  style: TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ),
          const Spacer(),
          // Bouton redémarrer serveur
          if (_serverOk)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Redémarrer le serveur Python',
                child: InkWell(
                  onTap: _serverStarting ? null : _redemarrerServeur,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    child: Row(
                      children: [
                        _serverStarting
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white70))
                            : const Icon(Icons.restart_alt_rounded,
                                size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        const Text('Redémarrer',
                            style: TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
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

  // ─── États serveur ────────────────────────────────────────────────────────

  Widget _buildServeurDemarrage() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: Color(0xFF0D47A1)),
        SizedBox(height: 24),
        Text('Démarrage du moteur de calcul…',
            style: TextStyle(fontSize: 15, color: Color(0xFF6B7280))),
        SizedBox(height: 8),
        Text('Cela peut prendre quelques secondes',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ]),
    );
  }

  Widget _buildServeurErreur() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
            child: SelectableText(_api.dernierErreur!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF5D4037), fontFamily: 'monospace')),
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
      ]),
    );
  }

  // ─── Panneau gauche ───────────────────────────────────────────────────────

  Widget _buildPanneauGauche() {
    final nomFichier = _fichierPath?.split(Platform.pathSeparator).last;

    return Container(
      width: 300,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        Icon(Icons.table_chart_rounded, size: 20,
                            color: nomFichier != null ? const Color(0xFF2E7D32) : Colors.grey[400]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nomFichier ?? 'Aucun fichier sélectionné',
                            style: TextStyle(
                              fontSize: 12,
                              color: nomFichier != null ? const Color(0xFF1C2B3A) : Colors.grey[400],
                              fontWeight: nomFichier != null ? FontWeight.w600 : FontWeight.normal,
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_fichierPath != null && !_processing) ? _traiter : null,
                        icon: _processing
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(_processing ? 'Calcul…' : 'Calculer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(_erreur!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFC62828))),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFF0F4F8)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('RÉSULTATS RÉCENTS'),
                if (_cache.isNotEmpty)
                  GestureDetector(
                    onTap: _viderCache,
                    child: Text('Vider', style: TextStyle(fontSize: 11, color: Colors.red[400])),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cache.isEmpty
                ? Center(child: Text('Aucun résultat sauvegardé',
                    style: TextStyle(fontSize: 12, color: Colors.grey[350])))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _cache.length,
                    itemBuilder: (_, i) => _buildCacheItem(_cache[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheItem(EstimCacheEntry entry) {
    final isActive = entry.timestamp == _timestamp;
    final dt = entry.modified;
    final date =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final sizeKb = (entry.size / 1024).toStringAsFixed(0);

    return GestureDetector(
      onTap: () => _ouvrirDepuisCache(entry),
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
            Icon(Icons.description_rounded, size: 16,
                color: isActive ? const Color(0xFF0D47A1) : Colors.grey[400]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive ? const Color(0xFF0D47A1) : const Color(0xFF374151))),
                  Text('$sizeKb ko',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _supprimerCache(entry),
              child: Icon(Icons.close_rounded, size: 14, color: Colors.grey[350]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Panneau droit : 5 onglets ────────────────────────────────────────────

  Widget _buildPanneauDroit() {
    if (_processing) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Color(0xFF0D47A1)),
          SizedBox(height: 20),
          Text('Calcul en cours…', style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
        ]),
      );
    }

    if (_outputs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.table_rows_rounded, size: 56, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            'Sélectionnez un fichier EstimType.xlsx\npuis cliquez sur Calculer',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[400], fontWeight: FontWeight.w500),
          ),
        ]),
      );
    }

    return Column(
      children: [
        // TabBar + boutons export
        Container(
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF0D47A1),
                  unselectedLabelColor: Colors.grey[500],
                  indicatorColor: const Color(0xFF0D47A1),
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: List.generate(_tabIds.length, (i) => Tab(
                    height: 46,
                    child: Row(children: [
                      Icon(_tabIcons[i], size: 16),
                      const SizedBox(width: 6),
                      Text(_tabLabels[i]),
                    ]),
                  )),
                ),
              ),
              // Boutons export
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _exportBtn(
                      icon: Icons.table_chart_outlined,
                      label: 'XLSX',
                      color: const Color(0xFF1B5E20),
                      onTap: _exporting ? null : () => _exporter('xlsx'),
                    ),
                    const SizedBox(width: 6),
                    _exportBtn(
                      icon: Icons.data_object_rounded,
                      label: 'JSON',
                      color: const Color(0xFF0D47A1),
                      onTap: _exporting ? null : () => _exporter('json'),
                    ),
                    const SizedBox(width: 6),
                    _exportBtn(
                      icon: Icons.add_chart_rounded,
                      label: 'JSON+',
                      color: const Color(0xFF6A1B9A),
                      tooltip: 'Exporter tous les onglets en un seul JSON\n(sauvegardé dans le même dossier que EstimType.xlsx)',
                      onTap: _exporting ? null : _exporterToutJson,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),

        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: List.generate(_tabIds.length, (i) {
              final id = _tabIds[i];
              final output = _outputs.firstWhere(
                (o) => o.id == id,
                orElse: () => EstimOutput(id: id, label: _tabLabels[i], rows: []),
              );
              return id == 'detail_materiaux'
                  ? _MateriauTab(output: output)
                  : _StandardTab(output: output);
            }),
          ),
        ),
      ],
    );
  }

  Widget _exportBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    String? tooltip,
  }) =>
      Tooltip(
        message: tooltip ?? 'Exporter l\'onglet actif en $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: onTap == null ? Colors.grey[100] : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: onTap == null ? Colors.grey[300]! : color.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _exporting
                    ? SizedBox(
                        width: 13, height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(icon, size: 14, color: onTap == null ? Colors.grey : color),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: onTap == null ? Colors.grey : color,
                    )),
              ],
            ),
          ),
        ),
      );

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Color(0xFF9CA3AF)));
}

// ─── Onglet standard (Estimation / Main d'œuvre / Gros Œuvre / Finition) ─────

class _StandardTab extends StatelessWidget {
  final EstimOutput output;
  const _StandardTab({required this.output});

  @override
  Widget build(BuildContext context) {
    if (output.rows.isEmpty) {
      return Center(
        child: Text('Aucune donnée', style: TextStyle(color: Colors.grey[400])),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: output.rows.length,
      itemBuilder: (_, i) => _buildRow(output.rows[i]),
    );
  }

  Widget _buildRow(EstimRow row) {
    switch (row.type) {
      case 'section_hdr':
        return _SectionHeader(row: row);
      case 'section_total':
        return _SectionTotal(row: row);
      case 'grand_total':
        return _GrandTotal(row: row);
      default:
        return _ItemRow(row: row);
    }
  }
}

// ─── Onglet Détail Matériaux (tableau horizontal) ─────────────────────────────

class _MateriauTab extends StatelessWidget {
  final EstimOutput output;
  const _MateriauTab({required this.output});

  @override
  Widget build(BuildContext context) {
    if (output.rows.isEmpty) {
      return Center(child: Text('Aucune donnée', style: TextStyle(color: Colors.grey[400])));
    }

    // Récupérer les headers depuis la première ligne mat_header
    final hdrRow = output.rows.firstWhere(
      (r) => r.type == 'mat_header',
      orElse: () => const EstimRow(type: 'mat_header', numero: '', description: ''),
    );
    final headers = hdrRow.matHeaders ?? [];

    // Séparer tableau matériaux et résumé d'approvisionnement
    final tableRows  = output.rows.where((r) =>
        r.type == 'mat_item' || r.type == 'mat_total').toList();
    final resumeRows = output.rows.where((r) =>
        r.type == 'mat_resume').toList();

    const double colW = 90;
    const double descW = 220;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tableau des quantités (défilement horizontal) ────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête colonnes
                Container(
                  color: const Color(0xFF0D47A1),
                  child: Row(children: [
                    _matCell('Élément', descW, isHeader: true),
                    ...headers.map((h) => _matCell(h, colW, isHeader: true)),
                  ]),
                ),
                // Lignes items
                ...tableRows.asMap().entries.map((e) {
                  final idx = e.key;
                  final r   = e.value;

                  if (r.type == 'mat_total') {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B5E20),
                        border: Border(top: BorderSide(color: Color(0xFF2E7D32), width: 2)),
                      ),
                      child: Row(children: [
                        _matCell(r.description, descW, isTotal: true),
                        ...(r.matValues ?? List.filled(headers.length, 0.0))
                            .map((v) => _matCell(v == 0 ? '-' : _fmtMat(v), colW, isTotal: true)),
                      ]),
                    );
                  }

                  final odd = idx.isEven;
                  return Container(
                    color: odd ? const Color(0xFFF8FAFC) : Colors.white,
                    child: Row(children: [
                      _matCell(r.description, descW),
                      ...(r.matValues ?? List.filled(headers.length, 0.0))
                          .map((v) => _matCell(v == 0 ? '-' : _fmtMat(v), colW)),
                    ]),
                  );
                }),
              ],
            ),
          ),

          // ── Résumé d'approvisionnement ────────────────────────────────────
          if (resumeRows.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'RÉSUMÉ D\'APPROVISIONNEMENT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(height: 4),
            ...resumeRows.asMap().entries.map((e) {
              final idx = e.key;
              final r   = e.value;
              return Container(
                color: idx.isEven ? const Color(0xFFF8FAFC) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(children: [
                  Expanded(
                    flex: 5,
                    child: Text(r.numero,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1C2B3A))),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(r.description,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: Color(0xFF1C2B3A))),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: Text(r.unite ?? '',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _matCell(String text, double width,
      {bool isHeader = false, bool isTotal = false, bool isSubtotal = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: (isHeader || isTotal || isSubtotal) ? Colors.white : const Color(0xFF1F2937),
          fontWeight: (isHeader || isTotal || isSubtotal) ? FontWeight.w700 : FontWeight.normal,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _fmtMat(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }
}

// ─── Widgets de lignes standard ───────────────────────────────────────────────

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

class _SectionHeader extends StatelessWidget {
  final EstimRow row;
  const _SectionHeader({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 1),
      decoration: const BoxDecoration(
        color: Color(0xFF0D47A1),
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(6), topRight: Radius.circular(6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        if (row.numero.isNotEmpty) ...[
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(row.numero,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(row.description,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final EstimRow row;
  const _ItemRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          SizedBox(width: 42,
              child: Text(row.numero,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))),
          Expanded(flex: 5,
              child: Text(row.description,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)))),
          SizedBox(width: 44,
              child: Text(row.unite ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))),
          SizedBox(width: 72,
              child: Text(_fmt(row.quantite),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF374151)))),
          SizedBox(width: 80,
              child: Text(_fmt(row.pu),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF374151)))),
          SizedBox(width: 96,
              child: Text(_fmt(row.montant),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1C2B3A)))),
        ]),
      ),
    );
  }
}

class _SectionTotal extends StatelessWidget {
  final EstimRow row;
  const _SectionTotal({required this.row});

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(children: [
        Expanded(
          child: Text(row.numero,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0D47A1))),
        ),
        Text(_fmt(row.montant),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
      ]),
    );
  }
}

class _GrandTotal extends StatelessWidget {
  final EstimRow row;
  const _GrandTotal({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        const Icon(Icons.summarize_rounded, size: 16, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Text(row.description,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        Text(_fmt(row.montant),
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
      ]),
    );
  }
}
