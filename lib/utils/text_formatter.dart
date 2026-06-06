import 'package:flutter/material.dart';

/// 简单的文本格式渲染工具
/// 支持：无序列表、有序列表、粗体、斜体、标题
class TextFormatter {
  /// 将纯文本解析为 Flutter Widget 列表
  /// 支持格式：
  ///   - 无序列表项（以 "- " 或 "* " 开头）
  ///   1. 有序列表项（以 "数字. " 开头）
  ///   **粗体文字**
  ///   *斜体文字*
  ///   # 标题
  static List<Widget> render(String text, {TextStyle? baseStyle}) {
    if (text.isEmpty) return [];

    final lines = text.split('\n');
    final widgets = <Widget>[];
    final baseFontSize = baseStyle?.fontSize ?? 16.0;
    final baseColor = baseStyle?.color;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // 空行
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // 标题（# 开头）
      if (trimmed.startsWith('#')) {
        final level = trimmed.indexOf(' ');
        if (level > 0 && level <= 3) {
          final headerText = trimmed.substring(level + 1);
          final sizes = [22.0, 19.0, 17.0];
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              headerText,
              style: TextStyle(
                fontSize: sizes[level.clamp(1, 3) - 1],
                fontWeight: FontWeight.w700,
                color: baseColor,
              ),
            ),
          ));
          continue;
        }
      }

      // 无序列表（- 或 * 开头）
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final content = trimmed.substring(2);
        final isNested = line.startsWith('  ') || line.startsWith('\t');
        widgets.add(Padding(
          padding: EdgeInsets.only(left: isNested ? 32 : 16, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(fontSize: baseFontSize, color: baseColor)),
              Expanded(
                child: _buildRichText(content,
                    baseStyle: baseStyle, baseFontSize: baseFontSize),
              ),
            ],
          ),
        ));
        continue;
      }

      // 有序列表（数字. 开头）
      final orderMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(trimmed);
      if (orderMatch != null) {
        final num = int.parse(orderMatch.group(1)!);
        final content = orderMatch.group(2)!;
        final isNested = line.startsWith('  ') || line.startsWith('\t');
        widgets.add(Padding(
          padding: EdgeInsets.only(left: isNested ? 32 : 16, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$num.  ',
                  style: TextStyle(
                      fontSize: baseFontSize,
                      fontWeight: FontWeight.w500,
                      color: baseColor)),
              Expanded(
                child: _buildRichText(content,
                    baseStyle: baseStyle, baseFontSize: baseFontSize),
              ),
            ],
          ),
        ));
        continue;
      }

      // 普通段落
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildRichText(line,
            baseStyle: baseStyle, baseFontSize: baseFontSize),
      ));
    }

    return widgets;
  }

  /// 解析行内格式（粗体、斜体），返回 RichText
  static Widget _buildRichText(String text,
      {TextStyle? baseStyle, double baseFontSize = 16}) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*)');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // 普通文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      if (match.group(1)!.startsWith('**')) {
        // 粗体 **text**
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else {
        // 斜体 *text*
        spans.add(TextSpan(
          text: match.group(3),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }

      lastEnd = match.end;
    }

    // 剩余文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(fontSize: baseFontSize, height: 1.7, color: baseStyle?.color),
        children: spans,
      ),
    );
  }

  /// 去除 markdown 符号，返回纯文本（用于预览截断）
  static String stripMarkdown(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!)
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m[1]!)
        .replaceAll(RegExp(r'^#+\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^[-\*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
  }
}
