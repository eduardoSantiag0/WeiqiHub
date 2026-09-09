import 'package:flutter/material.dart';
import 'package:wqhub/l10n/app_localizations.dart';
import 'package:wqhub/settings/shared_preferences_inherited_widget.dart';

/// App-bar menu with the joseki/invasion practice toggles (randomize orientation
/// and randomize side). Both settings are persisted and apply to every joseki
/// drill - category, favorites and Invasions alike.
class JosekiPracticeSettingsButton extends StatefulWidget {
  const JosekiPracticeSettingsButton({super.key});

  @override
  State<JosekiPracticeSettingsButton> createState() =>
      _JosekiPracticeSettingsButtonState();
}

class _JosekiPracticeSettingsButtonState
    extends State<JosekiPracticeSettingsButton> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final settings = context.settings;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.tune),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          checked: settings.josekiRandomizeOrientation,
          onTap: () => setState(() => settings.josekiRandomizeOrientation =
              !settings.josekiRandomizeOrientation),
          child: Text(loc.josekiRandomizeOrientation),
        ),
        CheckedPopupMenuItem(
          checked: settings.josekiRandomizeSide,
          onTap: () => setState(
              () => settings.josekiRandomizeSide = !settings.josekiRandomizeSide),
          child: Text(loc.josekiRandomizeSide),
        ),
      ],
    );
  }
}
