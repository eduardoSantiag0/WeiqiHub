import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wqhub/l10n/app_localizations.dart';

enum ColorPickerAction { set, clear }

/// A simple RGB-slider + hex-field color editor, with a "Clear" action that
/// lets the caller distinguish "remove this override" from "cancel, keep
/// whatever was there before" (both of which read as a `null` pop otherwise).
class ColorPickerDialog extends StatefulWidget {
  final String title;
  final Color? initialColor;

  const ColorPickerDialog({super.key, required this.title, this.initialColor});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _color = widget.initialColor ?? Colors.grey;
  late final TextEditingController _hexController =
      TextEditingController(text: _toHex(_color));
  String? _hexError;

  static String _toHex(Color c) =>
      ((c.r * 255).round().toRadixString(16).padLeft(2, '0') +
              (c.g * 255).round().toRadixString(16).padLeft(2, '0') +
              (c.b * 255).round().toRadixString(16).padLeft(2, '0'))
          .toUpperCase();

  void _setColor(Color color) {
    setState(() {
      _color = color;
      _hexController.text = _toHex(color);
      _hexError = null;
    });
  }

  void _onHexChanged(String value) {
    final hex = value.trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      setState(() => _hexError = AppLocalizations.of(context)!.invalidHexColor);
      return;
    }
    setState(() {
      _color = Color(int.parse('ff$hex', radix: 16));
      _hexError = null;
    });
  }

  Widget _channelSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.round().toString())),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: _color,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hexController,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              prefixText: '#',
              labelText: loc.hexColor,
              errorText: _hexError,
            ),
            onChanged: _onHexChanged,
          ),
          _channelSlider('R', _color.r * 255,
              (v) => _setColor(Color.fromARGB(255, v.round(), (_color.g * 255).round(), (_color.b * 255).round()))),
          _channelSlider('G', _color.g * 255,
              (v) => _setColor(Color.fromARGB(255, (_color.r * 255).round(), v.round(), (_color.b * 255).round()))),
          _channelSlider('B', _color.b * 255,
              (v) => _setColor(Color.fromARGB(255, (_color.r * 255).round(), (_color.g * 255).round(), v.round()))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(loc.cancel),
        ),
        if (widget.initialColor != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, (ColorPickerAction.clear, null)),
            child: Text(loc.clear),
          ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (ColorPickerAction.set, _color)),
          child: Text(loc.ok),
        ),
      ],
    );
  }
}
