import 'package:flutter/material.dart';
import 'package:wqhub/settings/appearance/imported_color_role_set.dart';
import 'package:wqhub/settings/appearance/imported_color_theme.dart';

/// Parses an Obsidian `theme.css` file into an [ImportedColorTheme],
/// mapping the subset of Obsidian's CSS custom properties that have a
/// direct equivalent in Flutter's Material 3 [ColorScheme].
///
/// Throws a [FormatException] if none of the mapped roles can be resolved
/// for either brightness.
ImportedColorTheme parseObsidianThemeCss(String css, {required String name}) {
  final withoutComments = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final blocks = _splitBlocks(withoutComments);

  final baseVars = <String, String>{};
  final lightVars = <String, String>{};
  final darkVars = <String, String>{};

  for (final block in blocks) {
    final target = switch (_classify(block.$1)) {
      _Scope.dark => darkVars,
      _Scope.light => lightVars,
      _Scope.base => baseVars,
      _Scope.ignore => null,
    };
    if (target == null) continue;
    for (final match in _declarationPattern.allMatches(block.$2)) {
      target[match.group(1)!.trim()] = match.group(2)!.trim();
    }
  }

  final lightEnv = <String, String>{...baseVars, ...lightVars};
  final darkEnv = <String, String>{...baseVars, ...darkVars};

  final light = _resolveRoleSet(lightEnv, Brightness.light);
  final dark = _resolveRoleSet(darkEnv, Brightness.dark);

  if (!light.hasAnyColor && !dark.hasAnyColor) {
    throw const FormatException(
        'No recognizable color roles found in this theme file.');
  }

  return ImportedColorTheme(name: name, light: light, dark: dark);
}

enum _Scope { base, light, dark, ignore }

_Scope _classify(String selector) {
  final s = selector.toLowerCase();
  final hasDark = s.contains('.theme-dark');
  final hasLight = s.contains('.theme-light');
  // A selector mentioning both (e.g. a comma-separated list applying the
  // same declarations to both modes, or a `:where(.theme-dark, .theme-light)`
  // guard) declares values shared by both brightnesses, same as `:root`.
  if (hasDark && hasLight) return _Scope.base;
  if (hasDark) return _Scope.dark;
  if (hasLight) return _Scope.light;
  if (s.contains(':root') || s.contains('body')) return _Scope.base;
  return _Scope.ignore;
}

final _declarationPattern = RegExp(r'(--[a-zA-Z0-9_-]+)\s*:\s*([^;]+);?');

/// Splits CSS into top-level `(selector, body)` blocks using brace-depth
/// counting. Blocks nested inside e.g. `@media { ... }` are still captured
/// individually since every `{...}` span is recorded as its own block.
List<(String, String)> _splitBlocks(String css) {
  final blocks = <(String, String)>[];
  final openIndices = <int>[];
  final selectors = <String>[];
  var lastStart = 0;
  for (var i = 0; i < css.length; i++) {
    final char = css[i];
    if (char == '{') {
      selectors.add(css.substring(lastStart, i).trim());
      openIndices.add(i);
      lastStart = i + 1;
    } else if (char == '}' && openIndices.isNotEmpty) {
      final start = openIndices.removeLast();
      blocks.add((selectors.removeLast(), css.substring(start + 1, i)));
      lastStart = i + 1;
    }
  }
  return blocks;
}

ImportedColorRoleSet _resolveRoleSet(Map<String, String> env, Brightness b) {
  Color? pick(List<String> names) {
    for (final name in names) {
      final color = _resolve(env[name], env, b, 0);
      if (color != null) return color;
    }
    return null;
  }

  return ImportedColorRoleSet(
    primary: pick(['--interactive-accent', '--text-accent', '--color-accent']),
    onPrimary: pick(['--text-on-accent', '--text-on-accent-inverted']),
    surface: pick(['--background-primary']),
    surfaceContainerHigh: pick(['--background-secondary']),
    onSurface: pick(['--text-normal']),
    onSurfaceVariant: pick(['--text-muted']),
    outline: pick(['--background-modifier-border']),
    error: pick(['--text-error', '--color-red']),
  );
}

