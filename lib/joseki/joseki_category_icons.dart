import 'package:flutter/material.dart';

/// The icons a user may pick for their own joseki categories. Stored by key
/// (the `icon` field in joseki_library.json); the values must stay `const` so
/// Flutter's icon tree-shaking keeps working (no dynamic `IconData`).
const Map<String, IconData> josekiCategoryIcons = {
  'folder': Icons.folder_outlined,
  'star': Icons.star_outline,
  'book': Icons.menu_book_outlined,
  'school': Icons.school_outlined,
  'grid': Icons.grid_on,
  'target': Icons.my_location,
  'flag': Icons.flag_outlined,
  'bolt': Icons.bolt_outlined,
  'fire': Icons.local_fire_department_outlined,
  'shield': Icons.shield_outlined,
  'swords': Icons.sports_kabaddi_outlined,
  'crown': Icons.workspace_premium_outlined,
  'puzzle': Icons.extension_outlined,
  'lightbulb': Icons.lightbulb_outline,
  'compass': Icons.explore_outlined,
  'map': Icons.map_outlined,
  'corner': Icons.crop_square_outlined,
  'circle': Icons.circle_outlined,
  'diamond': Icons.diamond_outlined,
  'bookmark': Icons.bookmark_outline,
  'label': Icons.label_outline,
  'favorite': Icons.favorite_outline,
  'rocket': Icons.rocket_launch_outlined,
  'trophy': Icons.emoji_events_outlined,
};

/// Fallback icon for a category with no (or an unknown) stored key.
const IconData josekiCategoryDefaultIcon = Icons.folder_outlined;

/// Resolves a stored key to its icon, falling back to [josekiCategoryDefaultIcon].
IconData josekiCategoryIconFor(String? key) =>
    josekiCategoryIcons[key] ?? josekiCategoryDefaultIcon;
