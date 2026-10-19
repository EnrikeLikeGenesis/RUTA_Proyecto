import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../config/report_categories.dart';
import '../../l10n/app_text.dart';
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
  final ImagePicker _imagePicker = ImagePicker();

  String _category = 'baches';
  bool _isSaving = false;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _removeExistingImage = false;

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

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
        _removeExistingImage = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'en'
                  ? 'Could not select image: $e'
                  : 'No se pudo seleccionar la imagen: $e',
            ),
          ),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
      _removeExistingImage = true;
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final existing = widget.existingReport;

    try {
      var imageUrl = _removeExistingImage ? null : existing?.imageUrl;
      if (_selectedImage != null && _selectedImageBytes != null) {
        final fileNameParts = _selectedImage!.name.split('.');
        final extension = fileNameParts.length > 1 ? fileNameParts.last : 'jpg';
        imageUrl = await _reportService.uploadReportImage(
          userId: widget.userId,
          bytes: _selectedImageBytes!,
          fileExtension: extension,
          contentType: _selectedImage!.mimeType,
        );
      }

      final report = ReportPoint(
        id: existing?.id ?? '',
        userId: existing?.userId ?? widget.userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        latitude: existing?.latitude ?? widget.position.latitude,
        longitude: existing?.longitude ?? widget.position.longitude,
        createdAt: existing?.createdAt ?? DateTime.now(),
        imageUrl: imageUrl,
      );

      if (widget.isEditing) {
        await _reportService.updateReport(report);
      } else {
        await _reportService.createReport(report);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'en'
                  ? 'Could not save report: ${appErrorText(context, e)}'
                  : 'Error al guardar: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? appText(context, 'Editar punto de reporte', 'Edit report')
              : appText(context, 'Nuevo punto de reporte', 'New report'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: appText(context, 'Título', 'Title'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? (isEnglish ? 'Required' : 'Requerido')
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: appText(context, 'Descripción', 'Description'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: appText(context, 'Categoría', 'Category'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  ...reportCategories.map(
                    (category) => DropdownMenuItem(
                      value: category.value,
                      child: Text(reportCategoryText(context, category.label)),
                    ),
                  ),
                  if (reportCategoryFor(_category) == null)
                    DropdownMenuItem(value: _category, child: Text(_category)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 16),
              _buildImageSection(),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isEditing
                            ? appText(
                                context,
                                'Guardar cambios',
                                'Save changes',
                              )
                            : appText(context, 'Guardar punto', 'Save report'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final existingImageUrl = widget.existingReport?.imageUrl;
    final hasImage =
        _selectedImageBytes != null ||
        (existingImageUrl != null && !_removeExistingImage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(context, 'Imagen', 'Image'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_selectedImageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _selectedImageBytes!,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
          )
        else if (existingImageUrl != null && !_removeExistingImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              existingImageUrl,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 200,
                alignment: Alignment.center,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  appText(
                    context,
                    'No se pudo cargar la imagen guardada',
                    'Could not load saved image',
                  ),
                ),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  hasImage
                      ? appText(context, 'Cambiar imagen', 'Change image')
                      : appText(context, 'Agregar imagen', 'Add image'),
                ),
              ),
            ),
            if (hasImage) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSaving ? null : _removeImage,
                tooltip: appText(context, 'Quitar imagen', 'Remove image'),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
