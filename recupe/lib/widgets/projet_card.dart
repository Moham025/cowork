// lib/widgets/projet_card.dart

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../models/projet_model.dart';

class ProjetCard extends StatefulWidget {
  final Projet projet;
  final VoidCallback onTap;

  const ProjetCard({
    Key? key,
    required this.projet,
    required this.onTap,
  }) : super(key: key);

  @override
  State<ProjetCard> createState() => _ProjetCardState();
}

class _ProjetCardState extends State<ProjetCard> {
  bool _isHovered = false;

  Future<void> _ouvrirFichier(String chemin) async {
    final uri = Uri.file(chemin);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.projet;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _isHovered ? const Color(0xFF3B8ED0) : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovered ? 0.2 : 0.1),
                blurRadius: _isHovered ? 20 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IMAGE avec badges logiciels
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: AspectRatio(
                  aspectRatio: 16 / 9.2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildImage(),
                      // Badges en bas à droite
                      if (p.hasArchicad || p.hasTwinmotion || p.hasEstimType)
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.hasArchicad)
                                _buildBadge(
                                  'assets/icones/menu-logo-archicad.png',
                                  onTap: () => _ouvrirFichier(p.archicadPath!),
                                ),
                              if (p.hasArchicad && p.hasTwinmotion)
                                const SizedBox(width: 4),
                              if (p.hasTwinmotion)
                                _buildBadge(
                                  'assets/icones/twinmotion.master.png',
                                  onTap: () => _ouvrirFichier(p.twinmotionPath!),
                                ),
                              if ((p.hasArchicad || p.hasTwinmotion) && p.hasEstimType)
                                const SizedBox(width: 4),
                              if (p.hasEstimType)
                                _buildBadge(
                                  'assets/icones/microsoft-excel-2019.jpg',
                                  onTap: () => _ouvrirFichier(p.estimTypePath!),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ZONE TEXTE
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.projet.nomProjet.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.projet.surfaceHabitable.toStringAsFixed(0)} m² • ${widget.projet.categorie}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF95a5a6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String assetPath, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      // Intercepte le tap avant qu'il remonte à GestureDetector parent
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (!widget.projet.hasImages) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Text(
            'Aucune image',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ),
      );
    }

    try {
      return Image.file(
        File(widget.projet.imageVignette),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
            ),
          );
        },
      );
    } catch (e) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Icon(Icons.error_outline, color: Colors.grey, size: 40),
        ),
      );
    }
  }
}