final _varPattern =
    RegExp(r'^var\(\s*(--[a-zA-Z0-9_-]+)\s*(?:,\s*(.+))?\)$', dotAll: true);
final _lightDarkPattern = RegExp(r'^light-dark\(\s*(.+)\)$', dotAll: true);

const _maxResolveDepth = 8;

Color? _resolve(
    String? raw, Map<String, String> env, Brightness brightness, int depth) {
  if (raw == null || depth > _maxResolveDepth) return null;
  final value = raw.trim();

  final varMatch = _varPattern.firstMatch(value);
  if (varMatch != null) {
    final resolved = _resolve(env[varMatch.group(1)], env, brightness, depth + 1);
    if (resolved != null) return resolved;
    return _resolve(varMatch.group(2), env, brightness, depth + 1);
  }

  final lightDarkMatch = _lightDarkPattern.firstMatch(value);
  if (lightDarkMatch != null) {
    final args = _splitTopLevelArgs(lightDarkMatch.group(1)!);
    if (args.length == 2) {
      final chosen = brightness == Brightness.light ? args[0] : args[1];
      return _resolve(chosen, env, brightness, depth + 1);
    }
    return null;
  }

  return _parseCssColor(value, env, depth);
}

/// Splits a comma-separated argument list on top-level commas only, i.e.
/// commas that aren't nested inside another `(...)` (such as a `rgb(...)`
/// passed as one side of a `light-dark(...)` call).
List<String> _splitTopLevelArgs(String s) {
  final args = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final char = s[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
    } else if (char == ',' && depth == 0) {
      args.add(s.substring(start, i).trim());
      start = i + 1;
    }
  }
  args.add(s.substring(start).trim());
  return args;
}

final _hexPattern = RegExp(r'^#([0-9a-fA-F]{3,8})$');
final _rgbPattern = RegExp(r'^rgba?\((.+)\)$', caseSensitive: false);
final _hslPattern = RegExp(r'^hsla?\((.+)\)$', caseSensitive: false);

Color? _parseCssColor(String value, Map<String, String> env, int depth) {
  final hexMatch = _hexPattern.firstMatch(value);
  if (hexMatch != null) return _parseHexColor(hexMatch.group(1)!);

  final rgbMatch = _rgbPattern.firstMatch(value);
  if (rgbMatch != null) return _parseRgbColor(rgbMatch.group(1)!, env, depth);

  final hslMatch = _hslPattern.firstMatch(value);
  if (hslMatch != null) return _parseHslColor(hslMatch.group(1)!, env, depth);

  return null;
}

Color? _parseHexColor(String hex) {
  // CSS puts alpha last (RRGGBBAA); Flutter's Color wants it first (AARRGGBB).
  final full = switch (hex.length) {
    3 => 'ff${_doubleHexDigits(hex)}', // #rgb
    4 => _moveAlphaFirst(_doubleHexDigits(hex)), // #rgba
    6 => 'ff$hex', // #rrggbb
    8 => _moveAlphaFirst(hex), // #rrggbbaa
    _ => null,
  };
  if (full == null) return null;
  final argb = int.tryParse(full, radix: 16);
  return argb == null ? null : Color(argb);
}

String _doubleHexDigits(String s) => s.split('').map((c) => '$c$c').join();

String _moveAlphaFirst(String rrggbbaa) =>
    '${rrggbbaa.substring(6, 8)}${rrggbbaa.substring(0, 6)}';

double? _parseChannel(String token, {bool isAlpha = false}) {
  final t = token.trim();
  if (t.endsWith('%')) {
    final pct = double.tryParse(t.substring(0, t.length - 1));
    if (pct == null) return null;
    return isAlpha ? pct / 100 : pct * 2.55;
  }
  return double.tryParse(t);
}

