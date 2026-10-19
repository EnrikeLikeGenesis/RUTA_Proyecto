import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position?> getLastKnownPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getLastKnownPosition();
  }

  /// Pide permisos si hace falta y devuelve la posición actual.
  /// Lanza una excepción con un mensaje claro si algo falla.
  Future<Position> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 20),
    bool isEnglish = false,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        isEnglish
            ? 'GPS is turned off. Turn it on to continue.'
            : 'El GPS está desactivado. Activalo para continuar.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          isEnglish
              ? 'Location permission denied.'
              : 'Permiso de ubicación denegado.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        isEnglish
            ? 'Location permission permanently denied. Enable it in your phone settings.'
            : 'Permiso de ubicación denegado permanentemente. Habilitalo desde los ajustes del teléfono.',
      );
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
  }

  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metros
      ),
    );
  }
}
