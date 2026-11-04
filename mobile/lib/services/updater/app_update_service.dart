import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../features/updater/update_dialog.dart';
import '../api/api_client.dart';

class AppUpdateInfo {
  final String version;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final int? apkSize;
  final String? publishedAt;

  AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    this.apkSize,
    this.publishedAt,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['latestVersion'] ?? json['version'] ?? '',
      tagName: json['tagName'] ?? json['tag_name'] ?? '',
      releaseName: json['releaseName'] ?? json['name'] ?? '',
      releaseNotes: json['releaseNotes'] ?? json['body'] ?? '',
      downloadUrl: json['downloadUrl'] ?? json['download_url'] ?? '',
      apkSize: json['apkSize'] ?? json['apk_size'],
      publishedAt: json['publishedAt'] ?? json['published_at'],
    );
  }
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._init();
  AppUpdateService._init();

  static const MethodChannel _channel = MethodChannel('com.suprimesolutions.app/updater');
  final Dio _dio = Dio();

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  AppUpdateInfo? _availableUpdate;
  AppUpdateInfo? get availableUpdate => _availableUpdate;

  /// Check whether a remote version is strictly newer than the current version
  static bool isNewerVersion(String current, String remote) {
    final cleanCurrent = current.replaceAll('v', '').split('+').first.trim();
    final cleanRemote = remote.replaceAll('v', '').split('+').first.trim();

    final curParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final remParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (curParts.length < 3) curParts.add(0);
    while (remParts.length < 3) remParts.add(0);

    for (int i = 0; i < 3; i++) {
      if (remParts[i] > curParts[i]) return true;
      if (remParts[i] < curParts[i]) return false;
    }
    return false;
  }

  /// Check if an update is available from Backend API or GitHub Releases directly
  Future<AppUpdateInfo?> checkForUpdate({
    BuildContext? context,
    bool silent = false,
  }) async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      AppUpdateInfo? updateInfo;

      // 1. Try Backend API first
      try {
        final response = await ApiClient.instance.dio.get(
          '/app/version',
          options: Options(receiveTimeout: const Duration(seconds: 8), sendTimeout: const Duration(seconds: 8)),
        );
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data['success'] == true && data['latestVersion'] != null) {
            updateInfo = AppUpdateInfo.fromJson(data);
          }
        }
      } catch (backendErr) {
        debugPrint('[AppUpdateService] Backend version check error: $backendErr. Falling back to GitHub.');
      }

      // 2. Check GitHub Releases directly if backend had no update or returned older version
      if (updateInfo == null || !isNewerVersion(AppConstants.appVersion, updateInfo.version)) {
        try {
          final ghResponse = await _dio.get(
            'https://api.github.com/repos/suprimesolution2000-art/Suprime-Solutions/releases/latest',
            options: Options(
              headers: {'Accept': 'application/vnd.github.v3+json'},
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
            ),
          );

          if (ghResponse.statusCode == 200 && ghResponse.data != null) {
            final data = ghResponse.data;
            final tagName = (data['tag_name'] ?? '').toString();
            final version = tagName.replaceAll(RegExp(r'^v'), '');
            final assets = (data['assets'] as List?) ?? [];
            final apkAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().endsWith('.apk'),
              orElse: () => null,
            );

            if (apkAsset != null) {
              final ghInfo = AppUpdateInfo(
                version: version,
                tagName: tagName,
                releaseName: data['name'] ?? 'Version $version',
                releaseNotes: data['body'] ?? '',
                downloadUrl: apkAsset['browser_download_url'] ?? '',
                apkSize: apkAsset['size'],
                publishedAt: data['published_at'],
              );
              if (isNewerVersion(AppConstants.appVersion, ghInfo.version)) {
                updateInfo = ghInfo;
              }
            }
          }
        } catch (ghErr) {
          debugPrint('[AppUpdateService] GitHub releases check error: $ghErr');
        }
      }

      // 3. Evaluate if update is newer
      if (updateInfo != null && isNewerVersion(AppConstants.appVersion, updateInfo.version)) {
        _availableUpdate = updateInfo;
        if (context != null && context.mounted) {
          UpdateDialog.show(context, updateInfo);
        }
        return updateInfo;
      } else {
        _availableUpdate = null;
        if (!silent && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are on the latest version (v${AppConstants.appVersion})'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return null;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] General error checking updates: $e');
      if (!silent && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check for updates. Please check your connection.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// Check if Android allows installing unknown apps
  Future<bool> canRequestPackageInstalls() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool canInstall = await _channel.invokeMethod('canRequestPackageInstalls') ?? false;
      return canInstall;
    } catch (_) {
      return false;
    }
  }

  /// Open Android settings to enable install unknown apps for Suprime Solutions
  Future<void> openInstallPermissionSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to open install permission settings: $e');
    }
  }

  /// Download APK with progress and launch installer
  Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    required Function(int received, int total) onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('In-app updates are only supported on Android devices.');
    }

    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}/Suprime_Solutions_${info.version}.apk';
    final targetFile = File(savePath);

    // If file already exists and size matches, install immediately
    if (await targetFile.exists()) {
      final fileLength = await targetFile.length();
      if (info.apkSize != null && fileLength == info.apkSize) {
        onProgress(fileLength, fileLength);
        await _installApk(savePath);
        return;
      } else {
        await targetFile.delete();
      }
    }

    // Download APK directly
    await _dio.download(
      info.downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        onProgress(received, total > 0 ? total : (info.apkSize ?? 0));
      },
    );

    // Trigger installation
    await _installApk(savePath);
  }

  Future<void> _installApk(String filePath) async {
    try {
      await _channel.invokeMethod('installApk', {'filePath': filePath});
    } catch (e) {
      debugPrint('[AppUpdateService] Error triggering native APK installer: $e');
      rethrow;
    }
  }
}
