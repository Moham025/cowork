// lib/services/estim_api_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── Modèles ─────────────────────────────────────────────────────────────────

class EstimRow {
  final String type; // block_hdr | data | total | recap_hdr | recap_item | grand_total
  final String numero;
  final String description;
  final String? unite;
  final double? quantite;
  final double? pu;
  final double? montant;

  const EstimRow({
    required this.type,
    required this.numero,
    required this.description,
    this.unite,
    this.quantite,
    this.pu,
    this.montant,
  });

  factory EstimRow.fromJson(Map<String, dynamic> j) => EstimRow(
        type: j['type'] as String,
        numero: j['num'] as String? ?? '',
        description: j['description'] as String? ?? '',
        unite: j['unite'] as String?,
        quantite: j['quantite'] == null ? null : (j['quantite'] as num).toDouble(),
        pu: j['pu'] == null ? null : (j['pu'] as num).toDouble(),
        montant: j['montant'] == null ? null : (j['montant'] as num).toDouble(),
      );
}

class EstimCacheEntry {
  final String name;
  final int size;
  final DateTime modified;

  const EstimCacheEntry({
    required this.name,
    required this.size,
    required this.modified,
  });

  factory EstimCacheEntry.fromJson(Map<String, dynamic> j) => EstimCacheEntry(
        name: j['name'] as String,
        size: j['size'] as int,
        modified: DateTime.parse(j['modified'] as String),
      );
}

/// Représente une ligne du tableau détail matériaux.
class DetailRow {
  final String type; // section | data | total_general | resume_hdr | resume_item
  final String numero;
  final String description;
  final String? unite;
  final double? quantite;
  final double? ciment;
  final double? brique;
  final double? hourdi;
  final double? sable;
  final double? granite;
  final double? planche;
  final double? terre;
  final double? ha6;
  final double? ha8;
  final double? ha10;
  final double? ha12;
  final double? ha14;
  final String? totalDisplay;
  final String? resultDisplay;

  const DetailRow({
    required this.type,
    required this.numero,
    required this.description,
    this.unite,
    this.quantite,
    this.ciment,
    this.brique,
    this.hourdi,
    this.sable,
    this.granite,
    this.planche,
    this.terre,
    this.ha6,
    this.ha8,
    this.ha10,
    this.ha12,
    this.ha14,
    this.totalDisplay,
    this.resultDisplay,
  });

  factory DetailRow.fromJson(Map<String, dynamic> j) => DetailRow(
        type: j['type'] as String? ?? 'data',
        numero: j['num'] as String? ?? '',
        description: j['description'] as String? ?? '',
        unite: j['unite'] as String?,
        quantite: j['quantite'] == null ? null : (j['quantite'] as num).toDouble(),
        ciment: j['ciment'] == null ? null : (j['ciment'] as num).toDouble(),
        brique: j['brique'] == null ? null : (j['brique'] as num).toDouble(),
        hourdi: j['hourdi'] == null ? null : (j['hourdi'] as num).toDouble(),
        sable: j['sable'] == null ? null : (j['sable'] as num).toDouble(),
        granite: j['granite'] == null ? null : (j['granite'] as num).toDouble(),
        planche: j['planche'] == null ? null : (j['planche'] as num).toDouble(),
        terre: j['terre'] == null ? null : (j['terre'] as num).toDouble(),
        ha6: j['ha6'] == null ? null : (j['ha6'] as num).toDouble(),
        ha8: j['ha8'] == null ? null : (j['ha8'] as num).toDouble(),
        ha10: j['ha10'] == null ? null : (j['ha10'] as num).toDouble(),
        ha12: j['ha12'] == null ? null : (j['ha12'] as num).toDouble(),
        ha14: j['ha14'] == null ? null : (j['ha14'] as num).toDouble(),
        totalDisplay: j['total_display'] as String?,
        resultDisplay: j['result_display'] as String?,
      );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class EstimApiService {
  static final EstimApiService _instance = EstimApiService._internal();
  factory EstimApiService() => _instance;
  EstimApiService._internal();

  static const _defaultBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8765',
  );

  String get baseUrl => _defaultBase;

  Process? _serverProcess;
  String? dernierErreur; // Exposé pour l'affichage debug

  // ─── Chemin du script serveur ───────────────────────────────────────────────

  static String get serverScriptPath {
    try {
      // En release : chercher EstimBatiment/ à côté de l'exécutable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidate = '$exeDir/EstimBatiment/estim_server.py';
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
    // Fallback dev
    return r'D:\BOLO\10-ngnior_conception_flutter\EstimBatiment\estim_server.py';
  }

  // ─── Cycle de vie du serveur ────────────────────────────────────────────────

  Future<bool> demarrerServeur({bool forceRestart = false}) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false; // Web → serveur distant
    }

    // Toujours tuer l'ancien serveur pour charger le code Python à jour
    arreterServeur();
    await _tuerProcessSurPort(8765);
    await Future.delayed(const Duration(milliseconds: 600));

    final scriptPath = serverScriptPath;
    debugPrint('[EstimAPI] script: $scriptPath');
    debugPrint('[EstimAPI] script existe: ${File(scriptPath).existsSync()}');

