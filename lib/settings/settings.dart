import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wqhub/audio/audio_controller.dart';
import 'package:wqhub/board/board_settings.dart';
import 'package:wqhub/board/board_theme.dart';
import 'package:wqhub/board/board_sizes.dart';
import 'package:wqhub/game_client/automatch_options.dart';
import 'package:wqhub/l10n/app_localizations.dart';
import 'package:wqhub/settings/analysis_provider.dart';
import 'package:wqhub/settings/appearance/color_role.dart';
import 'package:wqhub/settings/appearance/imported_color_role_set.dart';
import 'package:wqhub/settings/appearance/imported_color_theme.dart';
import 'package:wqhub/settings/appearance/imported_color_themes.dart';
import 'package:wqhub/train/custom_exam_presets.dart';
import 'package:wqhub/train/response_delay.dart';
import 'package:wqhub/wq/wq.dart' as wq;

enum PlayerRankVisibility {
  visible,
  hideRank,
  focusMode,
}

class Settings {
  final SharedPreferencesWithCache prefs;

  const Settings(this.prefs);

  static const _versionPatch = 'internal.version_patch';
  static const _localBoardSize = 'internal.local_board.size';
  static const _localBoardHandicap = 'internal.local_board.handicap';
  static const _localBoardMoves = 'internal.local_board.moves';
  static const _customExamPresets = 'internal.custom_exam_presets';
  static const _favoriteJosekiIds = 'internal.favorite_joseki_ids';
  // Default favorites shipped with the app; used until the learner
  // explicitly changes their favorites for the first time.
  static const _defaultFavoriteJosekiIds = <String>[
    '4-4/88b7ea82', // Response (O16)
    '4-4/0334b98b', // Attachment (Q14)
    '4-4/adfd4bd8', // Response (Q11)
    '4-4/f161f2b1', // High approach (Q14)
    '4-4/0e1853da', // Low approach (R11)
    '4-4/fe62c43d', // Attachment (R16)
    '3-4/edb71323', // One-space high pincer (N16)
    '3-4/ef2d2b2c', // Two-space high pincer (M16)
    '3-4/797bd3b9', // Low approach (R14)
    '3-3/7eca3ded', // High approach (Q16)
    '3-3/ae5c0f72', // Attachment (Q17)
  ];
  static const _themeKey = 'settings.theme';
  static const _behaviourKeyPrefix = 'settings.behaviour';
  static const _soundStoneKey = 'settings.sound.stone';
  static const _soundVoiceKey = 'settings.sound.voice';
  static const _soundUIKey = 'settings.sound.ui';
  static const _credentialsPrefix = 'settings.auth';
  static const _importedColorThemes = 'internal.imported_color_themes';
  static const _appLightColorTheme = 'settings.appearance.app_light_color_theme';
  static const _appDarkColorTheme = 'settings.appearance.app_dark_color_theme';
  static const _lightColorOverrides = 'settings.appearance.light_color_overrides';
  static const _darkColorOverrides = 'settings.appearance.dark_color_overrides';
  static const _boardTheme = 'settings.board.theme';
  static const _boardShowCoordinatesKey = 'settings.board.show_coordinates';
  static const _boardStoneShadowsKey = 'settings.board.stone_shadows';
  static const _boardEdgeLine = 'settings.board.edge_line';
  static const _rankVisibility = 'settings.appearance.rank_visibility';
  static const _fullscreen = 'settings.appearance.fullscreen';
  static const _saveDirectory = 'settings.save_dir';
  static const _locale = 'settings.language.locale';
  static const _helpDialogPrefix = 'settings.help';
  static const _ogsAutomatchPrefix = 'settings.ogs.automatch';

  // Internal preferences
  bool getVersionPatchStatus(String version) =>
      prefs.getBool('$_versionPatch.$version.status') ?? false;
  void setVersionPatchStatus(String version, bool status) =>
      prefs.setBool('$_versionPatch.$version.status', status);
  String? getSaveDirectory() => prefs.getString(_saveDirectory);
  set saveDirectory(String dir) => prefs.setString(_saveDirectory, dir);
  int get localBoardSize => prefs.getInt(_localBoardSize) ?? 19;
  set localBoardSize(int value) => prefs.setInt(_localBoardSize, value);
  int get localBoardHandicap => prefs.getInt(_localBoardHandicap) ?? 0;
  set localBoardHandicap(int value) => prefs.setInt(_localBoardHandicap, value);

  CustomExamPresets get customExamPresets {
    final val = prefs.getString(_customExamPresets);
    if (val == null) {
      return CustomExamPresets.empty();
    }
    return CustomExamPresets.fromJson(jsonDecode(val));
  }

