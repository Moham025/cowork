// lib/widgets/image_carousel.dart

import 'package:flutter/material.dart';
import 'dart:io';

class ImageCarousel extends StatefulWidget {
  final List<String> images;

  const ImageCarousel({Key? key, required this.images}) : super(key: key);

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  int _currentIndex = 0;

  void _precedent() {
    if (widget.images.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex - 1) % widget.images.length;
      if (_currentIndex < 0) _currentIndex = widget.images.length - 1;
    });
  }

  void _suivant() {
    if (widget.images.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.images.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text(
                'Aucune image disponible',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1a1a1a),
      child: Stack(
        children: [
          // Image principale
          Center(
            child: Image.file(
              File(widget.images[_currentIndex]),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, size: 80, color: Colors.grey),
                      SizedBox(height: 20),
                      Text(
                        'Erreur de chargement',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bouton Précédent
          if (widget.images.length > 1)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left, size: 32),
                    color: Colors.white,
                    onPressed: _precedent,
                  ),
                ),
              ),
            ),

          // Bouton Suivant
          if (widget.images.length > 1)
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right, size: 32),
                    color: Colors.white,
                    onPressed: _suivant,
                  ),
                ),
              ),
            ),

          // Indicateurs
          if (widget.images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _currentIndex ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == _currentIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

          // Compteur d'images
          if (widget.images.length > 1)
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
