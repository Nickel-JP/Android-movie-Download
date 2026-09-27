import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/download.dart';
import '../models/media_list.dart';
import '../services/app_controller.dart';
import '../services/app_navigation.dart';
import '../services/app_updater.dart';
import 'playlist_screen.dart';
import 'share_download_dialog.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  final _url = TextEditingController();
  int _page = 0;
  SaveMode _mode = SaveMode.video;
  int _height = 2160;
  int _fps = 60;
  int _bitrate = 320;
  String _container = 'mp4';
  bool _updating = false;
  double? _updateProgress;
  String? _updateMessage;
  int _lastShareRevision = -1;
  bool _shareScheduled = false;
  bool _shareDialogOpen = false;
  String _historyFilter = 'all';
  Map<String, dynamic>? _info;
  late final AppUpdater _updater = AppUpdater(widget.controller.bridge);
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_receiveShare);
    _url.addListener(_inputChanged);
    _receiveShare();
  }

  void _inputChanged() {
    if (mounted) setState(() => _info = null);
  }

  void _receiveShare() {
    if (!mounted ||
        _shareScheduled ||
        _shareDialogOpen ||
        !controller.ready ||
        controller.busy ||
        _updating ||
        controller.sharedUrl == null ||
        controller.sharedUrlRevision == _lastShareRevision) {
      return;
    }
    _shareScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareScheduled = false;
      if (mounted) _confirmSharedDownload();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() => _receiveShare();

  Future<void> _confirmSharedDownload() async {
    if (_shareDialogOpen ||
        !controller.ready ||
        controller.busy ||
        _updating ||
        ModalRoute.of(context)?.isCurrent != true ||
        controller.sharedUrl == null ||
        controller.sharedUrlRevision == _lastShareRevision) {
      return;
    }
    _shareDialogOpen = true;
    final revision = controller.sharedUrlRevision;
    _lastShareRevision = revision;
    final text = controller.sharedUrl!;
    try {
      final url = normalizeVideoUrl(text);
      final options = _options;
      _url.text = url;
      setState(() {
        _page = 0;
        _info = null;
      });
      FocusManager.instance.primaryFocus?.unfocus();
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => ShareDownloadDialog(url: url, options: options),
      );
      if (!mounted || revision != controller.sharedUrlRevision) return;
      await controller.consumeShare(revision);
      if (approved == true && mounted) {
        await _download(url: url, options: options);
      }
    } catch (e) {
      if (mounted) {
        _toast(AppController.readableError(e));
        if (controller.sharedUrl != null) {
          await controller.run(() => controller.consumeShare(revision));
        }
      }
    } finally {
      _shareDialogOpen = false;
      if (mounted) _receiveShare();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.run(controller.refresh);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_receiveShare);
    _url.removeListener(_inputChanged);
    _url.dispose();
    _updater.close();
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  DownloadOptions get _options => DownloadOptions(
    mode: _mode,
    height: _height,
    fps: _fps,
    bitrate: _bitrate,
    container: _container,
  );

  Future<void> _openList(String url, MediaListPage page) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final count = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(
          controller: controller,
          url: url,
          initialPage: page,
          options: _options,
        ),
      ),
    );
    if (count != null && mounted) {
      setState(() => _page = 1);
      _toast('$count件のダウンロードを追加しました');
    }
  }

  Future<void> _inspect() async {
    String? url;
    MediaListPage? result;
    await controller.run(() async {
      url = normalizeVideoUrl(_url.text);
      result = await controller.inspectCollection(url!);
    });
    if (result == null || url == null || !mounted) return;
    if (mounted) {
      try {
        if (normalizeVideoUrl(_url.text) == url) {
          if (result!.isList) {
            await _openList(url!, result!);
          } else {
            setState(() => _info = result!.singleInfo);
          }
        }
      } on FormatException {
        // 取得中に入力が変更された場合、古い動画情報を表示しない。
      }
    }
  }

  Future<void> _download({String? url, DownloadOptions? options}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    String? sourceUrl;
    MediaListPage? inspected;
    await controller.run(() async {
      sourceUrl = normalizeVideoUrl(url ?? _url.text);
      if (_info == null) {
        inspected = await controller.inspectCollection(sourceUrl!);
      }
    });
    if (controller.error != null || sourceUrl == null || !mounted) return;
    if (inspected?.isList == true) {
      await _openList(sourceUrl!, inspected!);
      return;
    }
    await controller.download(sourceUrl!, options ?? _options);
    if (mounted && controller.error == null) {
      setState(() => _page = 1);
      _toast('ダウンロードを追加しました');
    }
  }

  Future<void> _checkUpdate() async {
    if (_updating ||
        controller.busy ||
        controller.tasks.any((task) => task.active)) {
      return;
    }
    setState(() {
      _updating = true;
      _updateMessage = '最新版を確認しています…';
    });
    try {
      final release = await _updater.check(
        controller.repository,
        controller.versionCode,
      );
      if (!mounted) return;
      if (release == null) {
        setState(() => _updateMessage = 'アプリは最新版です');
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => UpdateDialog(
          release: release,
          currentVersion: controller.appVersion,
        ),
      );
      if (approved != true || !mounted) return;
      setState(() {
        _updateMessage = '更新をダウンロードしています…';
        _updateProgress = 0;
      });
      final path = await _updater.download(release, (progress) {
        if (mounted) setState(() => _updateProgress = progress);
      });
      final result = await controller.bridge.call<String>('installUpdate', {
        'path': path,
        'versionCode': release.versionCode,
      });
      if (mounted) {
        setState(() => _updateMessage = result ?? 'インストール確認画面を開きました');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updateMessage = AppController.readableError(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _updateProgress = null;
        });
        _receiveShare();
      }
    }
  }

  Future<void> _engineUpdate() => controller.run(() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('yt-dlpを更新'),
        content: const Text('公式の最新版を確認してダウンロードします。アプリの再インストールは不要です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認・更新'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final result = await controller.bridge.call<String>('updateEngine');
    await controller.refresh();
    _toast(result ?? 'yt-dlpを更新しました');
  });

  ColorScheme get _colors => Theme.of(context).colorScheme;
  Color get _muted => _colors.onSurfaceVariant;
  bool get _canUse => controller.ready && !controller.busy && !_updating;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xff285be0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Movie Download',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '設定',
            onPressed: () => setState(() => _page = 2),
            icon: const Icon(Icons.settings_outlined, size: 22),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                if (controller.error != null)
                  _notice(controller.error!, isError: true),
                if (!controller.ready) _notice('ダウンロードの準備中です…'),
                if (_page == 0) ..._downloadPage(),
                if (_page == 1) ..._historyPage(),
                if (_page == 2) ..._settingsPage(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    ),
  );

  Widget _bottomBar() => Container(
    decoration: BoxDecoration(
      color: _colors.surface,
      border: Border(top: BorderSide(color: _colors.outlineVariant)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_page == 0)
          SafeArea(
            top: false,
            bottom: MediaQuery.viewInsetsOf(context).bottom > 0,
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      key: const Key('startDownload'),
                      onPressed: _canUse && _url.text.trim().isNotEmpty
                          ? _download
                          : null,
                      icon: const Icon(Icons.download_rounded, size: 22),
                      label: Text(
                        controller.busy ? '処理中…' : 'ダウンロードを開始',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (MediaQuery.viewInsetsOf(context).bottom == 0)
          NavigationBar(
            selectedIndex: _page,
            onDestinationSelected: (index) {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _page = index);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.add_link),
                label: '新規',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: controller.tasks.any((task) => task.active),
                  label: Text(
                    '${controller.tasks.where((task) => task.active).length}',
                  ),
                  child: const Icon(Icons.download_outlined),
                ),
                label: '履歴',
              ),
              const NavigationDestination(icon: Icon(Icons.tune), label: '設定'),
            ],
          ),
      ],
    ),
  );

  List<Widget> _downloadPage() => [
    const Text(
      '新しいダウンロード',
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 6),
    Text('yt-dlp対応サイトの動画・音声', style: TextStyle(color: _muted, fontSize: 13)),
    const SizedBox(height: 24),
    Row(
      children: [
        const Expanded(
          child: Text(
            '動画のURL',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          onPressed: _updating ? null : _paste,
          icon: const Icon(Icons.content_paste_outlined, size: 17),
          label: const Text('貼り付け'),
        ),
      ],
    ),
    TextField(
      key: const Key('videoUrl'),
      controller: _url,
      maxLines: 2,
      minLines: 1,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: '動画・音声のURLを入力',
        suffixIcon: _url.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'URLを消去',
                icon: const Icon(Icons.close, size: 19),
                onPressed: _url.clear,
              ),
      ),
    ),
    const SizedBox(height: 6),
    Row(
      children: [
        Expanded(
          child: Text(
            _info == null ? '共有メニューからも追加できます' : '動画情報を取得しました',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        TextButton(
          onPressed: _canUse && _url.text.trim().isNotEmpty ? _inspect : null,
          child: const Text('URL・リストを確認'),
        ),
      ],
    ),
    if (_info != null) ...[
      const SizedBox(height: 8),
      _panel(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.ondemand_video, color: _colors.primary, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _info!['title'] as String? ?? '動画',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _info!['quality'] as String? ?? '',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    const SizedBox(height: 24),
    const Text(
      '保存形式',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    SizedBox(
      width: double.infinity,
      child: SegmentedButton<SaveMode>(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        showSelectedIcon: false,
        segments: SaveMode.values
            .map(
              (mode) => ButtonSegment(
                value: mode,
                icon: Icon(
                  mode == SaveMode.video
                      ? Icons.videocam_outlined
                      : Icons.music_note_outlined,
                  size: 18,
                ),
                label: Text(mode.label),
              ),
            )
            .toList(),
        selected: {_mode},
        onSelectionChanged: _updating
            ? null
            : (selection) => setState(() => _mode = selection.single),
      ),
    ),
    const SizedBox(height: 16),
    _panel(
      Column(
        children: [
          if (_mode == SaveMode.video) ...[
            _selectionRow<int>('画質', _height, {
              2160: '4K（2160p）',
              1440: '1440p',
              1080: '1080p',
              720: '720p',
              480: '480p',
            }, (value) => setState(() => _height = value)),
            const Divider(indent: 16, endIndent: 16),
            _selectionRow<int>('フレームレート', _fps, {
              60: '60fps',
              30: '30fps',
            }, (value) => setState(() => _fps = value)),
            const Divider(indent: 16, endIndent: 16),
            _selectionRow<String>('ファイル形式', _container, {
              'mp4': 'MP4',
              'mkv': 'MKV',
            }, (value) => setState(() => _container = value)),
          ],
          if (_mode == SaveMode.mp3)
            _selectionRow<int>('音質', _bitrate, {
              320: '320 kbps',
              256: '256 kbps',
              192: '192 kbps',
              128: '128 kbps',
            }, (value) => setState(() => _bitrate = value)),
          if (_mode == SaveMode.wav)
            _settingRow('音声形式', '24bit PCM', icon: Icons.audio_file_outlined),
        ],
      ),
    ),
    const SizedBox(height: 12),
    Text(
      _mode == SaveMode.video
          ? '指定した上限内で保存します。元動画の画質・fpsを超えることはありません。'
          : _mode == SaveMode.mp3
          ? '元音源をMP3へ変換します。元音源以上の音質にはなりません。'
          : '圧縮せずに保存します。MP3よりもファイル容量が大きくなります。',
      style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
    ),
    const SizedBox(height: 24),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_outlined, color: _muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '保存先：Download / Android movie Download',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    ),
  ];

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text == null || data!.text!.trim().isEmpty) {
      _toast('貼り付けるテキストがありません');
      return;
    }
    try {
      _url.text = normalizeVideoUrl(data.text!);
    } on FormatException {
      _url.text = data.text!;
    }
  }

  Widget _panel(Widget child) => Card(child: child);

  Widget _settingRow(
    String title,
    String value, {
    VoidCallback? onTap,
    IconData? icon,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: _muted, size: 21),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 3,
            child: Text(title, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.expand_more, size: 18, color: _muted),
          ],
        ],
      ),
    ),
  );

  Widget _selectionRow<T>(
    String title,
    T current,
    Map<T, String> options,
    ValueChanged<T> changed,
  ) => _settingRow(
    title,
    options[current] ?? '',
    onTap: _updating
        ? null
        : () async {
            final choice = await showModalBottomSheet<T>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: options.entries
                            .map(
                              (entry) => Semantics(
                                selected: entry.key == current,
                                child: ListTile(
                                  title: Text(entry.value),
                                  trailing: entry.key == current
                                      ? Icon(
                                          Icons.check,
                                          color: _colors.primary,
                                        )
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(context, entry.key),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
            if (choice != null && mounted) changed(choice);
          },
  );

  List<Widget> _historyPage() {
    final visible = controller.tasks
        .where(
          (task) =>
              _historyFilter == 'all' ||
              (_historyFilter == 'active' && task.active) ||
              (_historyFilter == 'completed' && task.status == 'completed'),
        )
        .toList();
    return [
      const Text(
        'ダウンロード履歴',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        '進行中 ${controller.tasks.where((task) => task.active).length}件 · 完了 ${controller.tasks.where((task) => task.status == 'completed').length}件',
        style: TextStyle(color: _muted, fontSize: 13),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: {'all': 'すべて', 'active': '進行中', 'completed': '完了'}.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.value),
                selected: _historyFilter == entry.key,
                onSelected: (_) => setState(() => _historyFilter = entry.key),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 20),
      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(Icons.download_outlined, size: 42, color: _muted),
              const SizedBox(height: 16),
              Text(
                _historyFilter == 'all' ? 'まだダウンロードはありません' : '該当するダウンロードはありません',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '「新規」から動画のURLを追加できます',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ...visible.map(
        (task) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _panel(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _colors.primary.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          task.mode == 'video'
                              ? Icons.movie_outlined
                              : Icons.audio_file_outlined,
                          size: 21,
                          color: _colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: task.status == 'failed'
                                ? _colors.error
                                : _muted,
                          ),
                        ),
                      ),
                      Text(
                        task.mode.toUpperCase(),
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                      if (task.active)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            '${task.progress.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: _colors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (task.active)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                        value:
                            task.status == 'processing' ||
                                task.status == 'saving'
                            ? null
                            : (task.progress / 100).clamp(0, 1),
                      ),
                    ),
                  if (task.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        task.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: _muted),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (task.active)
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () => controller.cancel(task.id),
                            child: const Text('キャンセル'),
                          ),
                        if (!task.active && task.status != 'completed')
                          TextButton.icon(
                            onPressed: controller.busy
                                ? null
                                : () => controller.retry(task.id),
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('再試行'),
                          ),
                        if (task.outputUri != null)
                          TextButton.icon(
                            onPressed: () => controller.run(() async {
                              await controller.bridge.call('openFile', {
                                'uri': task.outputUri,
                              });
                            }),
                            icon: const Icon(Icons.open_in_new, size: 17),
                            label: const Text('ファイルを開く'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _settingsPage() {
    final blocked =
        _updating ||
        controller.busy ||
        controller.tasks.any((task) => task.active);
    return [
      const Text(
        '設定',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 24),
      _settingsCard('アプリのアップデート', '現在のバージョン ${controller.appVersion}', [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: blocked ? null : _checkUpdate,
            icon: const Icon(Icons.system_update_alt, size: 20),
            label: Text(_updating ? '更新処理中…' : 'アップデートを確認'),
          ),
        ),
        if (_updateMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _updateMessage!,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        if (_updateProgress != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(value: _updateProgress),
          ),
      ]),
      const SizedBox(height: 16),
      _settingsCard('動画取得の更新', 'yt-dlp ${controller.engineVersion}', [
        Text(
          '動画を取得できないときは、最新版を確認してください。',
          style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: blocked ? null : _engineUpdate,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('yt-dlpを確認・更新'),
          ),
        ),
      ]),
      if (blocked) ...[
        const SizedBox(height: 12),
        _notice('ダウンロード・変換が完了すると更新できます。'),
      ],
      const SizedBox(height: 24),
      _sectionLabel('表示'),
      const SizedBox(height: 10),
      _panel(
        _selectionRow<ThemeMode>('テーマ', controller.themeMode, {
          ThemeMode.system: '端末に合わせる',
          ThemeMode.light: 'ライト',
          ThemeMode.dark: 'ダーク',
        }, (mode) => controller.setThemeMode(mode)),
      ),
      const SizedBox(height: 24),
      _sectionLabel('ログイン情報'),
      const SizedBox(height: 10),
      _settingsCard('Cookieファイル', controller.hasCookies ? '設定済み' : '未設定', [
        Text(
          'ログインが必要な動画にはNetscape形式のCookieファイルを指定します。',
          style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: blocked
                  ? null
                  : () => controller.run(() async {
                      await controller.bridge.call('importCookies');
                      await controller.refresh();
                    }),
              child: const Text('ファイルを選択'),
            ),
            if (controller.hasCookies)
              TextButton(
                onPressed: blocked
                    ? null
                    : () => controller.run(() async {
                        await controller.bridge.call('removeCookies');
                        await controller.refresh();
                      }),
                child: const Text('削除'),
              ),
          ],
        ),
      ]),
      const SizedBox(height: 16),
      _panel(
        ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: const Text('詳細設定', style: TextStyle(fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                'https://github.com/${controller.repository}',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: blocked ? null : _repositoryDialog,
                child: const Text('更新配信先を変更'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.center,
        child: Text(
          'Android movie Download',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Android movie Download',
            applicationVersion: controller.appVersion,
          ),
          child: const Text('ライセンス'),
        ),
      ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _muted,
      ),
    ),
  );

  Widget _settingsCard(String title, String subtitle, List<Widget> children) =>
      _panel(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      );

  Widget _notice(String message, {bool isError = false}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError
          ? _colors.errorContainer
          : _colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.info_outline,
          size: 18,
          color: isError ? _colors.onErrorContainer : _colors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: isError ? _colors.onErrorContainer : _colors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _repositoryDialog() async {
    final input = TextEditingController(
      text: 'https://github.com/${controller.repository}',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub更新配信先'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://github.com/owner/repository',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // ダイアログの終了アニメーション後に入力用コントローラーを破棄する。
    Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
    if (value != null) {
      try {
        await controller.saveRepository(value);
      } catch (e) {
        _toast(AppController.readableError(e));
      }
    }
  }
}
