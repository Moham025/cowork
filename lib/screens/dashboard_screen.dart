// lib/screens/dashboard_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/projet_model.dart';
import '../services/catalogue_service.dart';
import '../services/storage_service.dart';
import 'creation_screen.dart';
import 'details_screen.dart';
import 'estim_batiment_screen.dart';
import 'galerie_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

// Représente un projet créé mais sans infos.json
typedef _DossierEnCours = ({String name, String category, String path});

class _DashboardScreenState extends State<DashboardScreen> {
  final _catalogueService = CatalogueService();
  final _storageService   = StorageService();

  List<Projet>           _recentProjets      = [];
  List<_DossierEnCours>  _dossiersEnCours    = [];

  @override
  void initState() {
    super.initState();
    _loadRecentProjets();
    _scannerDossiersEnCours();
  }

  void _loadRecentProjets() {
    final paths     = _storageService.getRecentlyViewedPaths();
    final allProjets = _catalogueService.projets;

    final recent = <Projet>[];
    for (final path in paths) {
      for (final p in allProjets) {
        if (p.cheminDossier == path) { recent.add(p); break; }
      }
      if (recent.length == 2) break;
    }
    setState(() => _recentProjets = recent);
  }

  /// Parcourt le catalogue et détecte les dossiers avec structure Png mais sans infos.json.
  Future<void> _scannerDossiersEnCours() async {
    final cataloguePath = _storageService.getCataloguePath();
    if (cataloguePath == null) return;

    final root = Directory(cataloguePath);
    if (!root.existsSync()) return;

    final sep        = Platform.pathSeparator;
    final incomplete = <_DossierEnCours>[];

    for (final catEntity in root.listSync()) {
      if (catEntity is! Directory) continue;
      final category = catEntity.path.split(sep).last;
      if (category.startsWith('.')) continue;

      for (final projEntity in catEntity.listSync()) {
        if (projEntity is! Directory) continue;
        final projName = projEntity.path.split(sep).last;
        if (projName.startsWith('.')) continue;

        final hasInfos = File('${projEntity.path}${sep}infos.json').existsSync();
        final hasPng   = Directory('${projEntity.path}${sep}Png').existsSync();

        if (!hasInfos && hasPng) {
          incomplete.add((
            name:     projName,
            category: category,
            path:     projEntity.path,
          ));
        }
      }
    }

    if (mounted) setState(() => _dossiersEnCours = incomplete);
  }

  void _ouvrirDossierEnCours(_DossierEnCours d) {
    final projet = Projet(
      nomProjet:            d.name,
      categorie:            d.category,
      surfaceHabitable:     0,
      descriptionMarketing: '',
      nombreEtages:         1,
      detailsTechniques:    {},
      coutConstruction:     0,
      cheminDossier:        d.path,
      images:               [],
      rawJson:              {},
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(projet: projet, initialImageSource: 'A'),
      ),
    ).then((_) {
      _loadRecentProjets();
      _scannerDossiersEnCours(); // Re-scan : si infos.json créé, retire de la liste
    });
  }

  void _ouvrirEstimBatiment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EstimBatimentScreen()),
    );
  }

  void _ouvrirCreation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreationScreen()),
    ).then((_) => _loadRecentProjets());
  }

  void _ouvrirGalerie() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GalerieScreen()),
    ).then((_) => _loadRecentProjets());
  }

  void _ouvrirProjet(Projet projet) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailsScreen(projet: projet)),
    ).then((_) => _loadRecentProjets());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 48, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecentSection(),
                      if (_dossiersEnCours.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        _buildDossiersEnCoursSection(),
                      ],
                      const SizedBox(height: 32),
                      _buildQuickAccessSection(),
                      const SizedBox(height: 32),
                      _buildOutilsSection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 88,
      decoration: const BoxDecoration(
        color: Color(0xFF1C2B3A),
        boxShadow: [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF3B8ED0).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF3B8ED0).withValues(alpha: 0.35),
                    width: 1.5),
              ),
              child: const Icon(Icons.architecture_rounded,
                  color: Color(0xFF3B8ED0), size: 26),
            ),
            const SizedBox(width: 18),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NGnior',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.4,
                    height: 1.1,
                  ),
                ),
                Text(
                  'CONCEPTION  ·  TABLEAU DE BORD',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF3B8ED0).withValues(alpha: 0.85),
                    letterSpacing: 2.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Section label ─────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: const Color(0xFF3B8ED0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dossiers en cours de création ────────────────────────────────────────

  Widget _buildDossiersEnCoursSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('FICHIERS EN COURS DE CRÉATION'),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _dossiersEnCours.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final d = _dossiersEnCours[i];
              return _DossierEnCoursCard(
                dossier: d,
                onTap: () => _ouvrirDossierEnCours(d),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Recently viewed section ───────────────────────────────────────────────

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('DERNIERS DOSSIERS CONSULTÉS'),
        _recentProjets.isEmpty
            ? _buildEmptyRecent()
            : Row(
                children: [
                  Expanded(
                    child: _recentProjets.isNotEmpty
                        ? _RecentCard(
                            projet: _recentProjets[0],
                            onTap: () => _ouvrirProjet(_recentProjets[0]),
                          )
                        : _buildEmptyCard(),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _recentProjets.length > 1
                        ? _RecentCard(
                            projet: _recentProjets[1],
                            onTap: () => _ouvrirProjet(_recentProjets[1]),
                          )
                        : _buildEmptyCard(),
                  ),
                ],
              ),
      ],
    );
  }

  Widget _buildEmptyRecent() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 44, color: Colors.grey[200]),
            const SizedBox(height: 14),
            Text(
              'Aucun dossier consulté récemment',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ouvrez la galerie pour explorer les projets',
              style: TextStyle(fontSize: 12, color: Colors.grey[350]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, size: 34, color: Colors.grey[200]),
            const SizedBox(height: 8),
            Text(
              'Aucun dossier',
              style: TextStyle(fontSize: 13, color: Colors.grey[300]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Quick access section ──────────────────────────────────────────────────

  Widget _buildQuickAccessSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ACCÈS RAPIDE'),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.grid_view_rounded,
                label: 'Galerie complète',
                subtitle:
                    '${_catalogueService.projets.length} projets disponibles',
                color: const Color(0xFF3B8ED0),
                isPrimary: true,
                onTap: _ouvrirGalerie,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _ActionCard(
                icon: Icons.draw_rounded,
                label: 'Catalogue Création',
                subtitle: 'A Niveau · Appartement · Villa',
                color: const Color(0xFF7C3AED),
                isPrimary: false,
                onTap: _ouvrirCreation,
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: _PlaceholderCard(
                icon: Icons.favorite_border_rounded,
                label: 'Favoris',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Outils section ───────────────────────────────────────────────────────

  Widget _buildOutilsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('OUTILS'),
        Row(
          children: [
            Expanded(
              child: _ToolCard(
                imagePath: 'assets/icones/Eb-02.jpg',
                label: 'EstimBatiment',
                subtitle: 'Estimation & chiffrage',
                onTap: _ouvrirEstimBatiment,
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(child: SizedBox()),
            const SizedBox(width: 18),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  // ─── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        'Architecture Digital Gallery  ·  v2.0',
        style: TextStyle(
            fontSize: 11, color: Colors.grey[400], letterSpacing: 0.4),
      ),
    );
  }
}

// ─── Recent card widget (with hover effect) ───────────────────────────────────

class _RecentCard extends StatefulWidget {
  final Projet projet;
  final VoidCallback onTap;

  const _RecentCard({required this.projet, required this.onTap});

  @override
  State<_RecentCard> createState() => _RecentCardState();
}

class _RecentCardState extends State<_RecentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.13 : 0.05),
                blurRadius: _hovered ? 24 : 12,
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image area
                Expanded(
                  flex: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.projet.hasImages
                          ? Image.file(
                              File(widget.projet.imageVignette),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _imagePlaceholder(),
                            )
                          : _imagePlaceholder(),
                      // Bottom gradient
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.38),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Category tag
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD3E3FD),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.projet.categorie.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF174EA6),
                            ),
                          ),
                        ),
                      ),
                      // Hover arrow
                      if (_hovered)
                        Positioned(
                          bottom: 10,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Color(0xFF3B8ED0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Info area
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.projet.nomProjet,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C2B3A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.projet.budgetFormate,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFECF0F1),
      child: const Center(
        child: Icon(Icons.home_outlined, size: 44, color: Color(0xFFBDC3C7)),
      ),
    );
  }
}

