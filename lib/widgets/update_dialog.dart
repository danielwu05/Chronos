import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_version.dart';
import '../services/update_service.dart';

/// Checks GitHub Releases and, when a newer signed version exists, asks the user to update.
/// "Depois" stores nothing, so the question comes back on the next app start.
Future<void> checkAndPromptForUpdate(BuildContext context, {bool manual = false}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!manual && !isReleaseBuild) return;
  if (manual && !isReleaseBuild) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Atualização automática só funciona na versão instalada (não em builds de desenvolvimento).'),
    ));
    return;
  }

  final service = UpdateService();
  final info = await service.checkForUpdate();
  if (!context.mounted) return;
  if (info == null) {
    if (manual) {
      messenger?.showSnackBar(SnackBar(content: Text('O Chronos já está na versão mais recente ($appVersion).')));
    }
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(info: info, service: service),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  const UpdateDialog({super.key, required this.info, required this.service});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _running = false;
  UpdateStage? _stage;
  double? _fraction;
  String? _error;
  String? _warning;

  String _stageLabel(UpdateStage s) => switch (s) {
        UpdateStage.downloading => 'Baixando…',
        UpdateStage.verifying => 'Verificando assinatura…',
        UpdateStage.installing => 'Instalando…',
        UpdateStage.guard => 'Atualizando a proteção do sistema (pode pedir sua senha)…',
        UpdateStage.restarting => 'Reiniciando o Chronos…',
      };

  Future<void> _update() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final exe = await widget.service.downloadAndInstall(widget.info, (stage, fraction) {
        if (mounted) {
          setState(() {
            _stage = stage;
            _fraction = fraction;
          });
        }
      });
      if (await widget.service.guardNeedsUpdate(widget.info)) {
        setState(() {
          _stage = UpdateStage.guard;
          _fraction = null;
        });
        final ok = await widget.service.updateGuardFrom(widget.info);
        if (!ok && mounted) {
          setState(() => _warning =
              'A proteção do sistema (Guard) não foi atualizada agora. Você pode atualizá-la depois em Configurações.');
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      if (mounted) setState(() => _stage = UpdateStage.restarting);
      await UpdateService.relaunch(exe);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e is StateError ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('Nova versão do Chronos: ${info.version}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Você está na versão $appVersion. Deseja atualizar agora?'),
            if (info.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(info.notes.trim(), style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              ),
            ],
            if (_running && _stage != null) ...[
              const SizedBox(height: 16),
              Text(_stageLabel(_stage!)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _fraction),
            ],
            if (_warning != null) ...[
              const SizedBox(height: 12),
              Text(_warning!, style: const TextStyle(color: Colors.amberAccent)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('Falha na atualização: $_error', style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('Depois'),
        ),
        FilledButton(
          onPressed: _running ? null : _update,
          child: Text(_error != null ? 'Tentar novamente' : 'Atualizar agora'),
        ),
      ],
    );
  }
}

/// Exposed for tests/diagnostics.
bool get updaterSupportedOnThisPlatform => Platform.isLinux;
