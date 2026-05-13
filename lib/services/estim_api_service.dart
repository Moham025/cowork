// lib/services/estim_api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── Modèles ─────────────────────────────────────────────────────────────────

class EstimRow {
  final String type;
  // types communs : section_hdr | item | section_total | grand_total
  // types matériaux : mat_header | mat_item | mat_total
  final String numero;
  final String description;
  final String? unite;
  final double? quantite;
  final double? pu;
  final double? montant;

  // Pour les lignes matériaux
  final List<String>? matHeaders;
  final List<double>? matValues;

  const EstimRow({
    required this.type,
    required this.numero,
    required this.description,
    this.unite,
    this.quantite,
    this.pu,
    this.montant,
    this.matHeaders,
    this.matValues,
  });

  Map<String, dynamic> toJson() => {
        'type':        type,
        'num':         numero,
        'description': description,
        'unite':       unite,
        'quantite':    quantite,
        'pu':          pu,
        'montant':     montant,
        if (matHeaders != null) 'headers': matHeaders,
        if (matValues  != null) 'values':  matValues,
      };

  factory EstimRow.fromJson(Map<String, dynamic> j) {
    List<String>? hdrs;
    List<double>? vals;
    if (j['headers'] != null) {
      hdrs = (j['headers'] as List).map((e) => e.toString()).toList();
    }
    if (j['values'] != null) {
      vals = (j['values'] as List)
          .map((e) => e == null ? 0.0 : (e as num).toDouble())
          .toList();
    }
    return EstimRow(
      type:        j['type'] as String,
      numero:      j['num'] as String? ?? '',
      description: j['description'] as String? ?? '',
      unite:       j['unite'] as String?,
      quantite:    j['quantite'] == null ? null : (j['quantite'] as num).toDouble(),
      pu:          j['pu'] == null ? null : (j['pu'] as num).toDouble(),
      montant:     j['montant'] == null ? null : (j['montant'] as num).toDouble(),
      matHeaders:  hdrs,
      matValues:   vals,
    );
  }
}

class EstimOutput {
  final String id;
  final String label;
  final List<EstimRow> rows;

  const EstimOutput({required this.id, required this.label, required this.rows});

  Map<String, dynamic> toJson() => {
        'id':    id,
        'label': label,
        'rows':  rows.map((r) => r.toJson()).toList(),
      };

