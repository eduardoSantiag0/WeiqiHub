import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wqhub/board/board_settings.dart';
import 'package:wqhub/board/board_theme.dart';
import 'package:wqhub/color_picker_dialog.dart';
import 'package:wqhub/confirm_dialog.dart';
import 'package:wqhub/l10n/app_localizations.dart';
import 'package:wqhub/settings/appearance/color_role.dart';
import 'package:wqhub/settings/appearance/demo_color_themes.dart';
import 'package:wqhub/settings/appearance/imported_color_theme.dart';
import 'package:wqhub/settings/appearance/obsidian_theme_parser.dart';
import 'package:wqhub/settings/settings.dart';
import 'package:wqhub/settings/shared_preferences_inherited_widget.dart';
import 'package:wqhub/text_input_dialog.dart';

extension on PlayerRankVisibility {
  String toLocalizedString(AppLocalizations loc) => switch (this) {
        PlayerRankVisibility.visible => loc.rankVisibilityVisible,
        PlayerRankVisibility.hideRank => loc.rankVisibilityHideRank,
        PlayerRankVisibility.focusMode => loc.rankVisibilityFocusMode,
      };
}

extension on ThemeMode {
  String toLocalizedString(AppLocalizations loc) => switch (this) {
        ThemeMode.system => loc.system,
        ThemeMode.light => loc.light,
        ThemeMode.dark => loc.dark,
      };
}

extension on ColorRole {
  String toLocalizedString(AppLocalizations loc) => switch (this) {
        ColorRole.primary => loc.colorRolePrimary,
        ColorRole.onPrimary => loc.colorRoleOnPrimary,
        ColorRole.surface => loc.colorRoleSurface,
        ColorRole.surfaceContainerHigh => loc.colorRoleSurfaceContainerHigh,
        ColorRole.onSurface => loc.colorRoleOnSurface,
        ColorRole.onSurfaceVariant => loc.colorRoleOnSurfaceVariant,
        ColorRole.outline => loc.colorRoleOutline,
        ColorRole.error => loc.colorRoleError,
      };
}

class AppearanceSettingsList extends StatelessWidget {
  final Function() onChanged;
  final Function() onAppThemeChanged;

