import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    if (auth.isLoggedIn && profile == null) return;
    _firstName.text = profile?['first_name'] as String? ?? '';
    _lastName.text = profile?['last_name'] as String? ?? '';
    _email.text = auth.user?.email ?? '';
    _phone.text = profile?['phone_number'] as String? ?? '';
    _initialized = true;
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      await context.read<AuthProvider>().updateProfileImage(
        bytes: await image.readAsBytes(),
        fileExtension: image.name.split('.').last,
        contentType: image.mimeType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<ThemeProvider>().isEnglish
                  ? 'Profile photo updated'
                  : 'Foto de perfil actualizada',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(
          context.read<ThemeProvider>().isEnglish
              ? 'Could not update photo: $error'
              : 'No se pudo actualizar la foto: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updatePersonalDetails(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        phoneNumber: _phone.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<ThemeProvider>().isEnglish
                  ? 'Details updated. If you changed your email, confirm it from your inbox.'
                  : 'Datos actualizados. Si cambiaste el correo, confirmalo desde tu email.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(
          context.read<ThemeProvider>().isEnglish
              ? 'Could not save details: $error'
              : 'No se pudieron guardar los datos: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final isEnglish = context.watch<ThemeProvider>().isEnglish;
    final avatarUrl = profile?['avatar_url'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEnglish ? 'Personal details' : 'Datos personales'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundImage: avatarUrl == null
                      ? null
                      : NetworkImage(avatarUrl),
                  child: avatarUrl == null
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    onPressed: _uploadingPhoto ? null : _pickPhoto,
                    icon: _uploadingPhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    tooltip: isEnglish
                        ? 'Change profile photo'
                        : 'Cambiar foto de perfil',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _firstName,
                  decoration: InputDecoration(
                    labelText: isEnglish ? 'First name' : 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, isEnglish),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _lastName,
                  decoration: InputDecoration(
                    labelText: isEnglish ? 'Last name' : 'Apellido',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, isEnglish),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: isEnglish
                        ? 'Email address'
                        : 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())) {
                      return isEnglish
                          ? 'Enter a valid email address'
                          : 'Ingresá un correo válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isEnglish ? 'Phone' : 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEnglish ? 'Save changes' : 'Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _required(String? value, bool isEnglish) =>
      value == null || value.trim().isEmpty
      ? (isEnglish ? 'This field is required' : 'Este campo es obligatorio')
      : null;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }
}
