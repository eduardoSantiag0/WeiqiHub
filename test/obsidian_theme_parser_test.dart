import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/settings/appearance/color_role.dart';
import 'package:wqhub/settings/appearance/imported_color_role_set.dart';
import 'package:wqhub/settings/appearance/obsidian_theme_parser.dart';

void main() {
  test('colorFor/withColor/overlay round-trip correctly', () {
    const base = ImportedColorRoleSet(
      primary: Colors.red,
      surface: Colors.white,
      onSurface: Colors.black,
    );

    expect(base.colorFor(ColorRole.primary), Colors.red);
    expect(base.colorFor(ColorRole.error), isNull);

    final withError = base.withColor(ColorRole.error, Colors.orange);
    expect(withError.colorFor(ColorRole.error), Colors.orange);
    // Unrelated fields are preserved.
    expect(withError.colorFor(ColorRole.primary), Colors.red);
    expect(withError.colorFor(ColorRole.surface), Colors.white);

    final cleared = withError.withColor(ColorRole.error, null);
    expect(cleared.colorFor(ColorRole.error), isNull);

    const overrides = ImportedColorRoleSet(primary: Colors.green);
    final overlaid = base.overlay(overrides);
    expect(overlaid.colorFor(ColorRole.primary), Colors.green); // override wins
    expect(overlaid.colorFor(ColorRole.surface), Colors.white); // base kept
  });

  test('resolves vars, hex/rgb/hsl colors and var() fallbacks', () {
    const css = '''
      :root {
        --color-accent: #3a7;
        --interactive-accent: var(--color-accent);
        --text-on-accent: #ffffff;
        --text-error: rgb(220, 50, 47);
      }
      .theme-light {
        --background-primary: #fdf6e3;
        --background-secondary: rgba(238, 232, 213, 0.5);
        --text-normal: hsl(194, 25%, 20%);
        --text-muted: var(--undefined-var, #93a1a1);
        --background-modifier-border: #eee8d5ff;
      }
      .theme-dark {
        --background-primary: #002b36;
        --text-normal: #839496;
      }
    ''';

    final theme = parseObsidianThemeCss(css, name: 'test');

    expect(theme.light.primary, const Color(0xff33aa77));
    expect(theme.light.onPrimary, Colors.white);
    expect(theme.light.error, const Color(0xffdc322f));
    expect(theme.light.surface, const Color(0xfffdf6e3));
    expect(theme.light.surfaceContainerHigh,
        const Color.fromARGB(128, 238, 232, 213));
    expect(theme.light.onSurface,
        HSLColor.fromAHSL(1, 194, 0.25, 0.20).toColor());
    expect(theme.light.onSurfaceVariant, const Color(0xff93a1a1));
    expect(theme.light.outline, const Color(0xffeee8d5));

    expect(theme.dark.primary, const Color(0xff33aa77));
    expect(theme.dark.surface, const Color(0xff002b36));
    expect(theme.dark.onSurface, const Color(0xff839496));
  });

  test('a shared selector mentioning both modes applies to both', () {
    const css = '''
      .theme-dark,
      .theme-light {
        --background-primary: #abcdef;
      }
      .theme-dark {
        --text-normal: #ffffff;
      }
      .theme-light {
        --text-normal: #000000;
      }
    ''';

    final theme = parseObsidianThemeCss(css, name: 'test');
    expect(theme.light.surface, const Color(0xffabcdef));
    expect(theme.dark.surface, const Color(0xffabcdef));
    expect(theme.light.onSurface, Colors.black);
    expect(theme.dark.onSurface, Colors.white);
  });

  test('throws FormatException on unparseable input', () {
    expect(() => parseObsidianThemeCss('not a theme', name: 'x'),
        throwsFormatException);
    expect(() => parseObsidianThemeCss('', name: 'x'), throwsFormatException);
  });

  for (final name in [
    'solarized',
    'wasp',
    'reverie',
    'catppuccin',
    'everforest',
  ]) {
    test('parses the bundled $name demo theme', () {
      final css = File('assets/themes/$name.css').readAsStringSync();
      final theme = parseObsidianThemeCss(css, name: name);
      expect(theme.light.hasAnyColor, isTrue, reason: '$name light');
      expect(theme.dark.hasAnyColor, isTrue, reason: '$name dark');
      expect(theme.light.surface, isNotNull, reason: '$name light surface');
      expect(theme.dark.surface, isNotNull, reason: '$name dark surface');
      expect(theme.light.surface, isNot(equals(theme.dark.surface)),
          reason: '$name light/dark surface should differ');
    });
  }
}
