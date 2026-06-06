import 'dart:convert';
import 'package:http/http.dart' as http;

/// AI 供应商配置
class AIProvider {
  final String name;
  final String apiUrl;
  final String defaultModel;
  final bool useBearerAuth; // true=Bearer token, false=x-api-key

  const AIProvider({
    required this.name,
    required this.apiUrl,
    required this.defaultModel,
    this.useBearerAuth = true,
  });

  static const List<AIProvider> all = [
    AIProvider(
      name: 'DeepSeek（推荐）',
      apiUrl: 'https://api.deepseek.com/v1/chat/completions',
      defaultModel: 'deepseek-chat',
    ),
    AIProvider(
      name: '通义千问',
      apiUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      defaultModel: 'qwen-turbo',
    ),
    AIProvider(
      name: 'Anthropic Claude',
      apiUrl: 'https://api.anthropic.com/v1/messages',
      defaultModel: 'claude-sonnet-4-20250514',
      useBearerAuth: false,
    ),
    AIProvider(
      name: 'OpenAI',
      apiUrl: 'https://api.openai.com/v1/chat/completions',
      defaultModel: 'gpt-4o',
    ),
    AIProvider(
      name: '自定义（兼容 OpenAI 格式）',
      apiUrl: '',
      defaultModel: '',
    ),
  ];
}

/// AI 设置（单例）
class AISettings {
  static final AISettings _instance = AISettings._internal();
  factory AISettings() => _instance;
  AISettings._internal();

  String _apiKey = '';
  bool _enabled = true;
  int _providerIndex = 0; // 默认 DeepSeek
  String _customApiUrl = '';
  String _customModel = '';

  String get apiKey => _apiKey;
  bool get enabled => _enabled;
  int get providerIndex => _providerIndex;
  String get customApiUrl => _customApiUrl;
  String get customModel => _customModel;

  set apiKey(String key) => _apiKey = key;
  set enabled(bool v) => _enabled = v;
  set providerIndex(int v) => _providerIndex = v;
  set customApiUrl(String v) => _customApiUrl = v;
  set customModel(String v) => _customModel = v;

  bool get hasKey => _apiKey.isNotEmpty;

  AIProvider get provider {
    if (_providerIndex >= 0 && _providerIndex < AIProvider.all.length) {
      return AIProvider.all[_providerIndex];
    }
    return AIProvider.all[0];
  }

  String get resolvedApiUrl {
    if (provider.name == '自定义') return _customApiUrl;
    return provider.apiUrl;
  }

  String get resolvedModel {
    if (provider.name == '自定义') return _customModel;
    return provider.defaultModel;
  }
}

/// AI 助写服务
class AIService {
  /// 对文本进行润色
  static Future<String> polish(String text, {String mode = 'polish'}) async {
    final s = AISettings();
    if (!s.hasKey) throw Exception('请先在设置中输入 API Key');
    if (s.resolvedApiUrl.isEmpty) throw Exception('请填写自定义 API 地址');

    String systemPrompt;
    if (mode == 'polish') {
      systemPrompt = '你是一位文字助手。请对用户输入的文本进行整理和规范表达，'
          '要求：1. 修正错别字和语病 2. 让表达更加清晰通顺 3. 保持原意不变 '
          '4. 不要添加原文没有的内容 5. 保持原文的风格和语气 6. 直接输出结果，不要任何解释';
    } else {
      systemPrompt = '你是一位文字助手。请在用户输入的基础上进行适当扩写，'
          '使内容更丰富完整，同时保持原意。直接输出结果，不要任何解释。';
    }

    final isClaude = s.provider.name.contains('Claude');

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (isClaude) {
        headers['x-api-key'] = s.apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else {
        headers['Authorization'] = 'Bearer ${s.apiKey}';
      }

      final body = isClaude
          ? jsonEncode({
              'model': s.resolvedModel,
              'max_tokens': 4096,
              'system': systemPrompt,
              'messages': [
                {'role': 'user', 'content': text},
              ],
            })
          : jsonEncode({
              'model': s.resolvedModel,
              'max_tokens': 4096,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': text},
              ],
            });

      final response = await http.post(
        Uri.parse(s.resolvedApiUrl),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return isClaude ? _parseClaude(response.body) : _parseOpenAI(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('API Key 无效，请检查后重试');
      } else if (response.statusCode == 429) {
        throw Exception('请求太频繁，请稍后再试');
      } else {
        final msg = _extractError(response.body) ?? '请求失败 (${response.statusCode})';
        throw Exception(msg);
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('网络请求失败：$e');
    }
  }

  static String _parseOpenAI(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = choices[0] as Map<String, dynamic>;
      final content = msg['message']?['content'] as String?;
      if (content != null) return content.trim();
    }
    throw Exception('AI 返回格式异常');
  }

  static String _parseClaude(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>?;
    if (content != null && content.isNotEmpty) {
      final block = content[0] as Map<String, dynamic>;
      if (block['type'] == 'text') {
        return (block['text'] as String).trim();
      }
    }
    throw Exception('AI 返回格式异常');
  }

  static String? _extractError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final err = data['error'];
      if (err is Map) return (err['message'] as String?) ?? err.toString();
      return err?.toString();
    } catch (_) {
      return null;
    }
  }
}
