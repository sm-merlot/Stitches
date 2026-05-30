import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result returned by [ResizeCanvasDialog].
typedef ResizeResult = ({int width, int height, int anchorX, int anchorY});

class ResizeCanvasDialog extends StatefulWidget {
  final int currentWidth;
  final int currentHeight;

  const ResizeCanvasDialog({
    super.key,
    required this.currentWidth,
    required this.currentHeight,
  });

  @override
  State<ResizeCanvasDialog> createState() => _ResizeCanvasDialogState();
}

class _ResizeCanvasDialogState extends State<ResizeCanvasDialog> {
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  final _formKey = GlobalKey<FormState>();

  // Anchor: 0 = left/top, 1 = centre, 2 = right/bottom
  int _anchorX = 0;
  int _anchorY = 0;

  @override
  void initState() {
    super.initState();
    _widthCtrl = TextEditingController(text: widget.currentWidth.toString());
    _heightCtrl = TextEditingController(text: widget.currentHeight.toString());
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  String? _validateDim(String? value, String field) {
    if (value == null || value.isEmpty) return 'Required';
    final n = int.tryParse(value);
    if (n == null || n < 1) return '$field must be at least 1';
    if (n > 500) return '$field cannot exceed 500';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop<ResizeResult>((
      width: int.parse(_widthCtrl.text),
      height: int.parse(_heightCtrl.text),
      anchorX: _anchorX,
      anchorY: _anchorY,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resize Aida'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current size: ${widget.currentWidth} × ${widget.currentHeight}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _widthCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Width (cells)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => _validateDim(v, 'Width'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _heightCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Height (cells)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => _validateDim(v, 'Height'),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ── Anchor picker ──────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anchor',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Where existing content\nstays when resizing',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _AnchorPicker(
                    anchorX: _anchorX,
                    anchorY: _anchorY,
                    onChanged: (x, y) =>
                        setState(() {
                          _anchorX = x;
                          _anchorY = y;
                        }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Resize'),
        ),
      ],
    );
  }
}

// ─── Anchor picker ────────────────────────────────────────────────────────────

class _AnchorPicker extends StatelessWidget {
  final int anchorX;
  final int anchorY;
  final void Function(int x, int y) onChanged;

  const _AnchorPicker({
    required this.anchorX,
    required this.anchorY,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: 78,
      height: 78,
      child: Column(
        children: List.generate(3, (row) {
          return Expanded(
            child: Row(
              children: List.generate(3, (col) {
                final isSelected = col == anchorX && row == anchorY;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: GestureDetector(
                      onTap: () => onChanged(col, row),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primary
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: isSelected
                            ? Icon(Icons.circle,
                                size: 10, color: Colors.white.withValues(alpha: 0.9))
                            : null,
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}
