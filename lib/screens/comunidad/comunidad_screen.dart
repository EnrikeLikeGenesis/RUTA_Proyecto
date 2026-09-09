import 'package:flutter/material.dart';
import '../../models/report_point.dart';
import '../../services/report_service.dart';

/// Feed con todos los reportes de la comunidad, sin filtrar por cercanía.
class ComunidadScreen extends StatefulWidget {
  /// Id del usuario logueado (null si es invitado), para poder mostrar
  /// "Mi reporte" en los reportes propios.
  final String? currentUserId;

  const ComunidadScreen({super.key, this.currentUserId});

  @override
  State<ComunidadScreen> createState() => _ComunidadScreenState();
}

class _ComunidadScreenState extends State<ComunidadScreen> {
  final _reportService = ReportService();
  late Future<List<ReportPoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = _reportService.getAllReports();
  }

  Future<void> _refresh() async {
    setState(() => _future = _reportService.getAllReports());
    await _future;
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'peligro':
        return Icons.warning_amber_rounded;
      case 'transito':
        return Icons.traffic;
      case 'evento':
        return Icons.event;
      default:
        return Icons.location_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad'), centerTitle: false),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ReportPoint>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('No se pudieron cargar los reportes: ${snapshot.error}')),
                ],
              );
            }
            final reports = snapshot.data ?? [];
            if (reports.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('Todavía no hay reportes de la comunidad.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final report = reports[index];
                final isOwnReport = widget.currentUserId != null &&
                    report.userId == widget.currentUserId;
                final authorLabel =
                    isOwnReport ? 'Mi reporte' : (report.username ?? 'Usuario');
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(_iconForCategory(report.category)),
                    ),
                    title: Text(report.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.description.isNotEmpty
                              ? report.description
                              : report.category,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          authorLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: isOwnReport
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      '${report.createdAt.toLocal().day}/${report.createdAt.toLocal().month}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