// ─── Action card widget (with hover effect) ───────────────────────────────────

class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isPrimary ? widget.color : Colors.white;
    final shadowColor = widget.isPrimary
        ? widget.color.withValues(alpha: _hovered ? 0.40 : 0.22)
        : Colors.black.withValues(alpha: _hovered ? 0.09 : 0.04);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 108,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _hovered ? 20 : 10,
                offset: Offset(0, _hovered ? 6 : 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: widget.isPrimary
                        ? Colors.white
                            .withValues(alpha: _hovered ? 0.22 : 0.14)
                        : widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.isPrimary ? Colors.white : widget.color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: widget.isPrimary
                              ? Colors.white
                              : const Color(0xFF1C2B3A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isPrimary
                              ? Colors.white.withValues(alpha: 0.70)
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: widget.isPrimary
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.grey[350],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tool card widget (image icon + hover effect) ────────────────────────────

class _ToolCard extends StatefulWidget {
  final String imagePath;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.imagePath,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 108,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.09 : 0.04),
                blurRadius: _hovered ? 20 : 10,
                offset: Offset(0, _hovered ? 6 : 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    widget.imagePath,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B8ED0).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.calculate_rounded,
                          color: Color(0xFF3B8ED0), size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C2B3A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.grey[350],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dossier en cours card ────────────────────────────────────────────────────

class _DossierEnCoursCard extends StatefulWidget {
  final _DossierEnCours dossier;
  final VoidCallback onTap;
  const _DossierEnCoursCard({required this.dossier, required this.onTap});

  @override
  State<_DossierEnCoursCard> createState() => _DossierEnCoursCardState();
}

class _DossierEnCoursCardState extends State<_DossierEnCoursCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFFE67E22).withValues(alpha: 0.6)
                  : const Color(0xFFFFE0B2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE67E22)
                    .withValues(alpha: _hovered ? 0.14 : 0.06),
                blurRadius: _hovered ? 18 : 8,
                offset: Offset(0, _hovered ? 5 : 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.folder_open_rounded,
                    color: Color(0xFFE67E22), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dossier.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C2B3A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.dossier.category,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE67E22),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text('Infos manquantes',
                          style: TextStyle(fontSize: 10,
                              color: Color(0xFFE67E22),
                              fontWeight: FontWeight.w500)),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: _hovered
                      ? const Color(0xFFE67E22)
                      : Colors.grey[350]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Placeholder card widget ───────────────────────────────────────────────────

class _PlaceholderCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PlaceholderCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.grey[250], size: 22),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[300],
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Bientôt disponible',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