    try {
      _serverProcess = await Process.start('python', [scriptPath]);

      // Capturer stderr pour le debug
      final errBuf = StringBuffer();
      final outBuf = StringBuffer();
      _serverProcess!.stderr.listen((d) {
        final s = String.fromCharCodes(d);
        errBuf.write(s);
        debugPrint('[estim stderr] $s');
      });
      _serverProcess!.stdout.listen((d) {
        final s = String.fromCharCodes(d);
        outBuf.write(s);
        debugPrint('[estim stdout] $s');
      });

      // Détecter crash immédiat
      bool crashed = false;
      _serverProcess!.exitCode.then((code) {
        crashed = true;
        debugPrint('[EstimAPI] process terminé code=$code');
        debugPrint('[EstimAPI] stderr=$errBuf');
      });

      // Polling : 400 ms timeout × 25 essais ≈ 17 s max
      for (int i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (crashed) {
          dernierErreur = 'Process Python terminé prématurément.\n$errBuf';
          return false;
        }
        if (await _ping(timeout: 400)) return true;
      }
      dernierErreur = 'Timeout — serveur non démarré après 17 s.\nstderr: $errBuf';
      debugPrint('[EstimAPI] timeout. stderr=$errBuf');
      return false;
    } catch (e) {
      dernierErreur = 'Impossible de lancer Python : $e';
      debugPrint('[EstimAPI] exception: $e');
      return false;
    }
  }

  /// Tue le process qui écoute sur [port] (Windows uniquement).
  Future<void> _tuerProcessSurPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      final res = await Process.run(
        'cmd',
        ['/c', 'netstat -ano | findstr ":$port " | findstr "LISTENING"'],
      );
      final output = (res.stdout as String).trim();
      final match = RegExp(r'\s+(\d+)\s*$', multiLine: true).firstMatch(output);
      if (match != null) {
        final pid = match.group(1)!;
        await Process.run('taskkill', ['/F', '/PID', pid]);
        debugPrint('[EstimAPI] ancien serveur tué (PID=$pid)');
      }
    } catch (e) {
      debugPrint('[EstimAPI] _tuerProcessSurPort: $e');
    }
  }

  /// Ping rapide avec timeout configurable (ms). N'affecte pas verifierSante().
  Future<bool> _ping({int timeout = 400}) async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(Duration(milliseconds: timeout));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void arreterServeur() {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  // ─── Appels API ─────────────────────────────────────────────────────────────

  Future<bool> verifierSante() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Envoie le fichier xlsx au serveur et retourne les lignes parsées.
  Future<({String filename, int blocsCount, List<EstimRow> rows})> traiterFichier(
      String cheminFichier) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/process'));
    req.files.add(await http.MultipartFile.fromPath('file', cheminFichier));
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      final err = jsonDecode(body) as Map<String, dynamic>;
      throw Exception(err['detail'] ?? 'Erreur serveur ${streamed.statusCode}');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final rows = (data['rows'] as List)
        .map((e) => EstimRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      filename: data['filename'] as String,
      blocsCount: data['blocs_count'] as int,
      rows: rows,
    );
  }

  Future<List<EstimCacheEntry>> listerCache() async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache'))
        .timeout(const Duration(seconds: 10));
    final list = jsonDecode(resp.body) as List;
    return list
        .map((e) => EstimCacheEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({String filename, List<EstimRow> rows})> chargerDepuisCache(
      String name) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(name)}/rows'))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Fichier introuvable en cache');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rows = (data['rows'] as List)
        .map((e) => EstimRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (filename: data['filename'] as String, rows: rows);
  }

  Future<({String filename, List<DetailRow> rows})> chargerDetailDepuisCache(
      String name) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(name)}/detail-rows'))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Détail introuvable en cache');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final rows = (data['rows'] as List)
        .map((e) => DetailRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (filename: data['filename'] as String, rows: rows);
  }

  /// Télécharge le fichier xlsx en bytes.
  Future<Uint8List> telechargerFichier(String name) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(name)}/download'))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) throw Exception('Erreur téléchargement');
    return resp.bodyBytes;
  }

  Future<void> supprimerCache(String name) async {
    await http
        .delete(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(name)}'))
        .timeout(const Duration(seconds: 10));
  }

  Future<void> viderCache() async {
    await http
        .delete(Uri.parse('$baseUrl/cache'))
        .timeout(const Duration(seconds: 10));
  }

  /// Envoie le fichier xlsx au serveur pour calcul détail matériaux.
  Future<({String filename, List<DetailRow> rows})> calculerDetail(
      String cheminFichier) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/process-detail'));
    req.files.add(await http.MultipartFile.fromPath('file', cheminFichier));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      final err = jsonDecode(body) as Map<String, dynamic>;
      throw Exception(err['detail'] ?? 'Erreur serveur ${streamed.statusCode}');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final rows = (data['rows'] as List)
        .map((e) => DetailRow.fromJson(e as Map<String, dynamic>))
        .toList();
    return (filename: data['filename'] as String, rows: rows);
  }

  /// Force le redémarrage du serveur Python (kill + restart).
  Future<bool> redemarrerServeur() async {
    arreterServeur();
    await _tuerProcessSurPort(8765);
    await Future.delayed(const Duration(milliseconds: 800));
    return demarrerServeur();
  }

  /// Exporte un fichier du cache en PDF via le serveur.
  Future<Uint8List> exporterPdf(String name) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(name)}/export-pdf'))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) throw Exception('Erreur export PDF');
    return resp.bodyBytes;
  }
}
