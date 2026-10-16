import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

/// URL do version.json. Definida no build:
///   flutter build apk --dart-define=UPDATE_URL=https://.../version.json
/// (o workflow do GitHub já faz isso automaticamente).
const String kUpdateManifestUrl = String.fromEnvironment('UPDATE_URL');

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String notes;
  final bool force;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.notes,
    required this.force,
  });
}

class UpdateService {
  UpdateService._();

  /// Checagem leve (1 request pequeno, timeout curto). Nunca lança erro.
  static Future<UpdateInfo?> checkForUpdate() async {
    if (kUpdateManifestUrl.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse(kUpdateManifestUrl))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;

      final remoteCode = int.tryParse(data['versionCode']?.toString() ?? '');
      final apkUrl = data['apkUrl']?.toString() ?? '';
      if (remoteCode == null || apkUrl.isEmpty) return null;

      final pkg = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(pkg.buildNumber) ?? 0;
      if (remoteCode <= localCode) return null;

      final info = UpdateInfo(
        versionCode: remoteCode,
        versionName: data['versionName']?.toString() ?? '$remoteCode',
        apkUrl: apkUrl,
        notes: data['notes']?.toString() ?? '',
        force: data['force'] == true,
      );

      if (!info.force) {
        final skipped = await AppStorage.loadSkippedUpdateCode();
        if (skipped == remoteCode) return null;
      }
      return info;
    } catch (_) {
      return null;
    }
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  await showDialog(
    context: context,
    barrierDismissible: !info.force,
    builder: (ctx) => PopScope(
      canPop: !info.force,
      child: AlertDialog(
        backgroundColor: const Color(0xFF121622),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Color(0xFF00E5FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Nova versão ${info.versionName} disponível',
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.notes.isNotEmpty)
                Text(info.notes,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              const Text('Link do APK:',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 2),
              SelectableText(info.apkUrl,
                  style: const TextStyle(
                      color: Color(0xFF00E5FF), fontSize: 11)),
            ],
          ),
        ),
        actions: [
          if (!info.force) ...[
            TVFocusableItem(
              autoScroll: false,
              onSelect: () async {
                await AppStorage.saveSkippedUpdateCode(info.versionCode);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              builder: (c, f) => _updateBtn('Ignorar esta versão', f, false),
            ),
            TVFocusableItem(
              autoScroll: false,
              onSelect: () => Navigator.pop(ctx),
              builder: (c, f) => _updateBtn('Depois', f, false),
            ),
          ],
          TVFocusableItem(
            autofocus: true,
            autoScroll: false,
            onSelect: () async {
              final ok = await launchUrl(Uri.parse(info.apkUrl),
                  mode: LaunchMode.externalApplication);
              if (!ok && ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text(
                      'Sem navegador neste aparelho. Baixe o APK pelo link exibido.'),
                ));
              }
            },
            builder: (c, f) => _updateBtn('Baixar atualização', f, true),
          ),
        ],
      ),
    ),
  );
}

Widget _updateBtn(String label, bool focused, bool primary) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      gradient: primary
          ? const LinearGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF2979FF)])
          : null,
      color: primary ? null : const Color(0xFF1B2030),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: focused ? Colors.white : Colors.white12,
        width: focused ? 2 : 1,
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: primary ? Colors.black : Colors.white,
      ),
    ),
  );
}