  const AppearanceSettingsList(
      {super.key, required this.onChanged, required this.onAppThemeChanged});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListView(
      children: [
        ListTile(
          title: Text(loc.theme),
          trailing: DropdownButton<ThemeMode>(
            value: context.settings.themeMode,
            items: ThemeMode.values.map((mode) {
              return DropdownMenuItem<ThemeMode>(
                value: mode,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(mode.toLocalizedString(loc)),
                ),
              );
            }).toList(),
            borderRadius: BorderRadius.circular(8),
            onChanged: (ThemeMode? mode) {
              context.settings.themeMode = mode!;
              onAppThemeChanged();
            },
          ),
        ),
        _colorThemeDropdown(
          context,
          label: loc.appLightColorTheme,
          value: context.settings.appLightColorThemeName,
          onSelect: (name) {
            context.settings.appLightColorThemeName = name;
            onAppThemeChanged();
          },
        ),
        _colorThemeDropdown(
          context,
          label: loc.appDarkColorTheme,
          value: context.settings.appDarkColorThemeName,
          onSelect: (name) {
            context.settings.appDarkColorThemeName = name;
            onAppThemeChanged();
          },
        ),
        ListTile(
          title: Text(loc.colorOverrides),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.light, style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final role in ColorRole.values)
                    _colorRoleChip(context, role,
                        isLight: true,
                        onChanged: onChanged,
                        onAppThemeChanged: onAppThemeChanged),
                ],
              ),
              const SizedBox(height: 8),
              Text(loc.dark, style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final role in ColorRole.values)
                    _colorRoleChip(context, role,
                        isLight: false,
                        onChanged: onChanged,
                        onAppThemeChanged: onAppThemeChanged),
                ],
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(loc.demoColorThemes),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final demo in demoColorThemes)
                ActionChip(
                  label: Text(demo.name),
                  onPressed: () => _applyDemoColorTheme(
                      context, demo, onChanged, onAppThemeChanged),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.file_open),
          title: Text(loc.importAppColorTheme),
          onTap: () => _importObsidianTheme(context, onChanged, onAppThemeChanged),
        ),
        for (final name in context.settings.importedColorThemes.themes.keys)
          ListTile(
            title: Text(name),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => ConfirmDialog(
                    title: loc.confirm,
                    content: loc.msgConfirmDeleteAppColorTheme,
                    onYes: () => Navigator.pop(context, true),
                    onNo: () => Navigator.pop(context, false),
                  ),
                );
                if (confirmed ?? false) {
                  context.settings.removeImportedColorTheme(name);
                  onChanged();
                  onAppThemeChanged();
                }
              },
            ),
            onTap: () {
              context.settings.appLightColorThemeName = name;
              context.settings.appDarkColorThemeName = name;
              onAppThemeChanged();
            },
          ),
        ListTile(
          title: Text(loc.boardTheme),
          trailing: DropdownButton<BoardTheme>(
            value: context.settings.boardTheme,
            borderRadius: BorderRadius.circular(8),
            items: BoardTheme.themes.values.map((theme) {
              return DropdownMenuItem<BoardTheme>(
                value: theme,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(theme.displayName),
                ),
              );
            }).toList(),
            onChanged: (BoardTheme? theme) {
              context.settings.boardTheme = theme!;
              onChanged();
            },
          ),
        ),
        ListTile(
          title: Text(loc.showCoordinates),
          trailing: Switch(
            value: context.settings.showCoordinates,
            onChanged: (value) {
              context.settings.showCoordinates = value;
              onChanged();
            },
          ),
        ),
        ListTile(
          title: Text(loc.stoneShadows),
          trailing: Switch(
            value: context.settings.stoneShadows,
            onChanged: (value) {
              context.settings.stoneShadows = value;
              onChanged();
            },
          ),
        ),
        ListTile(
          title: Text(loc.edgeLine),
          trailing: SegmentedButton<BoardEdgeLine>(
            selected: <BoardEdgeLine>{context.settings.edgeLine},
            segments: [
              ButtonSegment<BoardEdgeLine>(
                value: BoardEdgeLine.single,
                label: Text(loc.simple),
              ),
              ButtonSegment<BoardEdgeLine>(
                value: BoardEdgeLine.thick,
                label: Text(loc.thick),
              ),
            ],
            onSelectionChanged: (value) {
              context.settings.edgeLine = value.first;
              onChanged();
            },
          ),
        ),
        ListTile(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.rankVisibility),
              DropdownButton<PlayerRankVisibility>(
                value: context.settings.rankVisibility,
                isExpanded: true,
                items: PlayerRankVisibility.values.map((mode) {
                  return DropdownMenuItem<PlayerRankVisibility>(
                    value: mode,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(mode.toLocalizedString(loc)),
                    ),
                  );
                }).toList(),
                borderRadius: BorderRadius.circular(8),
                onChanged: (PlayerRankVisibility? mode) {
                  context.settings.rankVisibility = mode!;
                  onChanged();
                },
              ),
            ],
          ),
        ),
        if (Platform.isAndroid || Platform.isIOS)
          ListTile(
            title: Text(loc.fullscreen),
            subtitle: Text(loc.fullscreenDesc),
            trailing: Switch(
              value: context.settings.fullscreen,
              onChanged: (value) {
                context.settings.fullscreen = value;
                onChanged();
              },
            ),
          ),
      ],
    );
  }
}

