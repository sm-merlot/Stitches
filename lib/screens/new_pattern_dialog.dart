import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pattern.dart';

class NewPatternDialog extends StatefulWidget {
  const NewPatternDialog({super.key});

  @override
  State<NewPatternDialog> createState() => _NewPatternDialogState();
}

class _NewPatternDialogState extends State<NewPatternDialog> {
  final _nameController = TextEditingController(text: 'New Pattern');
  final _widthController = TextEditingController(text: '30');
  final _heightController = TextEditingController(text: '30');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final pattern = CrossStitchPattern.empty(
      name: _nameController.text.trim(),
      width: int.parse(_widthController.text),
      height: int.parse(_heightController.text),
    );
    Navigator.of(context).pop(pattern);
  }

  String? _validatePositiveInt(String? value, String field) {
    if (value == null || value.isEmpty) return 'Required';
    final n = int.tryParse(value);
    if (n == null || n < 1) return '$field must be a positive number';
    if (n > 500) return '$field cannot exceed 500';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Pattern'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Pattern name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _widthController,
                      decoration: const InputDecoration(
                        labelText: 'Width (cells)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => _validatePositiveInt(v, 'Width'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      decoration: const InputDecoration(
                        labelText: 'Height (cells)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => _validatePositiveInt(v, 'Height'),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: you can resize your pattern later.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}