Color? _parseRgbColor(String args, Map<String, String> env, int depth) {
  final (channels, alphaToken) = _extractChannelTokens(args, env, depth);
  if (channels.length < 3) return null;
  final r = _parseChannel(channels[0]);
  final g = _parseChannel(channels[1]);
  final b = _parseChannel(channels[2]);
  if (r == null || g == null || b == null) return null;
  final alpha = alphaToken == null ? 1.0 : _parseChannel(alphaToken, isAlpha: true);
  if (alpha == null) return null;
  return Color.fromARGB(
      (alpha * 255).round().clamp(0, 255),
      r.round().clamp(0, 255),
      g.round().clamp(0, 255),
      b.round().clamp(0, 255));
}

Color? _parseHslColor(String args, Map<String, String> env, int depth) {
  final (channels, alphaToken) = _extractChannelTokens(args, env, depth);
  if (channels.length < 3) return null;
  final hueToken = channels[0].replaceAll(RegExp(r'deg$'), '');
  final hue = double.tryParse(hueToken);
  final satToken = channels[1];
  final lightToken = channels[2];
  if (hue == null || !satToken.endsWith('%') || !lightToken.endsWith('%')) {
    return null;
  }
  final sat = double.tryParse(satToken.substring(0, satToken.length - 1));
  final light = double.tryParse(lightToken.substring(0, lightToken.length - 1));
  if (sat == null || light == null) return null;
  final alpha = alphaToken == null ? 1.0 : _parseChannel(alphaToken, isAlpha: true);
  if (alpha == null) return null;
  return HSLColor.fromAHSL(alpha, hue % 360, (sat / 100).clamp(0, 1),
          (light / 100).clamp(0, 1))
      .toColor();
}

/// Finds the index of the first top-level occurrence of [char] in [s], i.e.
/// one not nested inside a `(...)` call (so the `/` alpha separator in
/// `rgb(10 20 30 / 50%)` isn't confused with one buried in a nested value).
int _topLevelIndexOf(String s, String char) {
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (c == char && depth == 0) {
      return i;
    }
  }
  return -1;
}

/// Resolves a raw value fragment that is (or starts with) a bare
/// `var(--name[, fallback])` reference into its underlying declared text,
/// by looking the variable up in [env]. Some themes (e.g. Catppuccin) store
/// a bare channel triplet like `--ctp-crust: 220, 224, 232;` and reuse it as
/// `rgb(var(--ctp-crust))`, so this must run before channels are split out.
String _expandVarToken(String token, Map<String, String> env, int depth) {
  if (depth > _maxResolveDepth) return token;
  final match = _varPattern.firstMatch(token.trim());
  if (match == null) return token;
  final value = env[match.group(1)];
  if (value != null) return _expandVarToken(value, env, depth + 1);
  final fallback = match.group(2);
  if (fallback != null) return _expandVarToken(fallback, env, depth + 1);
  return token;
}

/// Extracts the numeric/percentage channel tokens and an optional alpha
/// token from the contents of an `rgb()`/`rgba()`/`hsl()`/`hsla()` call,
/// expanding any bare `var(...)` tokens first (see [_expandVarToken]) and
/// accepting legacy comma syntax, modern space/slash syntax, and themes
/// that mix a `var()`-collapsed triplet with a literal trailing alpha.
(List<String>, String?) _extractChannelTokens(
    String args, Map<String, String> env, int depth) {
  String expand(String token) => _expandVarToken(token.trim(), env, depth);

  var main = args;
  String? alphaToken;
  final slashIndex = _topLevelIndexOf(args, '/');
  if (slashIndex != -1) {
    main = args.substring(0, slashIndex);
    alphaToken = expand(args.substring(slashIndex + 1));
  }

  final channels = <String>[];
  for (final part in _splitTopLevelArgs(main).map(expand)) {
    if (part.contains(',')) {
      channels.addAll(_splitTopLevelArgs(part));
    } else {
      channels.addAll(part.trim().split(RegExp(r'\s+')));
    }
  }
  channels.removeWhere((c) => c.isEmpty);

  if (alphaToken == null && channels.length == 4) {
    alphaToken = channels.removeLast();
  }

  return (channels, alphaToken);
}
