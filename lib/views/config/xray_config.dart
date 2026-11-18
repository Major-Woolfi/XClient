import 'dart:convert';
import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/features/form/form.dart';
import 'package:xclient/ui/ui.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class XRayConfigView extends ConsumerStatefulWidget {
  const XRayConfigView({super.key});

  @override
  ConsumerState<XRayConfigView> createState() => _XRayConfigViewState();
}

class _XRayConfigViewState extends ConsumerState<XRayConfigView> {
  static const _defaultPort = 10808;
  static const _logLevels = ['debug', 'info', 'warning', 'error', 'none'];

  final _portController = TextEditingController();
  final _dnsController = TextEditingController();
  final _routingController = TextEditingController();
  Map<String, dynamic> _config = {};
  String _logLevel = 'warning';
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _portController.dispose();
    _dnsController.dispose();
    _routingController.dispose();
    super.dispose();
  }

  Future<File> _configFile() async {
    return File(p.join(await appPath.homeDirPath, 'xray', 'config.json'));
  }

  Future<void> _loadConfig() async {
    final file = await _configFile();
    var config = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          config = decoded;
        }
      } catch (_) {}
    }

    final inbounds = config['inbounds'];
    final inbound = inbounds is List && inbounds.isNotEmpty
        ? inbounds.first
        : null;
    final log = config['log'];
    final dns = config['dns'];
    final routing = config['routing'];
    final rules = routing is Map ? routing['rules'] : null;

    if (!mounted) {
      return;
    }
    setState(() {
      _config = config;
      _portController.text =
          (inbound is Map ? inbound['port'] : null)?.toString() ??
          _defaultPort.toString();
      _logLevel = log is Map
          ? log['loglevel']?.toString() ?? 'warning'
          : 'warning';
      final servers = dns is Map ? dns['servers'] : null;
      _dnsController.text = servers is List ? servers.join('\n') : '';
      _routingController.text = rules is List
          ? const JsonEncoder.withIndent('  ').convert(rules)
          : '[]';
      _hasChanges = false;
    });
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  void _resetConfig() {
    setState(() {
      _portController.text = _defaultPort.toString();
      _logLevel = 'warning';
      _dnsController.clear();
      _routingController.text = '[]';
      _hasChanges = false;
    });
  }

  List<dynamic>? _parseRoutingRules() {
    try {
      final decoded = jsonDecode(_routingController.text);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveConfig() async {
    final appLocalizations = context.appLocalizations;
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      await dialogs.showAlert(
        message: TextSpan(
          text: appLocalizations.portTip(appLocalizations.xrayListenPort),
        ),
      );
      return;
    }

    final rules = _parseRoutingRules();
    if (rules == null) {
      await dialogs.showAlert(
        message: TextSpan(text: appLocalizations.ruleListInvalid),
      );
      return;
    }

    final config = Map<String, dynamic>.from(_config);
    final existingLog = config['log'];
    config['log'] = {
      if (existingLog is Map) ...existingLog,
      'loglevel': _logLevel,
    };

    final inbounds = config['inbounds'];
    final inbound = inbounds is List && inbounds.isNotEmpty
        ? inbounds.first
        : null;
    config['inbounds'] = [
      {
        if (inbound is Map) ...inbound,
        'port': port,
        if (inbound is! Map) 'protocol': 'socks',
        if (inbound is! Map) 'listen': '127.0.0.1',
        if (inbound is! Map) 'settings': <String, dynamic>{},
      },
      if (inbounds is List) ...inbounds.skip(1),
    ];

    final dnsServers = _dnsController.text
        .split('\n')
        .map((server) => server.trim())
        .where((server) => server.isNotEmpty)
        .toList();
    final existingDns = config['dns'];
    config['dns'] = {
      if (existingDns is Map) ...existingDns,
      'servers': dnsServers.isEmpty ? ['localhost'] : dnsServers,
    };

    final existingRouting = config['routing'];
    config['routing'] = {
      if (existingRouting is Map) ...existingRouting,
      'rules': rules,
    };

    if (config['outbounds'] is! List) {
      config['outbounds'] = [
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'blocked'},
      ];
    }

    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
      flush: true,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _config = config;
      _hasChanges = false;
    });
    await dialogs.showMessage(
      title: appLocalizations.xraySave,
      message: TextSpan(text: appLocalizations.xrayApplyDesc),
      confirmText: appLocalizations.confirm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;

    return BaseScaffold(
      title: appLocalizations.xrayConfig,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: appLocalizations.xrayConfig,
            items: [
              FormRow(
                title: appLocalizations.xrayListenPort,
                trailing: FormRowTextField(
                  controller: _portController,
                  hintText: _defaultPort.toString(),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: TextInputLimits.digitsOnly(
                    TextInputLimits.port,
                  ),
                  onChanged: (_) => _markChanged(),
                ),
              ),
              ListItem<String>.options(
                title: Text(appLocalizations.xrayLogLevel),
                options: _logLevels,
                value: _logLevel,
                textBuilder: (level) => level,
                onChanged: (level) {
                  setState(() {
                    _logLevel = level;
                    _hasChanges = true;
                  });
                },
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.xrayDnsServers,
            items: [
              _ConfigTextArea(
                controller: _dnsController,
                hint: '8.8.8.8\n1.1.1.1',
                onChanged: (_) => _markChanged(),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.xrayRoutingRules,
            items: [
              _ConfigTextArea(
                controller: _routingController,
                hint:
                    '[\n  {"type": "field", "ip": ["geoip:private"], '
                    '"outboundTag": "direct"}\n]',
                onChanged: (_) => _markChanged(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _hasChanges ? _resetConfig : null,
                  child: Text(appLocalizations.xrayReset),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
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

class _ConfigTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _ConfigTextArea({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: FilledInputTheme(
        borderRadius: AppRadius.md,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: TextField(
          controller: controller,
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
