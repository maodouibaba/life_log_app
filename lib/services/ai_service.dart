import 'dart:convert';
import 'package:http/http.dart' as http;

// ==================== AI 供应商 ====================

class AIProvider {
  final String name;
  final String apiUrl;
  final String defaultModel;
  final bool useBearerAuth;

  const AIProvider({
    required this.name,
    required this.apiUrl,
    required this.defaultModel,
    this.useBearerAuth = true,
  });

  static const List<AIProvider> all = [
    AIProvider(name: 'DeepSeek（推荐）', apiUrl: 'https://api.deepseek.com/v1/chat/completions', defaultModel: 'deepseek-chat'),
    AIProvider(name: '通义千问', apiUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions', defaultModel: 'qwen-turbo'),
    AIProvider(name: 'Anthropic Claude', apiUrl: 'https://api.anthropic.com/v1/messages', defaultModel: 'claude-sonnet-4-20250514', useBearerAuth: false),
    AIProvider(name: 'OpenAI', apiUrl: 'https://api.openai.com/v1/chat/completions', defaultModel: 'gpt-4o'),
    AIProvider(name: '自定义（兼容 OpenAI 格式）', apiUrl: '', defaultModel: ''),
  ];
}

// ==================== 写作风格 ====================

class AIWritingStyle {
  final String name;
  final String prompt;

  const AIWritingStyle({required this.name, required this.prompt});

  static const List<AIWritingStyle> all = [
    AIWritingStyle(
      name: '用户原文风格',
      prompt: '你是一位文字助手。请对用户输入的文本进行整理，'
          '要求：1. 修正错别字和语病 2. 让表达更加清晰通顺 '
          '3. 保持原意不变 4. 不要添加原文没有的内容 '
          '5. 最大程度保留用户原本的措辞、语气和表达习惯 '
          '6. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '正式书面风格',
      prompt: '你是一位文字助手。请将用户输入的文本改写为正式书面风格，'
          '要求：1. 使用规范的书面语 2. 句式完整、逻辑清晰 '
          '3. 保持原意不变 4. 适合正式场合阅读 '
          '5. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '跟自己聊天风格',
      prompt: '你是一位文字助手。请将用户输入的文本改写成跟自己聊天的语气，'
          '要求：1. 口语化、轻松自然 2. 像在跟自己对话一样 '
          '3. 保持原意不变 4. 可以用一些语气词 '
          '5. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '鲁迅风格',
      prompt: '你是一位文字助手。请用鲁迅（中国现代文学作家）的文风改写以下文本。'
          '要求：1. 语言凝练冷峻 2. 带点讽刺和深刻 3. 保持原意不变 '
          '4. 模仿鲁迅的句式节奏和用词习惯 5. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '徐志摩风格',
      prompt: '你是一位文字助手。请用徐志摩（中国现代诗人）的文风改写以下文本。'
          '要求：1. 语言优美、富有诗意 2. 情感丰富、意境优美 '
          '3. 保持原意不变 4. 加入适当的修辞和韵律感 '
          '5. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '文言文风格',
      prompt: '你是一位文字助手。请将以下文本翻译为文言文。'
          '要求：1. 使用文言文词汇和句式 2. 符合文言文语法规范 '
          '3. 保持原意不变 4. 直接输出结果，不要任何解释',
    ),
    AIWritingStyle(
      name: '自定义',
      prompt: '', // 用户自定义
    ),
  ];
}

// ==================== AI 设置 ====================

class AISettings {
  static final AISettings _instance = AISettings._internal();
  factory AISettings() => _instance;
  AISettings._internal();

  String _apiKey = '';
  bool _enabled = true;
  int _providerIndex = 0;
  String _customApiUrl = '';
  String _customModel = '';
  int _styleIndex = 0; // 默认"用户原文风格"
  String _customPrompt = '';

  String get apiKey => _apiKey;
  bool get enabled => _enabled;
  int get providerIndex => _providerIndex;
  String get customApiUrl => _customApiUrl;
  String get customModel => _customModel;
  int get styleIndex => _styleIndex;
  String get customPrompt => _customPrompt;

  set apiKey(String key) => _apiKey = key;
  set enabled(bool v) => _enabled = v;
  set providerIndex(int v) => _providerIndex = v;
  set customApiUrl(String v) => _customApiUrl = v;
  set customModel(String v) => _customModel = v;
  set styleIndex(int v) => _styleIndex = v;
  set customPrompt(String v) => _customPrompt = v;

  bool get hasKey => _apiKey.isNotEmpty;

  AIProvider get provider =>
      AIProvider.all[_providerIndex.clamp(0, AIProvider.all.length - 1)];

  String get resolvedApiUrl =>
      provider.name.contains('自定义') ? _customApiUrl : provider.apiUrl;

  String get resolvedModel =>
      provider.name.contains('自定义') ? _customModel : provider.defaultModel;

  /// 根据风格索引返回提示词
  String promptForStyle(int styleIdx) {
    final style = AIWritingStyle.all[styleIdx.clamp(0, AIWritingStyle.all.length - 1)];
    if (style.name == '自定义') return _customPrompt.isNotEmpty ? _customPrompt : AIWritingStyle.all[0].prompt;
    return style.prompt;
  }
}

// ==================== AI 服务 ====================

class AIService {
  /// 对文本进行润色
  /// [styleIndex] 写作风格索引，null 则使用设置中的默认风格
  static Future<String> polish(String text, {int? styleIndex}) async {
    final s = AISettings();
    if (!s.hasKey) throw Exception('请先在设置中输入 API Key');
    if (s.resolvedApiUrl.isEmpty) throw Exception('请填写 API 地址');

    final idx = styleIndex ?? s.styleIndex;
    final systemPrompt = s.promptForStyle(idx);
    final isClaude = s.provider.name.contains('Claude');

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
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
              'messages': [{'role': 'user', 'content': text}],
            })
          : jsonEncode({
              'model': s.resolvedModel,
              'max_tokens': 4096,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': text},
              ],
            });

      final response = await http.post(Uri.parse(s.resolvedApiUrl), headers: headers, body: body);

      if (response.statusCode == 200) {
        return isClaude ? _parseClaude(response.body) : _parseOpenAI(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('API Key 无效，请检查后重试');
      } else if (response.statusCode == 429) {
        throw Exception('请求太频繁，请稍后再试');
      } else {
        throw Exception(_extractError(response.body) ?? '请求失败 (${response.statusCode})');
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
      if (block['type'] == 'text') return (block['text'] as String).trim();
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
