import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../config/report_categories.dart';
import '../../models/report_point.dart';
import '../../services/report_service.dart';

class CreateReportScreen extends StatefulWidget {
  final LatLng position;
  final String userId;
  final ReportPoint? existingReport;

  const CreateReportScreen({
    super.key,
    required this.position,
    required this.userId,
    this.existingReport,
  });

  bool get isEditing => existingReport != null;

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ReportService _reportService = ReportService();

  String _category = 'baches';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingReport;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _category = existing.category;
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final existing = widget.existingReport;
    final report = ReportPoint(
      id: existing?.id ?? '', // lo genera Supabase si es nuevo
      userId: existing?.userId ?? widget.userId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      latitude: existing?.latitude ?? widget.position.latitude,
      longitude: existing?.longitude ?? widget.position.longitude,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.isEditing) {
        await _reportService.updateReport(report);
      } else {
        await _reportService.createReport(report);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar punto de reporte' : 'Nuevo punto de reporte'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ...reportCategories.map(
                    (category) => DropdownMenuItem(
                      value: category.value,
                      child: Text(category.label),
                    ),
                  ),
                  if (reportCategoryFor(_category) == null)
                    DropdownMenuItem(value: _category, child: Text(_category)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.isEditing ? 'Guardar cambios' : 'Guardar punto'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
