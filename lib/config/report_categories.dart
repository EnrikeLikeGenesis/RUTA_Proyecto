class ReportCategory {
  const ReportCategory({
    required this.value,
    required this.label,
    required this.markerAsset,
  });

  final String value;
  final String label;
  final String markerAsset;
}

const reportCategories = <ReportCategory>[
  ReportCategory(
    value: 'baches',
    label: 'Baches',
    markerAsset: 'assets/01_baches.png',
  ),
  ReportCategory(
    value: 'obras',
    label: 'Obras',
    markerAsset: 'assets/02_obras.png',
  ),
  ReportCategory(
    value: 'transito',
    label: 'Tránsito',
    markerAsset: 'assets/03_transito.png',
  ),
  ReportCategory(
    value: 'zonas_inseguras',
    label: 'Zonas inseguras',
    markerAsset: 'assets/04_zonas_inseguras.png',
  ),
  ReportCategory(
    value: 'accidentes',
    label: 'Accidentes',
    markerAsset: 'assets/05_accidentes.png',
  ),
  ReportCategory(
    value: 'inundaciones',
    label: 'Inundaciones',
    markerAsset: 'assets/06_inundaciones.png',
  ),
];

ReportCategory? reportCategoryFor(String value) {
  for (final category in reportCategories) {
    if (category.value == value) return category;
  }
  return null;
}
