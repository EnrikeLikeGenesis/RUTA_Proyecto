import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/report_point.dart';

class ReportService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Trae todos los puntos de reporte dentro de un rango aproximado
  /// (un "cuadrado" alrededor de la ubicación, simple y suficiente para el MVP).
  Future<List<ReportPoint>> getNearbyReports({
    required double latitude,
    required double longitude,
    double radiusInDegrees = 0.05, // ~5km aprox
  }) async {
    final data = await _client
        .from('report_points')
        .select('*, profiles(username)')
        .gte('latitude', latitude - radiusInDegrees)
        .lte('latitude', latitude + radiusInDegrees)
        .gte('longitude', longitude - radiusInDegrees)
        .lte('longitude', longitude + radiusInDegrees)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => ReportPoint.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Trae todos los puntos de reporte, sin filtrar por cercanía.
  /// Se usa en la pestaña "Comunidad" para mostrar el feed completo.
  Future<List<ReportPoint>> getAllReports() async {
    final data = await _client
        .from('report_points')
        .select('*, profiles(username)')
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => ReportPoint.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createReport(ReportPoint report) async {
    await _client.from('report_points').insert(report.toInsertMap());
  }

  Future<void> updateReport(ReportPoint report) async {
    await _client.from('report_points').update({
      'title': report.title,
      'description': report.description,
      'category': report.category,
    }).eq('id', report.id);
  }

  Future<void> deleteReport(String reportId) async {
    await _client.from('report_points').delete().eq('id', reportId);
  }

  /// Se suscribe en tiempo real a los INSERT de la tabla "report_points"
  /// y llama a [onInsert] con cada reporte nuevo apenas se crea (el suyo
  /// o el de cualquier otro usuario). Requiere que la tabla tenga
  /// habilitada la replicación Realtime en Supabase (Database > Replication).
  ///
  /// Devuelve el canal para poder cancelarlo con [unsubscribe] cuando la
  /// pantalla que lo usa se destruye.
  RealtimeChannel subscribeToNewReports({
    required void Function(ReportPoint report) onInsert,
  }) {
    final channel = _client
        .channel('public:report_points')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'report_points',
          callback: (payload) {
            onInsert(ReportPoint.fromMap(payload.newRecord));
          },
        )
        .subscribe();

    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) {
    return _client.removeChannel(channel);
  }
}
