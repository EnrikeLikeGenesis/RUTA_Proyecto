class ReportPoint {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String category;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String? imageUrl;

  /// Nombre de usuario de quien creó el reporte (viene de la tabla
  /// "profiles" a través del join en ReportService). Puede ser null si
  /// el perfil no se pudo cargar.
  final String? username;

  ReportPoint({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.imageUrl,
    this.username,
  });

  factory ReportPoint.fromMap(Map<String, dynamic> map) {
    // Cuando el select viene con el join "profiles(username)", Supabase
    // devuelve el perfil relacionado como un mapa anidado bajo 'profiles'.
    final profile = map['profiles'] as Map<String, dynamic>?;

    return ReportPoint(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? 'general',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      imageUrl: map['image_url'] as String?,
      username: profile?['username'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'title': title,
      'description': description,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'image_url': imageUrl,
    };
  }
}
