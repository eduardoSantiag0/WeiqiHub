import 'package:flutter/foundation.dart';

/// Obsidian community themes bundled with the app as one-tap demos, so
/// users can try the import feature without hunting down a `theme.css`
/// themselves. All are MIT-licensed; see assets/themes/*.LICENSE.
@immutable
class DemoColorTheme {
  final String name;
  final String assetPath;

  const DemoColorTheme({required this.name, required this.assetPath});
}

const demoColorThemes = <DemoColorTheme>[
  DemoColorTheme(name: 'Solarized', assetPath: 'assets/themes/solarized.css'),
  DemoColorTheme(name: 'Wasp', assetPath: 'assets/themes/wasp.css'),
  DemoColorTheme(name: 'Reverie', assetPath: 'assets/themes/reverie.css'),
  DemoColorTheme(name: 'Catppuccin', assetPath: 'assets/themes/catppuccin.css'),
  DemoColorTheme(
      name: 'Everforest Enchanted', assetPath: 'assets/themes/everforest.css'),
];
