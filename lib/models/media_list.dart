class MediaListEntry {
  MediaListEntry(Map<String, dynamic> data)
    : key = data['key'] as String,
      title = data['title'] as String? ?? '動画',
      url = data['url'] as String? ?? '',
      index = (data['index'] as num? ?? 0).toInt(),
      duration = (data['duration'] as num?)?.toDouble(),
      available = data['available'] as bool? ?? false,
      reason = data['reason'] as String? ?? '';
  final String key;
  final String title;
  final String url;
  final int index;
  final double? duration;
  final bool available;
  final String reason;
  String get durationLabel {
    if (duration == null) return '';
    final seconds = duration!.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class MediaListPage {
  MediaListPage(Map<String, dynamic> data)
    : isList = data['kind'] == 'playlist',
      title = data['title'] as String? ?? '動画リスト',
      entries = ((data['entries'] as List?) ?? [])
          .map((item) => MediaListEntry(Map<String, dynamic>.from(item as Map)))
          .toList(),
      hasMore = data['hasMore'] as bool? ?? false,
      nextOffset = (data['nextOffset'] as num? ?? 0).toInt(),
      total = (data['total'] as num?)?.toInt(),
      maximum = (data['maximum'] as num? ?? 1000).toInt(),
      singleInfo = data;
  final bool isList;
  final String title;
  final List<MediaListEntry> entries;
  final bool hasMore;
  final int nextOffset;
  final int? total;
  final int maximum;
  final Map<String, dynamic> singleInfo;
}
