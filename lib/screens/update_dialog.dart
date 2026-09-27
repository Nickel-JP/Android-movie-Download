import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/app_updater.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.release, this.currentVersion});

  final AppRelease release;
  final String? currentVersion;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _scrollController = ScrollController();
  static const _installHint = '設定と履歴はそのまま。ダウンロード後にAndroidのインストール確認画面が開きます。';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _notes {
    // 製品名と版番号はヘッダーにあるため、先頭の同じ見出しだけを除く。
    final notes = widget.release.notes.trim().replaceFirst(
      RegExp(r'^#\s+Android movie Download[^\r\n]*(?:\r?\n|$)\s*'),
      '',
    );
    return notes.isEmpty ? '今回の更新に詳しい変更内容はありません。' : notes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurface,
      height: 1.65,
    );
    final headingStyle = theme.textTheme.titleMedium!.copyWith(
      color: colors.onSurface,
      fontWeight: FontWeight.w700,
      height: 1.45,
    );
    final version = widget.currentVersion?.isNotEmpty == true
        ? '${widget.currentVersion} → ${widget.release.version}'
        : 'バージョン ${widget.release.version}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 横向きや大きな文字では補足を本文に移し、操作部分を確保する。
            final compact =
                constraints.maxHeight < 460 ||
                MediaQuery.textScalerOf(context).scale(14) > 22;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.system_update_rounded,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'アップデート',
                              style: theme.textTheme.titleLarge!.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              version,
                              style: theme.textTheme.bodyMedium!.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const Key('updateNotesScroll'),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MarkdownBody(
                            data: _notes,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                .copyWith(
                                  p: bodyStyle,
                                  h1: headingStyle.copyWith(fontSize: 18),
                                  h2: headingStyle,
                                  h3: headingStyle.copyWith(fontSize: 15),
                                  blockSpacing: 14,
                                  listBullet: bodyStyle.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                  listIndent: 20,
                                  listBulletPadding: const EdgeInsets.only(
                                    right: 8,
                                  ),
                                  code: bodyStyle.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    backgroundColor:
                                        colors.surfaceContainerHigh,
                                  ),
                                  blockquoteDecoration: BoxDecoration(
                                    color: colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                            // 更新案内は文章として表示し、画像の外部取得は行わない。
                            imageBuilder: (uri, title, alt) =>
                                Text(alt ?? title ?? '', style: bodyStyle),
                          ),
                          if (compact) ...[
                            const SizedBox(height: 20),
                            Text(
                              _installHint,
                              style: bodyStyle.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            Icons.download_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                          Text(
                            'ダウンロード容量',
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${(widget.release.size / 1024 / 1024).toStringAsFixed(1)} MB',
                            key: const Key('updateDownloadSize'),
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Text(
                          _installHint,
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      OverflowBar(
                        spacing: 10,
                        overflowSpacing: 8,
                        alignment: MainAxisAlignment.end,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: [
                          TextButton(
                            key: const Key('updateLater'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(80, 48),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('あとで'),
                          ),
                          FilledButton(
                            key: const Key('updateConfirm'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(120, 48),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('更新する'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
