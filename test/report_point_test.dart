import 'package:flutter_test/flutter_test.dart';
import 'package:prueba_flutter/models/report_point.dart';

void main() {
  group('ReportPoint image', () {
    test('reads image URL from a Supabase row', () {
      final report = ReportPoint.fromMap({
        'id': 'report-id',
        'user_id': 'user-id',
        'title': 'Bache',
        'description': '',
        'category': 'baches',
        'latitude': 0,
        'longitude': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
        'image_url': 'https://example.com/report.jpg',
      });

      expect(report.imageUrl, 'https://example.com/report.jpg');
    });

    test('includes image URL when creating a Supabase row', () {
      final report = ReportPoint(
        id: 'report-id',
        userId: 'user-id',
        title: 'Bache',
        description: '',
        category: 'baches',
        latitude: 0,
        longitude: 0,
        createdAt: DateTime.utc(2026),
        imageUrl: 'https://example.com/report.jpg',
      );

      expect(report.toInsertMap()['image_url'], report.imageUrl);
    });
  });
}
