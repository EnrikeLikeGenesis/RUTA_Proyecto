import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/support_service.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isGuest = context.watch<AuthProvider>().isGuest;
    final isEnglish = context.watch<ThemeProvider>().isEnglish;
    return Scaffold(
      appBar: AppBar(title: Text(isEnglish ? 'Help' : 'Ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: Text(
                isEnglish
                    ? 'Contact administration'
                    : 'Contactar con administración',
              ),
              subtitle: Text(
                isGuest
                    ? (isEnglish
                          ? 'Sign in to send and view private messages.'
                          : 'Iniciá sesión para enviar y consultar mensajes privados.')
                    : (isEnglish
                          ? 'Send a private question and check the reply.'
                          : 'Enviá una consulta privada y revisá la respuesta.'),
              ),
              enabled: !isGuest,
              onTap: isGuest
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupportQuestionsScreen(),
                      ),
                    ),
            ),
          ),
          _InfoTile(
            icon: Icons.description_outlined,
            title: isEnglish
                ? 'Terms and conditions'
                : 'Términos y condiciones',
            content: isEnglish ? _termsTextEnglish : _termsText,
          ),
          _InfoTile(
            icon: Icons.privacy_tip_outlined,
            title: isEnglish ? 'Privacy policy' : 'Políticas de privacidad',
            content: isEnglish ? _privacyTextEnglish : _privacyText,
          ),
          _FaqTile(isEnglish: isEnglish),
        ],
      ),
    );
  }
}

class SupportQuestionsScreen extends StatefulWidget {
  const SupportQuestionsScreen({super.key});

  @override
  State<SupportQuestionsScreen> createState() => _SupportQuestionsScreenState();
}

