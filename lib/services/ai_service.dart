import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI 设置（单例）
class AISettings {
  static final AISettings _instance = AISettings._internal();
  factory AISettings() => _instance;
  AISettings._internal();

  String _apiKey = '';
  bool _enabled = true;

  String get apiKey => _apiKey;
  bool get enabled => _enabled;

  set apiKey(String key) => _apiKey = key;
  set enabled(bool v) => _enabled = v;

  bool get hasKey => _apiKey.isNotEmpty;
}

/// AI 助写服务
/// 调用 Claude API 对用户输入的文本进行润色整理
class AIService {
  static const String _apiUrl = 'https://api.anthropic.com/v1/messages';

  /// 对文本进行润色
  /// [text] 用户输入的原始文本
  /// [mode] 'polish' 润色整理 | 'expand' 扩写
  static Future<String> polish(String text, {String mode = 'polish'}) async {
    final settings = AISettings();
    if (!settings.hasKey) {
      throw Exception('请先在设置中输入 API Key');
    }

    String systemPrompt;
    if (mode == 'polish') {
      systemPrompt = '你是一位文字助手。请对用户输入的文本进行整理和规范表达，'
          '要求：1. 修正错别字和语病 2. 让表达更加清晰通顺 3. 保持原意不变 '
          '4. 不要添加原文没有的内容 5. 保持原文的风格和语气 6. 直接输出结果，不要任何解释';
    } else {
      systemPrompt = '你是一位文字助手。请在用户输入的基础上进行适当扩写，'
          '使内容更丰富完整，同时保持原意。直接输出结果，不要任何解释。';
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': settings.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 4096,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': text},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>;
        if (content.isNotEmpty) {
          final block = content[0] as Map<String, dynamic>;
          if (block['type'] == 'text') {
            return (block['text'] as String).trim();
          }
        }
        throw Exception('AI 返回格式异常');
      } else if (response.statusCode == 401) {
        throw Exception('API Key 无效，请检查后重试');
      } else if (response.statusCode == 429) {
        throw Exception('请求太频繁，请稍后再试');
      } else {
        final body = response.body;
        final msg = _extractError(body) ?? '请求失败 (${response.statusCode})';
        throw Exception(msg);
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('网络请求失败：$e');
    }
  }

  static String? _extractError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['error']?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}
