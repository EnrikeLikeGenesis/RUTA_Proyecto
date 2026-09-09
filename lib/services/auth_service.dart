import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required String firstName,
    required String lastName,
    required String address,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    // Si el registro fue exitoso, creamos el perfil en la tabla "profiles"
    if (response.user != null) {
      await _client.from('profiles').insert({
        'id': response.user!.id,
        'email': email,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'address': address,
      });
    }

    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return data;
  }

  Future<void> updateUsername(String userId, String newUsername) async {
    await _client
        .from('profiles')
        .update({'username': newUsername}).eq('id', userId);
  }
}