class _SupportQuestionsScreenState extends State<SupportQuestionsScreen> {
  final _service = SupportService();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  late Future<List<Map<String, dynamic>>> _questions;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _questions = _service.getQuestions();
  }

  Future<void> _send() async {
    final isEnglish = context.read<ThemeProvider>().isEnglish;
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      _notify(
        isEnglish
            ? 'Enter both a subject and a message.'
            : 'Completá el asunto y la consulta.',
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await _service.createQuestion(
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      );
      _subject.clear();
      _message.clear();
      setState(() => _questions = _service.getQuestions());
      _notify(
        isEnglish
            ? 'Your private question has been sent.'
            : 'Tu consulta privada fue enviada.',
      );
    } catch (error) {
      _notify(
        isEnglish
            ? 'Could not send your question: $error'
            : 'No se pudo enviar la consulta: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply(String questionId) async {
    final isEnglish = context.read<ThemeProvider>().isEnglish;
    final controller = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEnglish ? 'Reply to question' : 'Responder consulta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: isEnglish ? 'Reply' : 'Respuesta',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isEnglish ? 'Cancel' : 'Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(isEnglish ? 'Send' : 'Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (answer == null || answer.trim().isEmpty) return;
    try {
      await _service.answerQuestion(
        questionId: questionId,
        answer: answer.trim(),
      );
      if (mounted) setState(() => _questions = _service.getQuestions());
    } catch (error) {
      if (mounted) {
        _notify(
          isEnglish
              ? 'Could not send the reply: $error'
              : 'No se pudo enviar la respuesta: $error',
          isError: true,
        );
      }
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isEnglish = context.watch<ThemeProvider>().isEnglish;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEnglish ? 'Private support' : 'Consultas privadas'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!auth.isAdmin) ...[
            TextField(
              controller: _subject,
              decoration: InputDecoration(
                labelText: isEnglish ? 'Subject' : 'Asunto',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: isEnglish
                    ? 'How can we help?'
                    : '¿En qué podemos ayudarte?',
                border: OutlineInputBorder(),
              ),
              maxLength: 2000,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              label: Text(
                _sending
                    ? (isEnglish ? 'Sending…' : 'Enviando…')
                    : (isEnglish ? 'Send question' : 'Enviar consulta'),
              ),
            ),
            const Divider(height: 32),
            Text(
              isEnglish ? 'My questions' : 'Mis consultas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ] else
            Text(
              isEnglish
                  ? 'Support inbox. Only administrators can view and reply to all threads.'
                  : 'Bandeja de consultas. Solo las personas administradoras pueden ver '
                        'y responder todos los hilos.',
            ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _questions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    isEnglish
                        ? 'Could not load support questions: ${snapshot.error}'
                        : 'No se pudieron cargar las consultas: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final questions = snapshot.data!;
              if (questions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    isEnglish
                        ? 'There are no questions yet.'
                        : 'Todavía no hay consultas.',
                  ),
                );
              }
              return Column(
                children: questions.map((question) {
                  final questionId = question['id'] as String;
                  final reply = question['admin_reply'] as String?;
                  return Card(
                    child: ExpansionTile(
                      title: Text(question['subject'] as String? ?? ''),
                      subtitle: Text(question['message'] as String? ?? ''),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            reply == null || reply.isEmpty
                                ? (isEnglish
                                      ? 'Waiting for a reply'
                                      : 'Pendiente de respuesta')
                                : (isEnglish
                                      ? 'Administrator reply:\n$reply'
                                      : 'Respuesta de administración:\n$reply'),
                          ),
                        ),
                        if (auth.isAdmin) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _reply(questionId),
                              icon: const Icon(Icons.reply),
                              label: Text(
                                reply == null || reply.isEmpty
                                    ? (isEnglish ? 'Reply' : 'Responder')
                                    : (isEnglish
                                          ? 'Update reply'
                                          : 'Actualizar respuesta'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [Text(content)],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final bool isEnglish;

  const _FaqTile({required this.isEnglish});

  @override
  Widget build(BuildContext context) {
    final faqs = isEnglish
        ? const [
            (
              'How do I create a report?',
              'On the map, select a point and choose the option to create a report. '
                  'You can add a description and an image.',
            ),
            (
              'How do I change my details?',
              'Open My account, then Personal details to update your name, email, '
                  'phone or photo.',
            ),
            (
              'How do I contact administration?',
              'In Help, open Contact administration. Your questions and replies are '
                  'private and visible only to you and the administrators.',
            ),
          ]
        : const [
            (
              '¿Cómo creo un reporte?',
              'Desde el mapa, seleccioná el punto y usá la opción para crear un reporte. '
                  'Podés agregar una descripción y una imagen.',
            ),
            (
              '¿Cómo cambio mis datos?',
              'Entrá en Mi cuenta y luego en Datos personales para editar tu nombre, '
                  'correo, teléfono o foto.',
            ),
            (
              '¿Cómo contacto a administración?',
              'En Ayuda, abrí Contactar con administración. Tus consultas y respuestas '
                  'son privadas y solo las ven vos y el equipo administrador.',
            ),
          ];
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.quiz_outlined),
        title: Text(
          isEnglish ? 'Frequently asked questions' : 'Preguntas frecuentes',
        ),
        children: faqs
            .map((faq) => ListTile(title: Text(faq.$1), subtitle: Text(faq.$2)))
            .toList(),
      ),
    );
  }
}

const _termsText =
    'Borrador informativo: RÜTA permite consultar y compartir reportes de la '
    'comunidad y planificar recorridos. La información publicada por usuarios '
    'puede no ser exacta ni estar actualizada; verificá siempre las condiciones '
    'del entorno y respetá las normas de tránsito. El uso de la aplicación no '
    'reemplaza el criterio personal ni constituye una garantía de seguridad. '
    'Al usarla, aceptás hacerlo de forma lícita y responsable.';

const _privacyText =
    'Borrador informativo: RÜTA puede procesar los datos de cuenta que '
    'proporcionás, las imágenes y reportes que publicás, y la ubicación cuando '
    'usás funciones del mapa. Los datos de cuenta y las consultas de ayuda se '
    'gestionan mediante Supabase; las consultas privadas solo son visibles para '
    'su autor y administración. Podés editar tus datos desde Mi cuenta. Antes '
    'de publicar la aplicación, este borrador debe revisarse y reemplazarse por '
    'una política legal completa que identifique al responsable y los plazos de '
    'conservación.';

const _termsTextEnglish =
    'Informational draft: RÜTA lets you consult and share community reports and '
    'plan routes. Information posted by users may be inaccurate or out of date; '
    'always verify local conditions and follow traffic laws. Use of the app does '
    'not replace personal judgment or guarantee safety. You agree to use the app '
    'lawfully and responsibly.';

const _privacyTextEnglish =
    'Informational draft: RÜTA may process the account details you provide, '
    'images and reports you post, and your location when you use map features. '
    'Account data and support questions are managed through Supabase; private '
    'questions are visible only to their author and administrators. You can edit '
    'your details in My account. Before publication, this draft must be reviewed '
    'and replaced by a complete legal policy identifying the data controller '
    'and retention periods.';
