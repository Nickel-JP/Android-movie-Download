import 'package:flutter/material.dart';

import '../models/download.dart';

class ShareDownloadDialog extends StatelessWidget {
  const ShareDownloadDialog({
    super.key,
    required this.url,
    required this.options,
  });

  final String url;
  final DownloadOptions options;

  String get _quality => switch (options.mode) {
    SaveMode.video =>
      '${options.container.toUpperCase()} ・ 最大${options.height == 2160 ? '4K' : '${options.height}p'} / ${options.fps}fps',
    SaveMode.mp3 => 'MP3 ・ ${options.bitrate} kbps',
    SaveMode.wav => 'WAV ・ 24bit PCM',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 520),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('ダウンロードしますか？'),
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共有されたURL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                url,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _quality,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '形式や画質は、キャンセル後に保存画面で変更できます。リストの場合は動画の選択画面を開きます。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('shareCancel'),
          style: TextButton.styleFrom(minimumSize: const Size(80, 48)),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('shareDownload'),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ダウンロード'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    );
  }
}