  set customExamPresets(CustomExamPresets presets) {
    prefs.setString(_customExamPresets, jsonEncode(presets.toJson()));
  }

  List<String> get favoriteJosekiIds =>
      prefs.getStringList(_favoriteJosekiIds) ?? _defaultFavoriteJosekiIds;

  bool isJosekiFavorite(String id) =>
      (prefs.getStringList(_favoriteJosekiIds) ?? _defaultFavoriteJosekiIds)
          .contains(id);

  void setJosekiFavorite(String id, bool favorite) {
    final ids = prefs.getStringList(_favoriteJosekiIds) ??
        List<String>.from(_defaultFavoriteJosekiIds);
    ids.remove(id);
    if (favorite) ids.add(id);
    prefs.setStringList(_favoriteJosekiIds, ids);
  }

  bool get josekiRandomizeOrientation =>
      prefs.getBool('$_behaviourKeyPrefix.joseki_randomize_orientation') ?? true;
  set josekiRandomizeOrientation(bool v) =>
      prefs.setBool('$_behaviourKeyPrefix.joseki_randomize_orientation', v);

  bool get josekiRandomizeSide =>
      prefs.getBool('$_behaviourKeyPrefix.joseki_randomize_side') ?? true;
  set josekiRandomizeSide(bool v) =>
      prefs.setBool('$_behaviourKeyPrefix.joseki_randomize_side', v);

  Iterable<wq.Point> get localBoardMoves =>
      (prefs.getStringList(_localBoardMoves) ?? []).map(wq.parseSgfPoint);

  void pushLocalBoardMoves(Iterable<wq.Point?> ps) {
    final moves = prefs.getStringList(_localBoardMoves) ?? [];
    moves.addAll(ps.map((p) => p?.toSgf() ?? ''));
    prefs.setStringList(_localBoardMoves, moves);
  }

  void popLocalBoardMoves({int count = 1}) {
    final moves = prefs.getStringList(_localBoardMoves) ?? [];
    for (int i = 0; i < count && moves.isNotEmpty; ++i) {
      moves.removeLast();
    }
    prefs.setStringList(_localBoardMoves, moves);
  }

  void clearLocalBoardState() => prefs.setStringList(_localBoardMoves, []);

  // General
  ThemeMode get themeMode =>
      ThemeMode.values[prefs.getInt(_themeKey) ?? ThemeMode.system.index];
  set themeMode(ThemeMode mode) => prefs.setInt(_themeKey, mode.index);

  // Appearance
  ImportedColorThemes get importedColorThemes {
    final val = prefs.getString(_importedColorThemes);
    if (val == null) {
      return ImportedColorThemes.empty();
    }
    return ImportedColorThemes.fromJson(jsonDecode(val));
  }

  set importedColorThemes(ImportedColorThemes themes) {
    prefs.setString(_importedColorThemes, jsonEncode(themes.toJson()));
  }

  // The name of the currently selected imported theme for each brightness,
  // or null to use the app's default color scheme. Light and dark can point
  // at different imported themes (e.g. Catppuccin for light, Everforest for
  // dark).
  String? get appLightColorThemeName => prefs.getString(_appLightColorTheme);

  set appLightColorThemeName(String? name) {
    if (name == null) {
      prefs.remove(_appLightColorTheme);
    } else {
      prefs.setString(_appLightColorTheme, name);
    }
  }

  String? get appDarkColorThemeName => prefs.getString(_appDarkColorTheme);

  set appDarkColorThemeName(String? name) {
    if (name == null) {
      prefs.remove(_appDarkColorTheme);
    } else {
      prefs.setString(_appDarkColorTheme, name);
    }
  }

  ImportedColorRoleSet get lightColorOverrides {
    final val = prefs.getString(_lightColorOverrides);
    return val == null
        ? const ImportedColorRoleSet()
        : ImportedColorRoleSet.fromJson(jsonDecode(val));
  }

  set lightColorOverrides(ImportedColorRoleSet overrides) {
    prefs.setString(_lightColorOverrides, jsonEncode(overrides.toJson()));
  }

  ImportedColorRoleSet get darkColorOverrides {
    final val = prefs.getString(_darkColorOverrides);
    return val == null
        ? const ImportedColorRoleSet()
        : ImportedColorRoleSet.fromJson(jsonDecode(val));
  }

  set darkColorOverrides(ImportedColorRoleSet overrides) {
    prefs.setString(_darkColorOverrides, jsonEncode(overrides.toJson()));
  }

