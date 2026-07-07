import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_update.dart';
import '../app/settings_about.dart';
import '../ui/ui.dart';
import 'desktop_window_controller.dart';
import 'local_auto_update_prompt_store.dart';
import 'release_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    required this.releaseBucketUrl,
    required this.windowController,
    this.currentVersion = gangChatClientVersion,
    this.autoUpdatePromptStore = const LocalAutoUpdatePromptStore(),
    this.updateService,
    this.platformOverride,
  });

  final Widget child;
  final String currentVersion;
  final String releaseBucketUrl;
  final AutoUpdatePromptStore autoUpdatePromptStore;
  final ReleaseUpdateService? updateService;
  final AppUpdatePlatform? platformOverride;
  final DesktopWindowController windowController;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  AvailableAppUpdate? _update;
  bool _dismissed = false;
  bool _checking = false;
  bool _downloading = false;
  int _downloadedBytes = 0;
  int? _downloadTotalBytes;
  String? _error;

  ReleaseUpdateService get _updateService =>
      widget.updateService ?? ReleaseUpdateService();

  @override
  void initState() {
    super.initState();
    unawaited(_checkForUpdate());
  }

  @override
  void didUpdateWidget(AppUpdateGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releaseBucketUrl != widget.releaseBucketUrl ||
        oldWidget.currentVersion != widget.currentVersion ||
        oldWidget.updateService != widget.updateService) {
      _update = null;
      _dismissed = false;
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _checkForUpdate({bool forced = false}) async {
    if (_checking) return;
    final platform = _currentPlatform();
    if (platform == null) return;

    if (!forced) {
      try {
        final enabled = await widget.autoUpdatePromptStore.read();
        if (!enabled) return;
      } catch (_) {
        return;
      }
    }

    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final update = await _updateService.checkForUpdate(
        bucketUrl: widget.releaseBucketUrl,
        currentVersion: widget.currentVersion,
        platform: platform,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _update = update;
        _dismissed = update == null;
        _downloadedBytes = 0;
        _downloadTotalBytes = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        if (forced || _update != null) {
          _error = '检查更新失败：$error';
        }
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final update = _update;
    if (update == null || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _downloadedBytes = 0;
      _downloadTotalBytes = null;
    });
    try {
      final file = await _updateService.downloadUpdate(
        update,
        onProgress: ({required receivedBytes, totalBytes}) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = receivedBytes;
            _downloadTotalBytes = totalBytes;
          });
        },
      );
      if (!mounted) return;
      await _updateService.startInstaller(file);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await widget.windowController.terminateApplication();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载或启动安装器失败：$error';
      });
    }
  }

  void _dismissUpdate() {
    if (_downloading) return;
    setState(() => _dismissed = true);
  }

  AppUpdatePlatform? _currentPlatform() {
    final override = widget.platformOverride;
    if (override != null) return override;
    if (Platform.isWindows) return AppUpdatePlatform.windows;
    if (Platform.isMacOS) return AppUpdatePlatform.macos;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    if (update == null || _dismissed) return widget.child;

    return _AppUpdatePage(
      update: update,
      checking: _checking,
      downloading: _downloading,
      downloadedBytes: _downloadedBytes,
      downloadTotalBytes: _downloadTotalBytes,
      error: _error,
      onDownload: () => unawaited(_downloadAndInstall()),
      onRetry: () => unawaited(_checkForUpdate(forced: true)),
      onContinue: _dismissUpdate,
    );
  }
}

class _AppUpdatePage extends StatelessWidget {
  const _AppUpdatePage({
    required this.update,
    required this.checking,
    required this.downloading,
    required this.downloadedBytes,
    required this.onDownload,
    required this.onRetry,
    required this.onContinue,
    this.downloadTotalBytes,
    this.error,
  });

  final AvailableAppUpdate update;
  final bool checking;
  final bool downloading;
  final int downloadedBytes;
  final int? downloadTotalBytes;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  double? get _downloadProgress {
    final total = downloadTotalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.surfaceLow,
      body: SettingsScaffold(
        icon: Icons.system_update_alt_outlined,
        title: '发现新版本',
        onBack: downloading ? null : onContinue,
        headerAction: ButtonIcon(
          tooltip: '重新检查',
          icon: const Icon(Icons.refresh),
          loading: checking,
          onPressed: checking || downloading ? null : onRetry,
          size: 38,
        ),
        body: SettingsList(
          children: [
            SettingsCard(
              title: '版本更新',
              trailing: _UpdateBadge(version: update.latestVersion),
              children: [
                _VersionLine(
                  label: '当前版本',
                  value: appVersionLabel(update.currentVersion),
                ),
                _VersionLine(
                  label: '最新版本',
                  value: appVersionLabel(update.latestVersion),
                  accent: true,
                ),
                _VersionLine(
                  label: '发行时间',
                  value: releaseTimeLabel(update.asset.releasedAt),
                ),
                if (downloading) ...[
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(UiRadii.sm),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 8,
                      color: UiColors.controlAccent,
                      backgroundColor: UiColors.surfacePressed,
                    ),
                  ),
                  Text(
                    _downloadProgress == null
                        ? '正在下载更新'
                        : '正在下载更新 ${(_downloadProgress! * 100).round()}%',
                    style: UiTypography.label,
                  ),
                ],
              ],
            ),
            if (error != null)
              SettingsCard(
                title: '更新失败',
                danger: true,
                children: [
                  Text(
                    error!,
                    style: UiTypography.label.copyWith(
                      color: UiColors.danger,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            _UpdateActions(
              downloading: downloading,
              onDownload: onDownload,
              onContinue: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 86, child: Text(label, style: UiTypography.label)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? UiColors.accent : UiColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.selected,
        borderRadius: BorderRadius.circular(UiRadii.sm),
        border: Border.all(color: UiColors.selectedBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          appVersionLabel(version),
          style: UiTypography.label.copyWith(
            color: UiColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _UpdateActions extends StatelessWidget {
  const _UpdateActions({
    required this.downloading,
    required this.onDownload,
    required this.onContinue,
  });

  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          Button(
            onPressed: downloading ? null : onContinue,
            icon: const Icon(Icons.schedule_outlined),
            child: const Text('稍后提醒'),
          ),
          Button(
            onPressed: downloading ? null : onContinue,
            icon: const Icon(Icons.login_outlined),
            child: const Text('继续使用'),
          ),
          Button(
            onPressed: downloading ? null : onDownload,
            loading: downloading,
            icon: const Icon(Icons.download_outlined),
            tone: ButtonTone.primary,
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }
}
