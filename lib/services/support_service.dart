import 'package:supabase_flutter/supabase_flutter.dart';

class SupportService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getQuestions() async {
    final data = await _client
        .from('support_questions')
        .select()
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> createQuestion({
    required String subject,
    required String message,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Iniciá sesión para contactar con ayuda.');
    await _client.from('support_questions').insert({
      'user_id': userId,
      'subject': subject,
      'message': message,
    });
  }

  Future<void> answerQuestion({
    required String questionId,
    required String answer,
  }) async {
    await _client.from('support_questions').update({
      'admin_reply': answer,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', questionId);
  }
}
