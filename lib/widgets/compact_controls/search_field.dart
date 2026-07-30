import 'package:flutter/material.dart';

import 'style.dart';

class CompactSearchField extends StatefulWidget {
  const CompactSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.onClear,
    this.suffixText,
    this.style,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final VoidCallback? onClear;
  final String? suffixText;
  final CompactControlStyle? style;

  @override
  State<CompactSearchField> createState() => _CompactSearchFieldState();
}

class _CompactSearchFieldState extends State<CompactSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CompactSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_handleControllerChanged);
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controlStyle = widget.style ?? CompactControlTheme.searchOf(context);
    final canClear =
        widget.controller?.text.isNotEmpty == true && widget.onClear != null;
    return SizedBox(
      height: controlStyle.fieldHeight,
      child: TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: controlStyle.fieldHeight * controlStyle.widthScale,
            minHeight: controlStyle.fieldHeight,
          ),
          suffixIcon: canClear
              ? Semantics(
                  button: true,
                  label: '清除筛选',
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: BoxConstraints.tightFor(
                      width: controlStyle.fieldHeight,
                      height: controlStyle.fieldHeight,
                    ),
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                )
              : null,
          suffixIconConstraints: BoxConstraints(
            minWidth: controlStyle.fieldHeight * controlStyle.widthScale,
            minHeight: controlStyle.fieldHeight,
          ),
          suffixText: widget.suffixText,
          hintText: widget.hintText,
          filled: true,
          fillColor: controlStyle.background(context),
          border: OutlineInputBorder(
            borderRadius: controlStyle.borderRadius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: controlStyle.borderRadius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: controlStyle.borderRadius,
            borderSide: BorderSide(
              color: controlStyle.focus(context),
              width: 1.5,
            ),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
