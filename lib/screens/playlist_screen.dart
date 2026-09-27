import 'package:flutter/material.dart';

import '../models/download.dart';
import '../models/media_list.dart';
import '../services/app_controller.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.controller,
    required this.url,
    required this.initialPage,
    required this.options,
  });
  final AppController controller;
  final String url;
  final MediaListPage initialPage;
  final DownloadOptions options;
  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final List<MediaListEntry> _entries = [...widget.initialPage.entries];
  final Set<String> _selected = {};
  late MediaListPage _page = widget.initialPage;
  bool _loading = false;
  String? _error;
  List<MediaListEntry> get _chosen => _entries
      .where((entry) => entry.available && _selected.contains(entry.key))
      .toList();

  Future<void> _loadNext() async {
    final next = await widget.controller.inspectCollection(
      widget.url,
      offset: _page.nextOffset,
    );
    if (!mounted) return;
    if (next.nextOffset <= _page.nextOffset) {
      throw const FormatException('リストの続きを取得できません。');
    }
    final existing = _entries.map((entry) => entry.key).toSet();
    setState(() {
      _entries.addAll(next.entries.where((entry) => existing.add(entry.key)));
      _page = next;
    });
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadNext();
    } catch (e) {
      if (mounted) setState(() => _error = AppController.readableError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectAll() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 全選択では続きを取得してから選択する。ミックスも明示した取得上限で停止する。
      while (mounted && _page.hasMore) {
        await _loadNext();
      }
      if (mounted) {
        setState(
          () => _selected.addAll(
            _entries
                .where((entry) => entry.available)
                .map((entry) => entry.key),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = AppController.readableError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_chosen.isEmpty || _loading || widget.controller.busy) return;
    final entries = _chosen;
    await widget.controller.downloadMany(entries, widget.options);
    if (!mounted) return;
    if (widget.controller.error == null) {
      Navigator.pop(context, entries.length);
    } else {
      setState(() => _error = widget.controller.error);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final blocked = _loading || widget.controller.busy;
      return Scaffold(
        appBar: AppBar(
          title: const Text('保存する動画を選択', style: TextStyle(fontSize: 18)),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.initialPage.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_entries.length}件取得済み${_page.total == null ? '' : ' / 全${_page.total}件'} · ${_chosen.length}件選択',
                    key: const Key('playlistSelectionCount'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '取得上限 ${_page.maximum}件・${widget.options.mode.label}で保存',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        key: const Key('playlistSelectAll'),
                        onPressed: blocked ? null : _selectAll,
                        icon: const Icon(Icons.check_box_outlined, size: 18),
                        label: const Text('全選択'),
                      ),
                      TextButton.icon(
                        key: const Key('playlistClearAll'),
                        onPressed: blocked
                            ? null
                            : () => setState(_selected.clear),
                        icon: const Icon(
                          Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        label: const Text('全解除'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length + (_page.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _entries.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton(
                        onPressed: blocked ? null : _loadMore,
                        child: const Text('さらに読み込む'),
                      ),
                    );
                  }
                  final entry = _entries[index];
                  final selected = _selected.contains(entry.key);
                  return CheckboxListTile(
                    key: ValueKey('playlistEntry:${entry.key}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected,
                    selected: selected,
                    selectedTileColor: colors.primary.withValues(alpha: 0.06),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      entry.available
                          ? '${entry.index}番目${entry.durationLabel.isEmpty ? '' : ' · ${entry.durationLabel}'}'
                          : entry.reason,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    onChanged: blocked || !entry.available
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              _selected.add(entry.key);
                            } else {
                              _selected.remove(entry.key);
                            }
                          }),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('playlistSaveSelected'),
                onPressed: blocked || _chosen.isEmpty ? null : _save,
                icon: const Icon(Icons.download),
                label: Text(
                  widget.controller.busy ? '登録中…' : '選択した${_chosen.length}件を保存',
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
