// lib/main.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'services/storage_service.dart';
import 'services/catalogue_service.dart';
import 'services/estim_api_service.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NGnior Bureau',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Roboto'),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storageService = StorageService();
  final _catalogueService = CatalogueService();

  double _progress = 0;
  String _message = 'Initialisation...';

  @override
  void initState() {
    super.initState();
    _chargerApplication();
  }

  Future<void> _chargerApplication() async {
    try {
      // Démarrage du serveur EstimBatiment en arrière-plan (sans bloquer)
      EstimApiService().demarrerServeur();

      _updateProgress(0.2, 'Vérification du catalogue...');
      await Future.delayed(const Duration(milliseconds: 300));

      String? cheminCatalogue = _storageService.getCataloguePath();

      // Si on a un chemin sauvegardé ET qu'il existe toujours → chargement direct
      if (cheminCatalogue != null && Directory(cheminCatalogue).existsSync()) {
        _updateProgress(0.6, 'Chargement des projets...');
        final success =
            await _catalogueService.chargerCatalogue(cheminCatalogue);

        if (success) {
          _updateProgress(0.9, 'Optimisation...');
          await Future.delayed(const Duration(milliseconds: 300));
          _updateProgress(1.0, 'Ouverture de l\'application...');
          await Future.delayed(const Duration(milliseconds: 500));
          _allerVersGalerie();
          return;
        }
      }

      // Sinon : on demande à l'utilisateur de sélectionner le dossier
      _updateProgress(0.4, 'Sélection du dossier catalogue...');
      await Future.delayed(const Duration(milliseconds: 300));

      cheminCatalogue = await _demanderDossier();

      if (cheminCatalogue == null) {
        // Utilisateur a annulé → on va quand même à la galerie (vide)
        _updateProgress(1.0, 'Catalogue non sélectionné');
        await Future.delayed(const Duration(milliseconds: 500));
        _allerVersGalerie();
        return;
      }

      // Sauvegarde du nouveau chemin pour les prochains lancements
      await _storageService.saveCataloguePath(cheminCatalogue);

      // Chargement du catalogue
      _updateProgress(0.6, 'Chargement des projets...');
      final success = await _catalogueService.chargerCatalogue(cheminCatalogue);

      if (!success) {
        _updateProgress(0.8, 'Erreur de chargement...');
        await Future.delayed(const Duration(seconds: 1));
        _allerVersGalerie();
        return;
      }

      // Finalisation
      _updateProgress(0.9, 'Optimisation...');
      await Future.delayed(const Duration(milliseconds: 300));

      _updateProgress(1.0, 'Ouverture de l\'application...');
      await Future.delayed(const Duration(milliseconds: 500));

      _allerVersGalerie();
    } catch (e) {
      print('Erreur splash: $e');
      _updateProgress(1.0, 'Erreur: $e');
      await Future.delayed(const Duration(seconds: 2));
      _allerVersGalerie();
    }
  }

  Future<String?> _demanderDossier() async {
    return await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Sélectionnez le dossier "Habitation" du catalogue',
    );
  }

  void _updateProgress(double progress, String message) {
    setState(() {
      _progress = progress;
      _message = message;
    });
  }

  void _allerVersGalerie() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2c3e50),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Text(
                'NGnior',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'CONCEPTION',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3498db),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 60),

              // Message
              Text(
                _message,
                style: const TextStyle(fontSize: 14, color: Color(0xFFecf0f1)),
              ),
              const SizedBox(height: 20),

              // Barre de progression
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF34495e),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF3498db),
                  ),
                ),
              ),
              const SizedBox(height: 60),

              // Version
              const Text(
                'Architecture Digital Gallery v2.0',
                style: TextStyle(fontSize: 10, color: Color(0xFF7f8c8d)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