Widget _colorRoleChip(
  BuildContext context,
  ColorRole role, {
  required bool isLight,
  required Function() onChanged,
  required Function() onAppThemeChanged,
}) {
  final loc = AppLocalizations.of(context)!;
  final overrides = isLight
      ? context.settings.lightColorOverrides
      : context.settings.darkColorOverrides;
  final current = overrides.colorFor(role);
  return ActionChip(
    avatar: CircleAvatar(
      backgroundColor:
          current ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      child: current == null ? const Icon(Icons.remove, size: 12) : null,
    ),
    label: Text(role.toLocalizedString(loc)),
    onPressed: () async {
      final result = await showDialog<(ColorPickerAction, Color?)>(
        context: context,
        builder: (context) => ColorPickerDialog(
          title: role.toLocalizedString(loc),
          initialColor: current,
        ),
      );
      if (result == null) return;
      final (action, color) = result;
      final newColor = action == ColorPickerAction.clear ? null : color;
      if (isLight) {
        context.settings.setLightColorOverride(role, newColor);
      } else {
        context.settings.setDarkColorOverride(role, newColor);
      }
      onChanged();
      onAppThemeChanged();
    },
  );
}

Widget _colorThemeDropdown(
  BuildContext context, {
  required String label,
  required String? value,
  required void Function(String?) onSelect,
}) {
  final loc = AppLocalizations.of(context)!;
  return ListTile(
    title: Text(label),
    trailing: DropdownButton<String?>(
      value: value,
      borderRadius: BorderRadius.circular(8),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(loc.appColorThemeDefault),
          ),
        ),
        for (final name in context.settings.importedColorThemes.themes.keys)
          DropdownMenuItem<String?>(
            value: name,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(name),
            ),
          ),
      ],
      onChanged: onSelect,
    ),
  );
}

Future<void> _applyDemoColorTheme(BuildContext context, DemoColorTheme demo,
    Function() onChanged, Function() onAppThemeChanged) async {
  final loc = AppLocalizations.of(context)!;
  if (!context.settings.importedColorThemes.themes.containsKey(demo.name)) {
    final css = await rootBundle.loadString(demo.assetPath);
    try {
      final parsed = parseObsidianThemeCss(css, name: demo.name);
      if (!context.mounted) return;
      context.settings.putImportedColorTheme(parsed);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.msgObsidianThemeImportFailed(e.message)),
            showCloseIcon: true,
          ),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  context.settings.appLightColorThemeName = demo.name;
  context.settings.appDarkColorThemeName = demo.name;
  onChanged();
  onAppThemeChanged();
}

Future<void> _importObsidianTheme(
    BuildContext context, Function() onChanged, Function() onAppThemeChanged) async {
  final loc = AppLocalizations.of(context)!;
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['css'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.single;
  final bytes =
      file.bytes ?? (file.path != null ? File(file.path!).readAsBytesSync() : null);
  if (bytes == null) return;
  final css = utf8.decode(bytes, allowMalformed: true);
  final suggestedName = file.name.replaceAll(RegExp(r'\.css$', caseSensitive: false), '');

  if (!context.mounted) return;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => TextInputDialog(
      title: loc.importAppColorTheme,
      content: loc.appColorThemeName,
      initialValue: suggestedName,
      maxLength: 40,
    ),
  );
  if (name == null || name.isEmpty) return;

  final ImportedColorTheme parsed;
  try {
    parsed = parseObsidianThemeCss(css, name: name);
  } on FormatException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.msgObsidianThemeImportFailed(e.message)),
          showCloseIcon: true,
        ),
      );
    }
    return;
  }

  if (context.settings.importedColorThemes.themes.containsKey(name)) {
    if (!context.mounted) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmDialog(
        title: loc.confirm,
        content: loc.msgConfirmReplaceAppColorTheme(name),
        onYes: () => Navigator.pop(context, true),
        onNo: () => Navigator.pop(context, false),
      ),
    );
    if (!(replace ?? false)) return;
  }

  if (!context.mounted) return;
  context.settings.putImportedColorTheme(parsed);
  onChanged();
}
