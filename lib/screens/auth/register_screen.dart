import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_text.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Paleta de colores celeste / azul
  static const Color primaryColor = Color(0xFF65B9F0);      // Azul celeste principal
  static const Color accentColor = Color(0xFF358BCB);       // Azul más intenso para detalles e íconos
  static const Color backgroundColor = Color(0xFFDDF2FF);  // Celeste claro para fondo/degradado
  static const Color cardBackgroundColor = Color(0xFFF7FCFF); // Relleno suave de campos

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signUp(
      _emailController.text.trim(),
      _passwordController.text,
      _usernameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      address: _addressController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Account created. Check your email if confirmation is required.'
                : 'Cuenta creada. Revisá tu email si pide confirmación.',
          ),
          backgroundColor: accentColor,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.errorMessage ??
                (isEnglish ? 'Could not register' : 'Error al registrarse'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.black54),
      prefixIcon: Icon(prefixIcon, color: accentColor),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cardBackgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Colors.black12, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          appText(context, 'Crear cuenta', 'Create account'),
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [backgroundColor, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    appText(
                      context,
                      'Completa tus datos para registrarte',
                      'Complete your details to register',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // 1. Nombre
                  TextFormField(
                    controller: _firstNameController,
                    decoration: _buildInputDecoration(
                      labelText: appText(context, 'Nombre', 'First name'),
                      prefixIcon: Icons.person_outline,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? (isEnglish ? 'Required' : 'Requerido')
                            : null,
                  ),
                  const SizedBox(height: 16),

                  // 2. Apellido
                  TextFormField(
                    controller: _lastNameController,
                    decoration: _buildInputDecoration(
                      labelText: appText(context, 'Apellido', 'Last name'),
                      prefixIcon: Icons.person_outline_sharp,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? (isEnglish ? 'Required' : 'Requerido')
                            : null,
                  ),
                  const SizedBox(height: 16),

                  // 3. Nombre de usuario
                  TextFormField(
                    controller: _usernameController,
                    decoration: _buildInputDecoration(
                      labelText: appText(
                        context,
                        'Nombre de usuario',
                        'Username',
                      ),
                      prefixIcon: Icons.alternate_email,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? (isEnglish ? 'Required' : 'Requerido')
                            : null,
                  ),
                  const SizedBox(height: 16),

                  // 4. Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _buildInputDecoration(
                      labelText: appText(context, 'Email', 'Email'),
                      prefixIcon: Icons.email_outlined,
                    ),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return isEnglish
                            ? 'Enter a valid email address'
                            : 'Ingresá un email válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 5. Dirección
                  TextFormField(
                    controller: _addressController,
                    decoration: _buildInputDecoration(
                      labelText: appText(context, 'Dirección', 'Address'),
                      prefixIcon: Icons.home_outlined,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? (isEnglish ? 'Required' : 'Requerido')
                            : null,
                  ),
                  const SizedBox(height: 16),

                  // 6. Contraseña
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: _buildInputDecoration(
                      labelText: appText(context, 'Contraseña', 'Password'),
                      prefixIcon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: accentColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return isEnglish
                            ? 'At least 6 characters'
                            : 'Mínimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 7. Repetir contraseña
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: _buildInputDecoration(
                      labelText: appText(
                        context,
                        'Repetir contraseña',
                        'Confirm password',
                      ),
                      prefixIcon: Icons.lock_reset_outlined,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: accentColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return isEnglish
                            ? 'Please confirm your password'
                            : 'Repetí la contraseña';
                      }
                      if (value != _passwordController.text) {
                        return isEnglish
                            ? 'Passwords do not match'
                            : 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Botón de registro
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _handleRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              appText(context, 'Registrarme', 'Register'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}