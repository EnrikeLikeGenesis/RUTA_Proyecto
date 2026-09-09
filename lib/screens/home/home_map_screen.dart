import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/proximity_config.dart';
import '../../models/report_point.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_layer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/report_service.dart';
import '../../widgets/map_tile_layer.dart';
import '../report/create_report_screen.dart';
import '../settings/settings_screen.dart';

class HomeMapScreen extends StatefulWidget {
  /// Null cuando se navega como invitado.
  final String? userId;

  /// Si es true, el usuario está navegando sin cuenta: puede ver reportes
  /// y marcar ubicaciones en el mapa, pero no crear reportes propios.
  final bool isGuest;

  /// Se llama cuando se toca la barra de búsqueda de arriba, para que la
  /// pantalla contenedora cambie a la pestaña "Rutas".
  final VoidCallback? onSearchTap;

  /// Se llama cuando el usuario toca un punto del mapa para usarlo como
  /// parte de una ruta. La pantalla contenedora debe guardar el punto y
  /// cambiar a la pestaña "Rutas".
  final ValueChanged<LatLng>? onMapPointMarked;

  const HomeMapScreen({
    super.key,
    required this.userId,
    this.isGuest = false,
    this.onSearchTap,
    this.onMapPointMarked,
  });

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final LocationService _locationService = LocationService();
  final ReportService _reportService = ReportService();
  final MapController _mapController = MapController();

  LatLng? _currentPosition;
  List<ReportPoint> _reports = [];
  bool _isLoading = true;
  String? _errorMessage;

  /// Marcador local que puede dejar un invitado. No se guarda en el
  /// servidor, es solo una referencia visual sobre el mapa.
  LatLng? _guestMarker;

  /// Canal de Supabase Realtime que escucha los reportes nuevos para
  /// avisar por notificación cuando caen dentro del radio del usuario.
  RealtimeChannel? _reportsChannel;

  @override
  void initState() {
    super.initState();
    _initLocationAndReports();
    _subscribeToNewReports();
  }

  /// Escucha en tiempo real la creación de reportes (propios o de otros
  /// usuarios). Si el reporte cae dentro de [ProximityConfig.alertRadiusMeters]
  /// respecto a la posición actual del usuario, dispara una notificación
  /// y refresca los reportes cercanos que se ven en el mapa.
  void _subscribeToNewReports() {
    _reportsChannel = _reportService.subscribeToNewReports(
      onInsert: _handleIncomingReport,
    );
  }

  void _handleIncomingReport(ReportPoint report) {
    if (_currentPosition == null) return;

    // No notificar al propio autor sobre su propio reporte recién creado.
    if (!widget.isGuest && report.userId == widget.userId) return;

    final distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      report.latitude,
      report.longitude,
    );