  factory EstimOutput.fromJson(Map<String, dynamic> j) => EstimOutput(
        id:    j['id'] as String,
        label: j['label'] as String,
        rows:  ((j['rows'] as List?) ?? [])
            .map((e) => EstimRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class EstimCacheEntry {
  final String timestamp;
  final String name;
  final int size;
  final DateTime modified;

  const EstimCacheEntry({
    required this.timestamp,
    required this.name,
    required this.size,
    required this.modified,
  });

  factory EstimCacheEntry.fromJson(Map<String, dynamic> j) => EstimCacheEntry(
        timestamp: j['timestamp'] as String,
        name:      j['name'] as String,
        size:      j['size'] as int,
        modified:  DateTime.parse(j['modified'] as String),
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
  String? dernierErreur;

  // ─── Chemin du script serveur ───────────────────────────────────────────────

  static String get serverScriptPath {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidate = '$exeDir/EstimBatiment/estim_server.py';
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
    return r'D:\BOLO\10-ngnior_conception_flutter\EstimBatiment\estim_server.py';
  }

  // ─── Cycle de vie ───────────────────────────────────────────────────────────

  Future<bool> demarrerServeur({bool forceRestart = false}) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return false;
    }
    arreterServeur();
    await _tuerProcessSurPort(8765);
    await Future.delayed(const Duration(milliseconds: 600));

    final scriptPath = serverScriptPath;
    debugPrint('[EstimAPI] script: $scriptPath');
    debugPrint('[EstimAPI] existe: ${File(scriptPath).existsSync()}');

    try {
      _serverProcess = await Process.start('python', [scriptPath]);

      final errBuf = StringBuffer();
      _serverProcess!.stderr.listen((d) {
        final s = String.fromCharCodes(d);
        errBuf.write(s);
        debugPrint('[estim stderr] $s');
      });
      _serverProcess!.stdout.listen((d) {
        debugPrint('[estim stdout] ${String.fromCharCodes(d)}');
      });

      bool crashed = false;
      _serverProcess!.exitCode.then((code) {
        crashed = true;
        debugPrint('[EstimAPI] process terminé code=$code stderr=$errBuf');
      });

      for (int i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (crashed) {
          dernierErreur = 'Process Python terminé prématurément.\n$errBuf';
          return false;
        }
        if (await _ping(timeout: 400)) return true;
      }
      dernierErreur = 'Timeout — serveur non démarré après 17 s.\nstderr: $errBuf';
      return false;
    } catch (e) {
      dernierErreur = 'Impossible de lancer Python : $e';
      debugPrint('[EstimAPI] exception: $e');
      return false;
    }
  }

  void arreterServeur() {
    _serverProcess?.kill();
    _serverProcess = null;
  }

  Future<void> _tuerProcessSurPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      // PowerShell : plus fiable que netstat sur Windows
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '\$p=(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue).OwningProcess;'
            r'if($p){Stop-Process -Id $p -Force -ErrorAction SilentlyContinue;Write-Host "killed:$p"}'
      ]);
      final out = (res.stdout as String).trim();
      if (out.isNotEmpty) debugPrint('[EstimAPI] $out');
    } catch (e) {
      // Fallback cmd+netstat
      try {
        final res2 = await Process.run(
          'cmd',
          ['/c', 'for /f "tokens=5" %a in (\'netstat -aon ^| findstr ":$port "\') do taskkill /F /PID %a'],
        );
        debugPrint('[EstimAPI] fallback kill: ${res2.stdout}');
      } catch (_) {}
      debugPrint('[EstimAPI] _tuerProcessSurPort: $e');
    }
  }

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

  // ─── API calls ──────────────────────────────────────────────────────────────

  Future<({String timestamp, List<EstimOutput> outputs})> traiterFichier(
      String cheminFichier) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/process'));
    req.files.add(await http.MultipartFile.fromPath('file', cheminFichier));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      // FastAPI detail peut être une String ou une List
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final detail = decoded['detail'];
          throw Exception(detail is String ? detail : detail.toString());
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
      throw Exception('Erreur serveur ${streamed.statusCode}\n$body');
    }
    final decoded = jsonDecode(body);
    if (decoded == null) {
      throw Exception('Réponse vide du serveur');
    }
    final data = decoded as Map<String, dynamic>;
    final rawOutputs = data['outputs'];
    if (rawOutputs == null) {
      throw Exception('Champ outputs manquant.\nRéponse: $body');
    }
    final outputs = (rawOutputs as List)
        .map((e) => EstimOutput.fromJson(e as Map<String, dynamic>))
        .toList();
    return (timestamp: data['timestamp'] as String, outputs: outputs);
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

  Future<({String timestamp, List<EstimOutput> outputs})> chargerDepuisCache(
      String ts) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(ts)}/data'))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Résultat introuvable');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final outputs = (data['outputs'] as List)
        .map((e) => EstimOutput.fromJson(e as Map<String, dynamic>))
        .toList();
    return (timestamp: data['timestamp'] as String, outputs: outputs);
  }

  Future<List<int>> exporterXlsx(String ts, String outputId) async {
    final resp = await http
        .get(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(ts)}/export/$outputId'))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('Export XLSX échoué (${resp.statusCode})');
    return resp.bodyBytes;
  }

  Future<void> supprimerCache(String ts) async {
    await http
        .delete(Uri.parse('$baseUrl/cache/${Uri.encodeComponent(ts)}'))
        .timeout(const Duration(seconds: 10));
  }

  Future<void> viderCache() async {
    await http
        .delete(Uri.parse('$baseUrl/cache'))
        .timeout(const Duration(seconds: 10));
  }
}
