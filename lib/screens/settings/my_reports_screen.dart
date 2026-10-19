import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/report_point.dart';
import '../../l10n/app_text.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/report_service.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  final _reportService = ReportService();
  late Future<List<ReportPoint>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = _loadReports();
  }

  Future<List<ReportPoint>> _loadReports() {
    final userId = context.read<AuthProvider>().user!.id;
    return _reportService.getMyReports(userId);
  }

  Future<void> _refresh() async {
    final future = _loadReports();
    setState(() => _reports = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = context.watch<ThemeProvider>().isEnglish;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEnglish ? 'My reports' : 'Lista de reportes'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ReportPoint>>(
          future: _reports,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      isEnglish
                          ? 'Could not load your reports: ${appErrorText(context, snapshot.error!)}'
                          : 'No se pudieron cargar tus reportes: ${snapshot.error}',
                    ),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final reports = snapshot.data!;
            if (reports.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: 100),
                  Center(
                    child: Text(
                      isEnglish
                          ? "You haven't created any reports yet."
                          : 'Todavía no creaste reportes.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final report = reports[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: report.imageUrl == null
                        ? const CircleAvatar(child: Icon(Icons.report_outlined))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              report.imageUrl!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(
                                    width: 56,
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                            ),
                          ),
                    title: Text(report.title),
                    subtitle: Text(
                      '${reportCategoryText(context, report.category)} · ${report.createdAt.toLocal().day}/'
                      '${report.createdAt.toLocal().month}/'
                      '${report.createdAt.toLocal().year}\n'
                      '${report.description}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
