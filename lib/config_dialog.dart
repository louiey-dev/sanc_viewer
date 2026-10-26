import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'map_service.dart';

class ConfigDialog extends ConsumerStatefulWidget {
  const ConfigDialog({super.key, this.onAssociateFiles});

  final VoidCallback? onAssociateFiles;

  @override
  ConsumerState<ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends ConsumerState<ConfigDialog> {
  final _availability = <MapService, bool>{};
  late MapService _selected;
  late ThemeMode _themeMode;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(appSettingsProvider).mapService;
    _themeMode = ref.read(themeModeProvider);
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _availability.clear();
    });
    final launcher = ref.read(mapLauncherProvider);
    await Future.wait(
      MapService.values.map((service) async {
        final available = await launcher.isAvailable(service);
        if (mounted) setState(() => _availability[service] = available);
      }),
    );
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Config'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Appearance'),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light mode'),
                ),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark mode')),
              ],
              selected: {_themeMode},
              onSelectionChanged: (selection) =>
                  setState(() => _themeMode = selection.single),
            ),
            if (widget.onAssociateFiles != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('File associations'),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onAssociateFiles!();
                },
              ),
            ],
            const Divider(height: 24),
            const Text('Map for photo locations'),
            const SizedBox(height: 8),
            const Text(
              'Maps open in your default browser. Availability checks '
              'whether this computer can open the link; internet access and '
              'map coverage are not checked.',
            ),
            const SizedBox(height: 12),
            for (final service in MapService.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _selected == service
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(service.label),
                subtitle: Text(switch (_availability[service]) {
                  true => 'Available in browser',
                  false => 'Unavailable: no browser handler or check failed',
                  null => 'Checking...',
                }),
                enabled: _availability[service] == true,
                onTap: () => setState(() => _selected = service),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _checking ? null : _check,
        child: const Text('Recheck'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _selected != ref.read(appSettingsProvider).mapService &&
                _availability[_selected] != true
            ? null
            : () {
                ref.read(appSettingsProvider).update(mapService: _selected);
                ref.read(themeModeProvider.notifier).setMode(_themeMode);
                Navigator.pop(context, true);
              },
        child: const Text('Save'),
      ),
    ],
  );
}
