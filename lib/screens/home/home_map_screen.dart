import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/proximity_config.dart';
import '../../config/report_categories.dart';
import '../../l10n/app_text.dart';
import '../../models/report_point.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_layer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/report_service.dart';
import '../../widgets/map_tile_layer.dart';
import '../../widgets/user_avatar_button.dart';
import '../report/create_report_screen.dart';

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
  final void Function(LatLng point, bool asDestination)? onMapPointMarked;

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
  static const LatLng _defaultMapCenter = LatLng(-34.6037, -58.3816);

  final LocationService _locationService = LocationService();
  final ReportService _reportService = ReportService();
  final MapController _mapController = MapController();

  LatLng? _currentPosition;
  LatLng _mapCenter = _defaultMapCenter;
  List<ReportPoint> _reports = [];
  bool _mapReady = false;
  bool _isLoading = true;
  String? _locationErrorMessage;
  String? _reportsErrorMessage;
  int _reportRequestGeneration = 0;

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
      if (mounted && context.read<ThemeProvider>().communityNotifications) {
      final isEnglish =
          Localizations.localeOf(context).languageCode == 'en';
      NotificationService.instance.showNearbyReportNotification(
        title: isEnglish
            ? 'A report was created near you'
            : 'Se creó un reporte cerca tuyo',
        body: isEnglish
            ? '${report.title} · ${distanceInMeters.round()} m from your location'
            : '${report.title} · a ${distanceInMeters.round()} m de tu ubicación',
        isEnglish: isEnglish,
      );
      }
      _loadNearbyReports();
    }
  }

  Future<void> _initLocationAndReports() async {
    setState(() {
      _isLoading = true;
      _locationErrorMessage = null;
      _reportsErrorMessage = null;
    });
    try {
      final lastKnownPosition = await _locationService.getLastKnownPosition();
      if (lastKnownPosition != null && mounted) {
        final cachedPosition = LatLng(
          lastKnownPosition.latitude,
          lastKnownPosition.longitude,
        );
        setState(() {
          _currentPosition = cachedPosition;
          _mapCenter = cachedPosition;
          _isLoading = false;
        });
        if (_mapReady) _mapController.move(cachedPosition, 15);
        unawaited(_loadNearbyReports());
      }

      final position = await _locationService.getCurrentPosition(
        accuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
        isEnglish: Localizations.localeOf(context).languageCode == 'en',
      );
      final currentPosition = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      final shouldReloadReports =
          _currentPosition == null ||
          Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                currentPosition.latitude,
                currentPosition.longitude,
              ) >
              250;
      setState(() {
        _currentPosition = currentPosition;
        _mapCenter = currentPosition;
      });
      if (_mapReady) _mapController.move(currentPosition, 15);
      if (shouldReloadReports) unawaited(_loadNearbyReports());
    } catch (e) {
      if (mounted) setState(() => _locationErrorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNearbyReports() async {
    if (_currentPosition == null) return;
    final generation = ++_reportRequestGeneration;
    final position = _currentPosition!;
    try {
      final reports = await _reportService.getNearbyReports(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted || generation != _reportRequestGeneration) return;
      setState(() {
        _reports = reports;
        _reportsErrorMessage = null;
      });
    } catch (e) {
      if (mounted && generation == _reportRequestGeneration) {
        setState(() => _reportsErrorMessage = e.toString());
      }
    }
  }

  Future<void> _handleMapTap(LatLng point) async {
    final isWithinProximity =
        _currentPosition != null &&
        Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              point.latitude,
              point.longitude,
            ) <=
            ProximityConfig.alertRadiusMeters;
    final canCreateReport =
        isWithinProximity && !widget.isGuest && widget.userId != null;

    final action = await showModalBottomSheet<_MapPointAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCreateReport)
              ListTile(
                leading: const Icon(Icons.add_location_alt),
                title: Text(appText(context, 'Crear reporte', 'Create report')),
                onTap: () =>
                    Navigator.of(sheetContext)
                        .pop(_MapPointAction.createReport),
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                appText(context, 'Como punto de destino', 'Set as destination'),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MapPointAction.destination),
            ),
            ListTile(
              leading: const Icon(Icons.trip_origin),
              title: Text(
                appText(context, 'Como punto de partida', 'Set as starting point'),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MapPointAction.origin),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _MapPointAction.createReport:
        await _handleCreateReport(point);
      case _MapPointAction.destination:
        widget.onMapPointMarked?.call(point, true);
      case _MapPointAction.origin:
        widget.onMapPointMarked?.call(point, false);
    }
  }

  Future<void> _handleCreateReport(LatLng position) async {
    if (widget.isGuest) {
      _handleGuestMark(position);
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CreateReportScreen(position: position, userId: widget.userId!),
      ),
    );
    if (created == true) {
      await _loadNearbyReports();
    }
  }

  /// Un invitado puede marcar una ubicación en el mapa a modo de
  /// referencia personal, pero esa marca nunca se envía como reporte.
  void _handleGuestMark(LatLng position) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    setState(() => _guestMarker = position);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEnglish
              ? 'Location marked. Guests cannot create reports; sign in to report.'
              : 'Ubicación marcada. Como invitado no podés crear reportes: '
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
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(appText(context, 'Eliminar reporte', 'Delete report')),
        content: Text(
          isEnglish
              ? 'Are you sure you want to delete "${report.title}"?'
              : '¿Seguro que querés eliminar "${report.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appText(context, 'Cancelar', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appText(context, 'Eliminar', 'Delete')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(
              SnackBar(
                content: Text(
                  isEnglish ? 'Could not delete: $e' : 'Error al eliminar: $e',
                ),
              ),
            );
      }
    }
  }

  void _showReportDetails(ReportPoint report) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final authProvider = context.read<AuthProvider>();
    final isOwnReport = !widget.isGuest && report.userId == widget.userId;
    final canManage =
        !widget.isGuest &&
        (authProvider.isAdmin || report.userId == widget.userId);
    final authorLabel = isOwnReport
        ? appText(context, 'Mi reporte', 'My report')
        : (report.username ?? appText(context, 'Usuario', 'User'));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  Chip(label: Text(reportCategoryText(context, report.category))),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
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
              if (report.imageUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    report.imageUrl!,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (_, _, _) => Container(
                      height: 220,
                      alignment: Alignment.center,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Text(
                        appText(
                          context,
                          'No se pudo cargar la imagen',
                          'Could not load image',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (report.description.isNotEmpty) Text(report.description),
              const SizedBox(height: 12),
              Text(
                '${isEnglish ? 'Created' : 'Creado'}: ${report.createdAt.toLocal()}',
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
                        label: Text(appText(context, 'Editar', 'Edit')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _handleDeleteReport(report),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.delete),
                        label: Text(appText(context, 'Eliminar', 'Delete')),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(appText(context, '¿Necesitás ayuda?', 'Need help?')),
        content: Text(
          isEnglish
              ? 'In an emergency, contact your local emergency services.'
              : 'Ante una emergencia, comunicate con los servicios de '
                  'emergencia de tu zona (por ejemplo, 911 en Argentina).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(context, 'Entendido', 'Got it')),
          ),
        ],
      ),
    );
  }

  void _showMapTypeSheet() {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final mapLayerProvider = context.read<MapLayerProvider>();
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isEnglish ? 'Map type' : 'Tipo de mapa',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.standard,
                icon: Icons.map_outlined,
                label: isEnglish ? 'Standard' : 'Estándar',
                subtitle: isEnglish
                    ? 'With light and dark mode'
                    : 'Con modo claro y oscuro',
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.terrain,
                icon: Icons.terrain,
                label: isEnglish ? 'Terrain' : 'Relieve',
                subtitle: isEnglish
                    ? 'With light and dark mode'
                    : 'Con modo claro y oscuro',
              ),
              _buildMapTypeTile(
                sheetContext: sheetContext,
                provider: mapLayerProvider,
                type: MapLayerType.satellite,
                icon: Icons.satellite_alt,
                label: isEnglish ? 'Satellite' : 'Satélite',
                subtitle: isEnglish ? 'Same imagery always' : 'Misma imagen siempre',
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

  Widget _reportMarker(String category) {
    final reportCategory = reportCategoryFor(category);
    if (reportCategory == null) {
      return const Icon(Icons.location_on, color: Colors.red, size: 36);
    }

    return Image.asset(
      reportCategory.markerAsset,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBody(),
          _buildTopBar(context),
          _buildSosButton(context),
          _buildRightButtons(context),
          _buildReportButton(context),
          if (_locationErrorMessage != null || _reportsErrorMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 76,
              child: _buildLoadErrorCard(),
            ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorCard() {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final locationFailed = _locationErrorMessage != null;
    final message = locationFailed
        ? (isEnglish
              ? 'Could not get your location. The map is available; move it or retry.'
              : 'No se pudo obtener tu ubicación. El mapa sigue disponible; '
                    'podés moverlo o volver a intentar.')
        : (isEnglish
              ? 'Could not load nearby reports.'
              : 'No se pudieron cargar los reportes cercanos.');
    final errorDetails =
        _locationErrorMessage != null
        ? appErrorText(context, _locationErrorMessage!)
        : _reportsErrorMessage != null
        ? appErrorText(context, _reportsErrorMessage!)
        : (isEnglish ? 'Unknown error' : 'Error desconocido');

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  Text(
                    errorDetails,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: locationFailed
                  ? _initLocationAndReports
                  : _loadNearbyReports,
              child: Text(appText(context, 'Reintentar', 'Retry')),
            ),
          ],
        ),
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
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.search),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            appText(
                              context,
                              'Buscar una dirección o ruta',
                              'Search for an address or route',
                            ),
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
            const UserAvatarButton(),
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
            tooltip: appText(context, 'Tipo de mapa', 'Map type'),
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
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
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
                    widget.isGuest
                        ? Icons.push_pin_outlined
                        : Icons.add_location_alt,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isGuest
                        ? (isEnglish ? 'Mark location' : 'Marcar')
                        : (isEnglish ? 'Report' : 'Reportar'),
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
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mapType = context.watch<MapLayerProvider>().mapType;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: _currentPosition == null ? 5 : 15,
        onMapReady: () {
          _mapReady = true;
          if (_currentPosition != null) {
            _mapController.move(_currentPosition!, 15);
          }
        },
        onTap: (tapPosition, point) {
          _handleMapTap(point);
        },
      ),
      children: [
        buildMapTileLayer(mapType: mapType, isDark: isDark),
        // Círculo visual de ${ProximityConfig.alertRadiusMeters}m alrededor
        // del usuario: es el radio dentro del cual un reporte nuevo dispara
        // una notificación.
        if (_currentPosition != null)
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
            if (_currentPosition != null)
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
                  child: _reportMarker(report.category),
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

enum _MapPointAction { createReport, destination, origin }
