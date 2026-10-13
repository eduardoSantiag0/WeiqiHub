import 'package:flutter/material.dart';
import 'package:wqhub/settings/appearance/color_role.dart';

@immutable
class ImportedColorRoleSet {
  final Color? primary;
  final Color? onPrimary;
  final Color? surface;
  final Color? surfaceContainerHigh;
  final Color? onSurface;
  final Color? onSurfaceVariant;
  final Color? outline;
  final Color? error;

  const ImportedColorRoleSet({
    this.primary,
    this.onPrimary,
    this.surface,
    this.surfaceContainerHigh,
    this.onSurface,
    this.onSurfaceVariant,
    this.outline,
    this.error,
  });

  Color? colorFor(ColorRole role) => switch (role) {
        ColorRole.primary => primary,
        ColorRole.onPrimary => onPrimary,
        ColorRole.surface => surface,
        ColorRole.surfaceContainerHigh => surfaceContainerHigh,
        ColorRole.onSurface => onSurface,
        ColorRole.onSurfaceVariant => onSurfaceVariant,
        ColorRole.outline => outline,
        ColorRole.error => error,
      };

  ImportedColorRoleSet withColor(ColorRole role, Color? color) => switch (role) {
        ColorRole.primary => ImportedColorRoleSet(
            primary: color,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: error,
          ),
        ColorRole.onPrimary => ImportedColorRoleSet(
            primary: primary,
            onPrimary: color,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: error,
          ),
        ColorRole.surface => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: color,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: error,
          ),
        ColorRole.surfaceContainerHigh => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: color,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: error,
          ),
        ColorRole.onSurface => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: color,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: error,
          ),
        ColorRole.onSurfaceVariant => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: color,
            outline: outline,
            error: error,
          ),
        ColorRole.outline => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: color,
            error: error,
          ),
        ColorRole.error => ImportedColorRoleSet(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            surfaceContainerHigh: surfaceContainerHigh,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            error: color,
          ),
      };

  /// Returns a role set where each field [overrides] has set takes priority
  /// over this one's, i.e. `base.overlay(overrides)`.
  ImportedColorRoleSet overlay(ImportedColorRoleSet overrides) =>
      ImportedColorRoleSet(
        primary: overrides.primary ?? primary,
        onPrimary: overrides.onPrimary ?? onPrimary,
        surface: overrides.surface ?? surface,
        surfaceContainerHigh:
            overrides.surfaceContainerHigh ?? surfaceContainerHigh,
        onSurface: overrides.onSurface ?? onSurface,
        onSurfaceVariant: overrides.onSurfaceVariant ?? onSurfaceVariant,
        outline: overrides.outline ?? outline,
        error: overrides.error ?? error,
      );

  bool get hasAnyColor => <Color?>[
        primary,
        onPrimary,
        surface,
        surfaceContainerHigh,
        onSurface,
        onSurfaceVariant,
        outline,
        error,
      ].any((c) => c != null);

  ColorScheme toColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(
        seedColor: primary ?? Colors.blueAccent,
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        surfaceContainerHigh: surfaceContainerHigh,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        error: error,
      );

  Map<String, dynamic> toJson() => {
        if (primary != null) 'primary': primary!.toARGB32(),
        if (onPrimary != null) 'onPrimary': onPrimary!.toARGB32(),
        if (surface != null) 'surface': surface!.toARGB32(),
        if (surfaceContainerHigh != null)
          'surfaceContainerHigh': surfaceContainerHigh!.toARGB32(),
        if (onSurface != null) 'onSurface': onSurface!.toARGB32(),
        if (onSurfaceVariant != null)
          'onSurfaceVariant': onSurfaceVariant!.toARGB32(),
        if (outline != null) 'outline': outline!.toARGB32(),
        if (error != null) 'error': error!.toARGB32(),
      };

  factory ImportedColorRoleSet.fromJson(Map<String, dynamic> json) =>
      ImportedColorRoleSet(
        primary: _colorFromJson(json['primary']),
        onPrimary: _colorFromJson(json['onPrimary']),
        surface: _colorFromJson(json['surface']),
        surfaceContainerHigh: _colorFromJson(json['surfaceContainerHigh']),
        onSurface: _colorFromJson(json['onSurface']),
        onSurfaceVariant: _colorFromJson(json['onSurfaceVariant']),
        outline: _colorFromJson(json['outline']),
        error: _colorFromJson(json['error']),
      );

  static Color? _colorFromJson(dynamic value) =>
      value == null ? null : Color(value as int);
}