  void setLightColorOverride(ColorRole role, Color? color) {
    lightColorOverrides = lightColorOverrides.withColor(role, color);
  }

  void setDarkColorOverride(ColorRole role, Color? color) {
    darkColorOverrides = darkColorOverrides.withColor(role, color);
  }

  // Resolves the selected theme name for each brightness to its role set
  // overlaid with any manual per-role overrides, or null if nothing at all
  // is customized (falls back to the app's default color scheme).
  ImportedColorRoleSet? get appLightColorRoleSet {
    final name = appLightColorThemeName;
    final base = name == null ? null : importedColorThemes.themes[name]?.light;
    final overrides = lightColorOverrides;
    if (base == null && !overrides.hasAnyColor) return null;
    return (base ?? const ImportedColorRoleSet()).overlay(overrides);
  }

  ImportedColorRoleSet? get appDarkColorRoleSet {
    final name = appDarkColorThemeName;
    final base = name == null ? null : importedColorThemes.themes[name]?.dark;
    final overrides = darkColorOverrides;
    if (base == null && !overrides.hasAnyColor) return null;
    return (base ?? const ImportedColorRoleSet()).overlay(overrides);
  }

  void putImportedColorTheme(ImportedColorTheme theme) {
    final themes = importedColorThemes;
    themes.themes[theme.name] = theme;
    importedColorThemes = themes;
  }

  void removeImportedColorTheme(String name) {
    final themes = importedColorThemes;
    themes.themes.remove(name);
    importedColorThemes = themes;
    if (appLightColorThemeName == name) {
      appLightColorThemeName = null;
    }
    if (appDarkColorThemeName == name) {
      appDarkColorThemeName = null;
    }
  }

  BoardTheme get boardTheme =>
      BoardTheme.themes[prefs.getString(_boardTheme)] ?? BoardTheme.plain;
  bool get showCoordinates => prefs.getBool(_boardShowCoordinatesKey) ?? false;
  bool get stoneShadows => prefs.getBool(_boardStoneShadowsKey) ?? true;
  BoardEdgeLine get edgeLine =>
      BoardEdgeLine.values[prefs.getInt(_boardEdgeLine) ?? 0];
  PlayerRankVisibility get rankVisibility => PlayerRankVisibility.values[
      prefs.getInt(_rankVisibility) ?? PlayerRankVisibility.visible.index];
  bool get fullscreen => prefs.getBool(_fullscreen) ?? true;

  set boardTheme(BoardTheme theme) => prefs.setString(_boardTheme, theme.id);
  set showCoordinates(bool val) => prefs.setBool(_boardShowCoordinatesKey, val);
  set stoneShadows(bool val) => prefs.setBool(_boardStoneShadowsKey, val);
  set edgeLine(BoardEdgeLine edgeLine) =>
      prefs.setInt(_boardEdgeLine, edgeLine.index);
  set rankVisibility(PlayerRankVisibility val) =>
      prefs.setInt(_rankVisibility, val.index);
  set fullscreen(bool val) => prefs.setBool(_fullscreen, val);

  // Behaviour
  bool get confirmMoves =>
      prefs.getBool('$_behaviourKeyPrefix.confirm_moves') ??
      (Platform.isAndroid || Platform.isIOS);

  set confirmMoves(bool val) =>
      prefs.setBool('$_behaviourKeyPrefix.confirm_moves', val);

  int get confirmMovesBoardSize =>
      prefs.getInt('$_behaviourKeyPrefix.confirm_moves_board_size') ??
      BoardSizes.size_9.value;

  set confirmMovesBoardSize(int boardSize) =>
      prefs.setInt('$_behaviourKeyPrefix.confirm_moves_board_size', boardSize);

  ResponseDelay get responseDelay => ResponseDelay.values[
      prefs.getInt('$_behaviourKeyPrefix.response_delay') ??
          ResponseDelay.short.index];

  set responseDelay(ResponseDelay delay) =>
      prefs.setInt('$_behaviourKeyPrefix.response_delay', delay.index);

  AnalysisProvider? get analysisProvider {
    final i = prefs.getInt('$_behaviourKeyPrefix.analysis_provider');
    return i == null ? null : AnalysisProvider.values[i];
  }

  set analysisProvider(AnalysisProvider? provider) {
    if (provider != null) {
      prefs.setInt('$_behaviourKeyPrefix.analysis_provider', provider.index);
    }
  }

  bool get alwaysBlackToPlay =>
      prefs.getBool('$_behaviourKeyPrefix.always_black_to_play') ?? true;

  set alwaysBlackToPlay(bool val) =>
      prefs.setBool('$_behaviourKeyPrefix.always_black_to_play', val);