    if (distanceInMeters <= ProximityConfig.alertRadiusMeters) {
      NotificationService.instance.showNearbyReportNotification(
        title: 'Se creó un reporte cerca tuyo',
        body: '${report.title} · a ${distanceInMeters.round()} m de tu ubicación',
      );
      _loadNearbyReports();
    }
  }

  Future<void> _initLocationAndReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final position = await _locationService.getCurrentPosition();
      _currentPosition = LatLng(position.latitude, position.longitude);
      await _loadNearbyReports();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNearbyReports() async {
    if (_currentPosition == null) return;
    final reports = await _reportService.getNearbyReports(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );
    setState(() => _reports = reports);
  }

  /// Se llama al tocar el mapa. Ya no crea un reporte: marca el punto
  /// tocado como parte de una ruta y le pide a la pantalla contenedora
  /// que cambie a la pestaña "Rutas", donde el usuario elige si lo usa
  /// como destino (ruta B, saliendo desde su ubicación actual) o como
  /// punto de partida (ruta A, escribiendo el destino a mano).
  void _handleMapTap(LatLng point) {
    if (widget.onMapPointMarked == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Punto marcado. Elegí cómo usarlo en tu ruta.'),
        duration: Duration(seconds: 2),
      ),
    );
    widget.onMapPointMarked!(point);
  }

  /// Mantener presionado el mapa: solo los usuarios admin pueden crear un
  /// reporte en cualquier punto (no hace falta estar parado ahí). Para el
  /// resto de los usuarios (incluidos invitados) el gesto no hace nada,
  /// para no pisar el uso normal del mapa (arrastrar/zoom).
  void _handleMapLongPress(LatLng point) {
    if (widget.isGuest || widget.userId == null) return;
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAdmin) return;
    _handleCreateReport(point);
  }

  Future<void> _handleCreateReport(LatLng position) async {
    if (widget.isGuest) {
      _handleGuestMark(position);
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          position: position,
          userId: widget.userId!,
        ),
      ),
    );
    if (created == true) {
      await _loadNearbyReports();
    }
  }

  /// Un invitado puede marcar una ubicación en el mapa a modo de
  /// referencia personal, pero esa marca nunca se envía como reporte.
  void _handleGuestMark(LatLng position) {
    setState(() => _guestMarker = position);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ubicación marcada. Como invitado no podés crear reportes: '
          'iniciá sesión para reportar.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleEditReport(ReportPoint report) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          position: LatLng(report.latitude, report.longitude),
          userId: widget.userId!,
          existingReport: report,
        ),
      ),
    );
    if (updated == true) {
      await _loadNearbyReports();
    }
  }

  Future<void> _handleDeleteReport(ReportPoint report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: Text('¿Seguro que querés eliminar "${report.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _reportService.deleteReport(report.id);
      if (mounted) Navigator.of(context).pop(); // cierra el bottom sheet
      await _loadNearbyReports();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  void _showReportDetails(ReportPoint report) {
    final authProvider = context.read<AuthProvider>();
    final isOwnReport = !widget.isGuest && report.userId == widget.userId;
    final canManage = !widget.isGuest &&
        (authProvider.isAdmin || report.userId == widget.userId);
    final authorLabel =
        isOwnReport ? 'Mi reporte' : (report.username ?? 'Usuario');

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(label: Text(report.category)),
                const SizedBox(width: 8),
                Icon(Icons.person_outline,
                    size: 16, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  authorLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight:
                            isOwnReport ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.description.isNotEmpty) Text(report.description),
            const SizedBox(height: 12),
            Text(
              'Creado: ${report.createdAt.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (canManage) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(); // cierra el bottom sheet
                        _handleEditReport(report);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleDeleteReport(report),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    final channel = _reportsChannel;
    if (channel != null) {
      _reportService.unsubscribe(channel);
    }
    super.dispose();
  }

  void _recenter() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 15);
    }
  }

  void _showSosInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Necesitás ayuda?'),
        content: const Text(
          'Ante una emergencia, comunicate con los servicios de '
          'emergencia de tu zona (por ejemplo, 911 en Argentina).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showMapTypeSheet() {
    final mapLayerProvider = context.read<MapLayerProvider>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tipo de mapa', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.standard,
                icon: Icons.map_outlined,
                label: 'Estándar',
                subtitle: 'Con modo claro y oscuro',
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.terrain,
                icon: Icons.terrain,
                label: 'Relieve',
                subtitle: 'Con modo claro y oscuro',
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.satellite,
                icon: Icons.satellite_alt,
                label: 'Satélite',
                subtitle: 'Misma imagen siempre',
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapTypeTile({
    required BuildContext sheetContext,
    required MapLayerProvider provider,
    required MapLayerType type,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final selected = provider.mapType == type;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      selected: selected,
      onTap: () {
        provider.setMapType(type);
        Navigator.of(sheetContext).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBody(),
          if (!_isLoading && _errorMessage == null) ...[
            _buildTopBar(context),
            _buildSosButton(context),
            _buildRightButtons(context),
            _buildReportButton(context),
          ],
        ],
      ),
    );
  }

  /// Barra de búsqueda flotante centrada arriba del mapa, al estilo
  /// Google Maps, con el avatar de la cuenta a la derecha.
  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(28),
                color: Theme.of(context).colorScheme.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: widget.onSearchTap,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.search),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Buscar una dirección o ruta',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              elevation: 3,
              shape: const CircleBorder(),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosButton(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: FloatingActionButton(
        heroTag: 'sos',
        backgroundColor: Colors.red,
        onPressed: _showSosInfo,
        child: const Icon(Icons.sos, color: Colors.white),
      ),
    );
  }

  Widget _buildRightButtons(BuildContext context) {
    final mapType = context.watch<MapLayerProvider>().mapType;
    final layersIcon = switch (mapType) {
      MapLayerType.standard => Icons.layers_outlined,
      MapLayerType.terrain => Icons.terrain,
      MapLayerType.satellite => Icons.satellite_alt,
    };
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'layers',
            tooltip: 'Tipo de mapa',
            onPressed: _showMapTypeSheet,
            child: Icon(layersIcon),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'recenter',
            onPressed: _currentPosition == null ? null : _recenter,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  Widget _buildReportButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(28),
          color: colorScheme.primary,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: _currentPosition == null
                ? null
                : () => _handleCreateReport(_currentPosition!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isGuest ? Icons.push_pin_outlined : Icons.add_location_alt,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isGuest ? 'Marcar' : 'Reportar',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initLocationAndReports,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mapType = context.watch<MapLayerProvider>().mapType;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition!,
        initialZoom: 15,
        onTap: (tapPosition, point) => _handleMapTap(point),
        onLongPress: (tapPosition, point) => _handleMapLongPress(point),
      ),
      children: [
        buildMapTileLayer(mapType: mapType, isDark: isDark),
        // Círculo visual de ${ProximityConfig.alertRadiusMeters}m alrededor
        // del usuario: es el radio dentro del cual un reporte nuevo dispara
        // una notificación.
        CircleLayer(
          circles: [
            CircleMarker(
              point: _currentPosition!,
              radius: ProximityConfig.alertRadiusMeters,
              useRadiusInMeter: true,
              color: Colors.blue.withValues(alpha: 0.12),
              borderColor: Colors.blue.withValues(alpha: 0.5),
              borderStrokeWidth: 2,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            // Marcador de mi ubicación actual
            Marker(
              point: _currentPosition!,
              width: 24,
              height: 24,
              child: const Icon(Icons.circle, color: Colors.blue, size: 18),
            ),
            // Marcadores de los puntos de reporte
            ..._reports.map(
              (report) => Marker(
                point: LatLng(report.latitude, report.longitude),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => _showReportDetails(report),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
              ),
            ),
            // Marca personal del invitado (no se envía como reporte).
            if (_guestMarker != null)
              Marker(
                point: _guestMarker!,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => setState(() => _guestMarker = null),
                  child: const Icon(
                    Icons.push_pin,
                    color: Colors.orange,
                    size: 34,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
