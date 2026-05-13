// lib/screens/creation_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../services/creation_service.dart';
import '../services/storage_service.dart';

class CreationScreen extends StatefulWidget {
  const CreationScreen({super.key});

  @override
  State<CreationScreen> createState() => _CreationScreenState();
}

class _CreationScreenState extends State<CreationScreen> {
  final _service = CreationService();
  bool _loading = true;
  bool _disponible = false;
  String _categorieActive = 'Tous';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final cataloguePath = StorageService().getCataloguePath();
    if (cataloguePath == null) {
      setState(() { _loading = false; _disponible = false; });
      return;
    }
    final ok = await _service.charger(cataloguePath);
    if (mounted) setState(() { _loading = false; _disponible = ok; });
  }

  List<String> get _categories {
    final cats = _service.projets.map((p) => p.categorie).toSet().toList()..sort();
    return ['Tous', ...cats];
  }

  List<ProjetCreation> get _projetsFiltres {
    if (_categorieActive == 'Tous') return _service.projets;
    return _service.projets.where((p) => p.categorie == _categorieActive).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          if (!_loading) _buildCategoryBar(),
          Expanded(child: _buildBody()),
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
        color: Color(0xFF1C2B3A),
        boxShadow: [BoxShadow(color: Color(0x28000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF3B8ED0)),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Tableau de bord',
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF3B8ED0).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3B8ED0).withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.draw_rounded, color: Color(0xFF3B8ED0), size: 18),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Catalogue Création',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${_projetsFiltres.length} projet${_projetsFiltres.length > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 11, color: const Color(0xFF3B8ED0).withValues(alpha: 0.8))),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Category bar ─────────────────────────────────────────────────────────

  Widget _buildCategoryBar() {
    return Container(
      color: Colors.white,
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final active = cat == _categorieActive;
          return GestureDetector(
            onTap: () => setState(() => _categorieActive = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF3B8ED0) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3B8ED0)));
    }
    if (!_disponible) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_rounded, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Dossier CREATION introuvable',
                style: TextStyle(fontSize: 15, color: Colors.grey[400], fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('Il doit se trouver à côté du dossier Habitation',
                style: TextStyle(fontSize: 12, color: Colors.grey[350])),
          ],
        ),
      );
    }
    if (_projetsFiltres.isEmpty) {
      return Center(child: Text('Aucun projet', style: TextStyle(color: Colors.grey[400])));
    }

    return LayoutBuilder(builder: (context, constraints) {
      int cols = 3;
      if (constraints.maxWidth > 1400) {
        cols = 5;
      } else if (constraints.maxWidth > 1100) {
        cols = 4;
      } else if (constraints.maxWidth < 800) {
        cols = 2;
      }

      return GridView.builder(
        padding: const EdgeInsets.all(28),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 1.25,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _projetsFiltres.length,
        itemBuilder: (_, i) => _CreationCard(projet: _projetsFiltres[i]),
      );
    });
  }
}

// ─── Carte projet création ────────────────────────────────────────────────────

class _CreationCard extends StatefulWidget {
  final ProjetCreation projet;
  const _CreationCard({required this.projet});

  @override
  State<_CreationCard> createState() => _CreationCardState();
}

class _CreationCardState extends State<_CreationCard> {
  bool _hovered = false;

  Future<void> _ouvrirDossier() async {
    final uri = Uri.file(widget.projet.cheminDossier);
    await launchUri(uri);
  }

  Future<void> launchUri(Uri uri) async {
    if (Platform.isWindows) {
      await Process.start('explorer', [uri.toFilePath()],
          mode: ProcessStartMode.detached);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _ouvrirDossier,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? const Color(0xFF3B8ED0) : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.14 : 0.06),
                blurRadius: _hovered ? 20 : 10,
                offset: Offset(0, _hovered ? 6 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image vignette
                Expanded(
                  flex: 7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(),
                      // Badge catégorie
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2B3A).withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            widget.projet.categorie,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                      // Hover: icône dossier
                      if (_hovered)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF3B8ED0)),
                          ),
                        ),
                    ],
                  ),
                ),
                // Nom
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.projet.nom,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C2B3A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CRÉATION · ${widget.projet.categorie}',
                          style: const TextStyle(fontSize: 9, color: Color(0xFF95a5a6)),
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

  Widget _buildImage() {
    if (widget.projet.imagePath != null) {
      return Image.file(
        File(widget.projet.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFECF0F1),
      child: Center(
        child: Icon(Icons.draw_outlined, size: 36, color: Colors.grey[300]),
      ),
    );
  }
}
