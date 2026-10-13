import 'dart:collection';

import 'package:wqhub/settings/appearance/imported_color_theme.dart';

class ImportedColorThemes {
  final SplayTreeMap<String, ImportedColorTheme> themes;

  const ImportedColorThemes({required this.themes});

  ImportedColorThemes.empty() : themes = SplayTreeMap<String, ImportedColorTheme>();

  Map<String, dynamic> toJson() =>
      themes.map((key, theme) => MapEntry(key, theme.toJson()));

  ImportedColorThemes.fromJson(Map<String, dynamic> json)
      : themes = SplayTreeMap.from(json.map((key, value) => MapEntry(
            key,
            ImportedColorTheme.fromJson(key, value as Map<String, dynamic>))));
}