  bool get randomizeTaskOrientation =>
      prefs.getBool('$_behaviourKeyPrefix.randomize_task_orientation') ?? false;

  set randomizeTaskOrientation(bool val) =>
      prefs.setBool('$_behaviourKeyPrefix.randomize_task_orientation', val);

  bool get showMoveErrorsAsCrosses =>
      prefs.getBool('$_behaviourKeyPrefix.show_move_errors_as_crosses') ??
      false;

  set showMoveErrorsAsCrosses(bool val) =>
      prefs.setBool('$_behaviourKeyPrefix.show_move_errors_as_crosses', val);

  bool get trackTimeFrenzyMistakes =>
      prefs.getBool('$_behaviourKeyPrefix.track_time_frenzy_mistakes') ?? false;

  set trackTimeFrenzyMistakes(bool val) =>
      prefs.setBool('$_behaviourKeyPrefix.track_time_frenzy_mistakes', val);

  // Sound
  double get soundStone => prefs.getDouble(_soundStoneKey) ?? 1.0;
  set soundStone(double val) => prefs.setDouble(_soundStoneKey, val).then((_) {
        AudioController().stoneVolume = val;
      });

  double get soundVoice => prefs.getDouble(_soundVoiceKey) ?? 1.0;
  set soundVoice(double val) => prefs.setDouble(_soundVoiceKey, val).then((_) {
        AudioController().voiceVolume = val;
      });

  double get soundUI => prefs.getDouble(_soundUIKey) ?? 1.0;
  set soundUI(double val) => prefs.setDouble(_soundUIKey, val).then((_) {
        AudioController().uiVolume = val;
      });

  // Locale
  Locale get locale => Locale(prefs.getString(_locale) ?? _defaultLocale());
  set locale(Locale loc) => prefs.setString(_locale, loc.languageCode);

  String _defaultLocale() {
    final platformLoc = Locale(Platform.localeName);
    for (final loc in AppLocalizations.supportedLocales) {
      if (loc.languageCode == platformLoc.languageCode) {
        return loc.languageCode;
      }
    }
    return 'en';
  }

  // Auth
  String? getUsername(String serverId) =>
      prefs.getString('$_credentialsPrefix.$serverId.username');

  String? getPassword(String serverId) =>
      prefs.getString('$_credentialsPrefix.$serverId.password');

  void setUsername(String serverId, String username) {
    prefs.setString('$_credentialsPrefix.$serverId.username', username);
  }

  void setPassword(String serverId, String password) {
    prefs.setString('$_credentialsPrefix.$serverId.password', password);
  }

  // OGS automatch
  int get ogsAutomatchUpperRankDiff =>
      prefs.getInt('$_ogsAutomatchPrefix.upper_rank_diff') ??
      AutomatchOptions.defaultRankDiff;
  set ogsAutomatchUpperRankDiff(int val) =>
      prefs.setInt('$_ogsAutomatchPrefix.upper_rank_diff', val);

  int get ogsAutomatchLowerRankDiff =>
      prefs.getInt('$_ogsAutomatchPrefix.lower_rank_diff') ??
      AutomatchOptions.defaultRankDiff;
  set ogsAutomatchLowerRankDiff(int val) =>
      prefs.setInt('$_ogsAutomatchPrefix.lower_rank_diff', val);

  // Help
  bool get showCollectionsHelp =>
      prefs.getBool('$_helpDialogPrefix.collections') ?? true;
  set showCollectionsHelp(bool b) =>
      prefs.setBool('$_helpDialogPrefix.collections', b);
  bool get showGradingExamHelp =>
      prefs.getBool('$_helpDialogPrefix.grading_exam') ?? true;
  set showGradingExamHelp(bool b) =>
      prefs.setBool('$_helpDialogPrefix.grading_exam', b);
  bool get showEndgameExamHelp =>
      prefs.getBool('$_helpDialogPrefix.endgame_exam') ?? true;
  set showEndgameExamHelp(bool b) =>
      prefs.setBool('$_helpDialogPrefix.endgame_exam', b);
  bool get showTimeFrenzyHelp =>
      prefs.getBool('$_helpDialogPrefix.time_frenzy') ?? true;
  set showTimeFrenzyHelp(bool b) =>
      prefs.setBool('$_helpDialogPrefix.time_frenzy', b);
  bool get showRankedModeHelp =>
      prefs.getBool('$_helpDialogPrefix.ranked_mode') ?? true;
  set showRankedModeHelp(bool b) =>
      prefs.setBool('$_helpDialogPrefix.ranked_mode', b);
}
