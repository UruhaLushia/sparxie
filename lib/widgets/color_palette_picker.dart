import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gamepad_navigation.dart';

Future<Color?> showColorPalettePicker(
  BuildContext context, {
  required String title,
  required Color color,
}) => showDialog<Color>(
  context: context,
  builder: (_) => _ColorPaletteDialog(title: title, initialColor: color),
);

class _ColorPaletteDialog extends StatefulWidget {
  const _ColorPaletteDialog({required this.title, required this.initialColor});

  final String title;
  final Color initialColor;

  @override
  State<_ColorPaletteDialog> createState() => _ColorPaletteDialogState();
}

class _ColorPaletteDialogState extends State<_ColorPaletteDialog> {
  static const _presets = [
    Color(0xff66ccff),
    Color(0xff7c3aed),
    Color(0xffdb2777),
    Color(0xffdc2626),
    Color(0xffea580c),
    Color(0xffca8a04),
    Color(0xff16a34a),
    Color(0xff0d9488),
    Color(0xff0891b2),
    Color(0xff475569),
  ];

  late HSVColor _hsv;
  late final TextEditingController _hexController;

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _hex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(Color color) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _hexController.text = _hex(color);
    });
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexController.text = _hex(hsv.toColor());
    });
  }

  void _setHexColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SaturationValuePicker(hsv: _hsv, onChanged: _setHsv),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.palette_outlined, size: 18),
                  Expanded(
                    child: GamepadSliderControl(
                      value: _hsv.hue,
                      min: 0,
                      max: 360,
                      divisions: 360,
                      onChanged: (hue) => _setHsv(_hsv.withHue(hue)),
                      child: Slider(
                        value: _hsv.hue,
                        min: 0,
                        max: 360,
                        onChanged: (hue) => _setHsv(_hsv.withHue(hue)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: TextField(
                      controller: _hexController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixText: '#',
                      ),
                      onChanged: (value) {
                        final parsed = _parseHex(value);
                        if (parsed != null) _setHexColor(parsed);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _presets)
                    AppFocusHighlight(
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => _setColor(color),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color.toARGB32() == color.toARGB32()
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(Offset position) {
            final saturation = (position.dx / constraints.maxWidth).clamp(
              0.0,
              1.0,
            );
            final value =
                1 - (position.dy / constraints.maxHeight).clamp(0.0, 1.0);
            onChanged(hsv.withSaturation(saturation).withValue(value));
          }

          return GestureDetector(
            onTapDown: (details) => update(details.localPosition),
            onPanUpdate: (details) => update(details.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _PalettePainter(hue: hsv.hue),
                foregroundPainter: _PaletteThumbPainter(
                  position: Offset(
                    (hsv.saturation * constraints.maxWidth).clamp(
                      8,
                      constraints.maxWidth - 8,
                    ),
                    ((1 - hsv.value) * constraints.maxHeight).clamp(
                      8,
                      constraints.maxHeight - 8,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PalettePainter extends CustomPainter {
  const _PalettePainter({required this.hue});
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_PalettePainter oldDelegate) => hue != oldDelegate.hue;
}

class _PaletteThumbPainter extends CustomPainter {
  const _PaletteThumbPainter({required this.position});
  final Offset position;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      position,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    canvas.drawCircle(
      position,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black54,
    );
  }

  @override
  bool shouldRepaint(_PaletteThumbPainter oldDelegate) =>
      position != oldDelegate.position;
}

String _hex(Color color) =>
    color.toARGB32().toRadixString(16).substring(2).toUpperCase();

Color? _parseHex(String raw) {
  final clean = raw.replaceAll('#', '').trim();
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(0xff000000 | value);
}
