import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../models/report_point.dart';
import '../../services/report_service.dart';

/// Paginated community feed to avoid downloading every report at once.
class ComunidadScreen extends StatefulWidget {
  final String? currentUserId;

  const ComunidadScreen({super.key, this.currentUserId});

  @override
  State<ComunidadScreen> createState() => _ComunidadScreenState();
}

class _ComunidadScreenState extends State<ComunidadScreen> {
  static const _pageSize = 30;

  final _reportService = ReportService();
  final _scrollController = ScrollController();
  final List<ReportPoint> _reports = [];
  bool _isLoading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 500) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage({bool refresh = false}) async {
    if (_isLoading || (!refresh && !_hasMore)) return;
    final offset = refresh ? 0 : _reports.length;
    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _reports.clear();
        _hasMore = true;
      }
    });

    try {
      final page = await _reportService.getAllReports(
        offset: offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _reports.addAll(page);
        _hasMore = page.length == _pageSize;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
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

  void _showReportDetails(ReportPoint report) {
    final isOwnReport =
        widget.currentUserId != null && report.userId == widget.currentUserId;
    final author = isOwnReport
        ? appText(context, 'Mi reporte', 'My report')
        : (report.username ?? appText(context, 'Usuario', 'User'));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              report.title,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(_iconForCategory(report.category), size: 18),
                  label: Text(reportCategoryText(context, report.category)),
                ),
                Text(
                  author,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
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
                  height: 240,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    alignment: Alignment.center,
                    color: Theme.of(sheetContext)
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
            Text(
              report.description.isNotEmpty
                  ? report.description
                  : appText(context, 'Sin descripción', 'No description'),
            ),
            const SizedBox(height: 12),
            Text(
              '${appText(context, 'Creado', 'Created')}: '
              '${report.createdAt.toLocal()}',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFooter =
        _reports.isEmpty || _isLoading || _error != null || _hasMore;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'Comunidad', 'Community')),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadNextPage(refresh: true),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: _reports.length + (showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _reports.length) {
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        isEnglish
                            ? 'Could not load reports: $_error'
                            : 'No se pudieron cargar los reportes: $_error',
                      ),
                      TextButton(
                        onPressed: _loadNextPage,
                        child: Text(appText(context, 'Reintentar', 'Retry')),
                      ),
                    ],
                  ),
                );
              }
              if (_isLoading) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (_reports.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(60),
                  child: Center(
                    child: Text(
                      appText(
                        context,
                        'Todavía no hay reportes de la comunidad.',
                        'There are no community reports yet.',
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            final report = _reports[index];
            final isOwnReport =
                widget.currentUserId != null &&
                report.userId == widget.currentUserId;
            final authorLabel = isOwnReport
                ? appText(context, 'Mi reporte', 'My report')
                : (report.username ?? appText(context, 'Usuario', 'User'));
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => _showReportDetails(report),
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
                            : reportCategoryText(context, report.category),
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
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }
}
