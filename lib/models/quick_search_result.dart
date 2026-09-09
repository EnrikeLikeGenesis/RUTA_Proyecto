import '../models/report_point.dart';
import '../services/geocoding_service.dart';

/// Modo de búsqueda del panel unificado (chips "Calle" / "Reporte").
enum QuickSearchMode { calle, reporte }

/// Resultado elegido en la búsqueda unificada: puede ser una dirección
/// (para trazar una ruta desde la ubicación actual) o un reporte existente
/// (para centrar el mapa y ver sus detalles).
class QuickSearchResult {
  final AddressSuggestion? address;
  final ReportPoint? report;

  const QuickSearchResult.address(AddressSuggestion suggestion)
      : address = suggestion,
        report = null;

  const QuickSearchResult.report(ReportPoint reportPoint)
      : address = null,
        report = reportPoint;
}
