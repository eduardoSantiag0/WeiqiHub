import 'package:flutter/material.dart';
import 'package:wqhub/settings/appearance/imported_color_role_set.dart';

@immutable
class ImportedColorTheme {
  final String name;
  final ImportedColorRoleSet light;
  final ImportedColorRoleSet dark;

  const ImportedColorTheme({
    required this.name,
    required this.light,
    required this.dark,
  });

  Map<String, dynamic> toJson() => {
        'light': light.toJson(),
        'dark': dark.toJson(),
      };

  factory ImportedColorTheme.fromJson(String name, Map<String, dynamic> json) =>
      ImportedColorTheme(
        name: name,
        light: ImportedColorRoleSet.fromJson(
            json['light'] as Map<String, dynamic>? ?? const {}),
        dark: ImportedColorRoleSet.fromJson(
            json['dark'] as Map<String, dynamic>? ?? const {}),
      );
}
