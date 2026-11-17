import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xclient/common/common.dart';
import 'package:xclient/ui/ui.dart';
import 'package:xclient/widgets/widgets.dart';

/// Простой и красивый экран настройки ядра XRay.
///
/// Разделы: порт прослушивания, уровень логирования, DNS-серверы, правила маршрутизации, аутбаунды.
/// Изменения применяются к конфигу XRay при нажатии Save.
class XRayConfigView extends ConsumerStatefulWidget {
  const XRayConfigView({super.key});

  @override
  ConsumerState<XRayConfigView> createState() => _XRayConfigViewState();
}

class _XRayConfigViewState extends ConsumerState<XRayConfigView> {
  late final m.TextEditingController _portController =
      m.TextEditingController(text: '10808');
  late final m.TextEditingController _dnsController =
      m.TextEditingController();
  late final m.TextEditingController _routingController =
      m.TextEditingController();
  String _logLevel = 'warning';
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  @override
  void dispose() {
    _portController.dispose();
    _dnsController.dispose();
    _routingController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentConfig() async {
    final path = await appPath.homeDirPath;
    final configFile = File('${path}xray/config.json');
    if (await configFile.exists()) {
      final json = await configFile.readAsString();
      try {
        final Map<String, dynamic> decoded = jsonDecode(json);
        final inbounds = decoded['inbounds'] as List?;
        if (inbounds != null && inbounds.isNotEmpty) {
          final port = inbounds.first['port'];
          if (port != null) {
            _portController.text = port.toString();
          }
        }
        final log = decoded['log'];
        if (log is Map) {
          _logLevel = log['loglevel']?.toString() ?? 'warning';
        }
        final dns = decoded['dns'];
        if (dns is Map) {
          final servers = dns['servers'];
          if (servers is List) {
            _dnsController.text = servers.join('\n');
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _hasChanges = false);
    }
  }

  Future<void> _saveConfig() async {
    final port = int.tryParse(_portController.text.trim()) ?? 10808;
    final dnsServers = _dnsController.text
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final config = <String, dynamic>{
      'log': {'loglevel': _logLevel},
      'inbounds': [
        {
          'port': port,
          'protocol': 'socks',
          'settings': {'udp': true},
        },
      ],
      'dns': {
        'servers': dnsServers.isNotEmpty ? dnsServers : ['localhost'],
      },
      'outbounds': [
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'blocked'},
      ],
      'routing': {
        'rules': [
          {
            'type': 'field',
            'ip': ['geoip:private'],
            'outboundTag': 'direct',
          },
        ],
      },
    };

    final homeDir = await appPath.homeDirPath;
    final xrayDir = Directory('${homeDir}xray');
    if (!await xrayDir.exists()) {
      await xrayDir.create(recursive: true);
    }
    final configFile = File('${xrayDir.path}/config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
      flush: true,
    );

    if (mounted) {
      setState(() => _hasChanges = false);
    }

    if (!mounted) return;
    await dialogs.showMessage(
      title: context.appLocalizations.xraySave,
      message: TextSpan(
        text: context.appLocalizations.xrayApplyDesc,
      ),
      confirmText: context.appLocalizations.confirm,
    );
  }

  void _resetConfig() {
    _portController.text = '10808';
    _dnsController.clear();
    _routingController.clear();
    _logLevel = 'warning';
    setState(() => _hasChanges = false);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;

    return Scaffold(
      title: appLocalizations.xrayConfig,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 32 + context.bottomInset,
        ),
        children: [
          _SectionCard(
            title: appLocalizations.xrayConfig,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConfigTextField(
                  label: appLocalizations.xrayListenPort,
                  hint: '10808',
                  controller: _portController,
                  keyboardType: m.TextInputType.number,
                  onChanged: (_) => setState(() => _hasChanges = true),
                ),
                const SizedBox(height: 16),
                _ConfigDropdown<String>(
                  label: appLocalizations.xrayLogLevel,
                  value: _logLevel,
                  items: const ['debug', 'info', 'warning', 'error', 'none'],
                  onChanged: (value) {
                    setState(() {
                      _logLevel = value!;
                      _hasChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _ConfigTextField(
                  label: appLocalizations.xrayDnsServers,
                  hint: '8.8.8.8\n1.1.1.1',
                  controller: _dnsController,
                  keyboardType: m.TextInputType.text,
                  maxLines: 3,
                  onChanged: (_) => setState(() => _hasChanges = true),
                ),
                const SizedBox(height: 16),
                _ConfigTextField(
                  label: appLocalizations.xrayRoutingRules,
                  hint: 'DOMAIN,google.com,direct\nGEOIP,CN,direct',
                  controller: _routingController,
                  keyboardType: m.TextInputType.text,
                  maxLines: 3,
                  onChanged: (_) => setState(() => _hasChanges = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: m.OutlinedButton(
                  onPressed: _resetConfig,
                  child: Text(appLocalizations.xrayReset),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: m.FilledButton(
                  onPressed: _hasChanges ? _saveConfig : null,
                  child: Text(appLocalizations.xraySave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Карточка с заголовком и разделителем.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: AppTextStyle.title3.of(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

/// Поле ввода текста с меткой.
class _ConfigTextField extends StatelessWidget {
  const _ConfigTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines,
    this.onChanged,
  });

  final String label;
  final String? hint;
  final m.TextEditingController controller;
  final m.TextInputType? keyboardType;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyle.body.of(context).copyWith(
              fontWeight: FontWeight.w500,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          m.TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines ?? 1,
            onChanged: onChanged,
            decoration: m.InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyle.body.of(context).copyWith(
                color: context.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: m.OutlineInputBorder(
                borderRadius: AppRadius.sm,
                borderSide: m.BorderSide(
                  color: context.colorScheme.outlineVariant,
                ),
              ),
              enabledBorder: m.OutlineInputBorder(
                borderRadius: AppRadius.sm,
                borderSide: m.BorderSide(
                  color: context.colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: m.OutlineInputBorder(
                borderRadius: AppRadius.sm,
                borderSide: m.BorderSide(
                  color: context.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Выпадающее поле выбора с меткой.
class _ConfigDropdown<T> extends StatelessWidget {
  const _ConfigDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyle.body.of(context).copyWith(
              fontWeight: FontWeight.w500,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.sm,
              color: context.colorScheme.surfaceContainerHighest,
            ),
            child: m.DropdownButtonFormField<T>(
              initialValue: value,
              items: items
                  .map(
                    (item) => m.DropdownMenuItem<T>(
                      value: item,
                      child: Text(item.toString()),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
              decoration: const m.InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: m.InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
