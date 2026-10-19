import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  Map<String, dynamic>? _profile;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isGuest = false;
  int _profileLoadGeneration = 0;

  AuthProvider() {
    _user = _authService.currentUser;
    _authService.authStateChanges.listen((state) {
      _user = state.session?.user;
      if (_user != null) {
        _isGuest = false;
        _profile = null;
        _loadProfile();
      } else {
        _profile = null;
        _isGuest = false;
      }
      notifyListeners();
    });
    if (_user != null) _loadProfile();
  }

  User? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAdmin => _profile?['is_admin'] == true;

  /// Indica si se está navegando la app en modo invitado (sin cuenta).
  bool get isGuest => _isGuest;

  /// Entra a la app como invitado: solo puede ver reportes y marcar
  /// ubicaciones en el mapa, sin poder crear reportes propios.
  void continueAsGuest() {
    _isGuest = true;
    notifyListeners();
  }

  /// Sale del modo invitado (por ejemplo, para ir a iniciar sesión).
  void exitGuest() {
    _isGuest = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final userId = _user?.id;
    if (userId == null) return;
    final generation = ++_profileLoadGeneration;
    final profile = await _authService.getProfile(userId);
    if (_user?.id != userId || generation != _profileLoadGeneration) return;
    _profile = profile;
    notifyListeners();
  }

  Future<bool> signUp(
    String email,
    String password,
    String username, {
    required String firstName,
    required String lastName,
    required String address,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authService.signUp(
        email: email,
        password: password,
        username: username,
        firstName: firstName,
        lastName: lastName,
        address: address,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _authService.signIn(email: email, password: password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isGuest = false;
    await _authService.signOut();
  }

  Future<void> updateUsername(String newUsername) async {
    if (_user == null) return;
    await _authService.updateUsername(_user!.id, newUsername);
    await _loadProfile();
    notifyListeners();
  }

  Future<void> updatePersonalDetails({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
  }) async {
    final userId = _user?.id;
    if (userId == null) throw StateError('No hay una sesión activa.');
    await _authService.updatePersonalDetails(
      userId: userId,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phoneNumber: phoneNumber,
    );
    await _loadProfile();
  }

  Future<void> updateProfileImage({
    required Uint8List bytes,
    required String fileExtension,
    String? contentType,
  }) async {
    final userId = _user?.id;
    if (userId == null) throw StateError('No hay una sesión activa.');
    final imageUrl = await _authService.uploadProfileImage(
      userId: userId,
      bytes: bytes,
      fileExtension: fileExtension,
      contentType: contentType,
    );
    await _authService.updateProfileImage(userId, imageUrl);
    await _loadProfile();
  }
}
