import 'dart:convert';
import 'package:http/http.dart' show post;
import '../database/app_database.dart';

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
  int _styleIndex = 0;
  String _customPrompt = '';

  String get apiKey => _apiKey;
  bool get enabled => _enabled;
  int get providerIndex => _providerIndex;
  String get customApiUrl => _customApiUrl;
  String get customModel => _customModel;
  int get styleIndex => _styleIndex;
  String get customPrompt => _customPrompt;

  set apiKey(String key) { _apiKey = key; _save('ai_api_key', key); }
  set enabled(bool v) { _enabled = v; _save('ai_enabled', v ? '1' : '0'); }
  set providerIndex(int v) { _providerIndex = v; _save('ai_provider', v.toString()); }
  set customApiUrl(String v) { _customApiUrl = v; _save('ai_custom_url', v); }
  set customModel(String v) { _customModel = v; _save('ai_custom_model', v); }
  set styleIndex(int v) { _styleIndex = v; _save('ai_style', v.toString()); }
  set customPrompt(String v) { _customPrompt = v; _save('ai_custom_prompt', v); }

  /// 从数据库加载设置
  Future<void> load() async {
    final db = _AppDatabaseProvider();
    _apiKey = await db.get('ai_api_key') ?? '';
    _enabled = (await db.get('ai_enabled')) != '0';
    _providerIndex = int.tryParse(await db.get('ai_provider') ?? '') ?? 0;
    _customApiUrl = await db.get('ai_custom_url') ?? '';
    _customModel = await db.get('ai_custom_model') ?? '';
    _styleIndex = int.tryParse(await db.get('ai_style') ?? '') ?? 0;
    _customPrompt = await db.get('ai_custom_prompt') ?? '';
  }

  void _save(String key, String value) {
    _AppDatabaseProvider().set(key, value);
  }

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
    // 基本风格提示词 + 通用长度约束：输出长度不超过原文的 120%
    final basePrompt = s.promptForStyle(idx);
    final lengthRule = '重要：输出文本的长度不要超过用户输入原文长度的 120%（字数）。'
        '用户原文长度：${text.length} 字。请严格控制输出长度。';
    final systemPrompt = '$basePrompt\n\n$lengthRule';
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

      final response = await post(Uri.parse(s.resolvedApiUrl), headers: headers, body: body);

      if (response.statusCode == 200) {
        // 使用 utf8 解码，避免 Content-Type 缺少 charset 时 Latin-1 解码导致中文乱码
        final bodyUtf8 = utf8.decode(response.bodyBytes);
        return isClaude ? _parseClaude(bodyUtf8) : _parseOpenAI(bodyUtf8);
      } else if (response.statusCode == 401) {
        throw Exception('API Key 无效，请检查后重试');
      } else if (response.statusCode == 429) {
        throw Exception('请求太频繁，请稍后再试');
      } else {
        final bodyUtf8 = utf8.decode(response.bodyBytes);
        throw Exception(_extractError(bodyUtf8) ?? '请求失败 (${response.statusCode})');
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

  /// 对一组记录进行 AI 总结
  /// [entries] 记录内容列表，每项包含标题和正文
  /// [customPrompt] 自定义总结要求，为空则使用默认
  static Future<String> summarize(List<MapEntry<String, String>> entries,
      {String? customPrompt}) async {
    final s = AISettings();
    if (!s.hasKey) throw Exception('请先在设置中输入 API Key');
    if (s.resolvedApiUrl.isEmpty) throw Exception('请填写 API 地址');

    if (entries.isEmpty) throw Exception('没有可总结的记录');

    // 组装记录文本
    final buffer = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      final title = entries[i].key;
      final content = entries[i].value;
      buffer.writeln('--- 记录 ${i + 1} ---');
      if (title.isNotEmpty) buffer.writeln('标题：$title');
      buffer.writeln(content);
      buffer.writeln();
    }
    final entriesText = buffer.toString();
    final userPrompt = customPrompt?.isNotEmpty == true
        ? '用户要求：$customPrompt\n\n'
            '请根据以下记录内容回答：\n\n$entriesText'
        : '请对以下生活记录进行总结分析，严格按照以下结构输出：\n\n'
            '1. 【做了什么】概括这段时间的主要事项，尽量包含量化数据（次数、时长、件数等）\n'
            '2. 【分析重点】指出关键事项、重复出现的主题或模式\n'
            '3. 【后续待办】还需要跟进或处理的事项\n\n'
            '注意：只基于已有记录进行分析，不要引申或推测记录之外的内容。'
            '用简洁清晰的中文输出。\n\n'
            '记录内容如下：\n\n$entriesText';

    final systemPrompt = '你是一位个人记录分析助手。'
        '严格按照用户的要求分析记录，只陈述记录中已有的信息，'
        '不要引申、推测或编造记录之外的内容。'
        '回答简洁清晰，使用中文。';

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
              'messages': [{'role': 'user', 'content': userPrompt}],
            })
          : jsonEncode({
              'model': s.resolvedModel,
              'max_tokens': 4096,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
            });

      final response =
          await post(Uri.parse(s.resolvedApiUrl), headers: headers, body: body);

      if (response.statusCode == 200) {
        final bodyUtf8 = utf8.decode(response.bodyBytes);
        return isClaude ? _parseClaude(bodyUtf8) : _parseOpenAI(bodyUtf8);
      } else if (response.statusCode == 401) {
        throw Exception('API Key 无效，请检查后重试');
      } else if (response.statusCode == 429) {
        throw Exception('请求太频繁，请稍后再试');
      } else {
        final bodyUtf8 = utf8.decode(response.bodyBytes);
        throw Exception(_extractError(bodyUtf8) ?? '请求失败 (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('网络请求失败：$e');
    }
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

/// 数据库设置持久化辅助
class _AppDatabaseProvider {
  final AppDatabase _db = AppDatabase();

  Future<String?> get(String key) async {
    try { return await _db.getSetting(key); } catch (_) { return null; }
  }

  Future<void> set(String key, String value) async {
    try { await _db.setSetting(key, value); } catch (_) {}
  }
}
