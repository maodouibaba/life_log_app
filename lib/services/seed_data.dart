import '../database/app_database.dart';

/// 演示数据生成器
/// 填充 2 个入口、跨 3 天的演示数据
class SeedData {
  static Future<void> load(AppDatabase db) async {
    // 时间工具：生成指定天数前的时间
    DateTime daysAgo(int d) =>
        DateTime.now().subtract(Duration(days: d));

    // ==================== 入口 1：默认（生活/学习）====================

    // 项目分组
    await db.createProjectGroup('健康', 1);
    await db.createProjectGroup('学习', 1);
    await db.createProjectGroup('兴趣', 1);

    // 项目
    final fitness = await db.createProject('健身计划', groupId: 1, spaceId: 1);
    final reading = await db.createProject('阅读清单', groupId: 2, spaceId: 1);
    final flutterStudy = await db.createProject('Flutter学习', groupId: 2, spaceId: 1);
    await db.createProject('英语学习', groupId: 2, spaceId: 1);
    await db.createProject('摄影入门', groupId: 3, spaceId: 1);

    // 树状标签
    // 生活
    final lifeRoot = await db.createTag('生活', spaceId: 1);
    final foodTag = await db.createTag('饮食', parentId: lifeRoot.id, spaceId: 1);
    final lunchTag = await db.createTag('午餐', parentId: foodTag.id, spaceId: 1);
    final dinnerTag = await db.createTag('晚餐', parentId: foodTag.id, spaceId: 1);
    final sportTag = await db.createTag('运动', parentId: lifeRoot.id, spaceId: 1);
    final runTag = await db.createTag('跑步', parentId: sportTag.id, spaceId: 1);
    await db.createTag('骑行', parentId: sportTag.id, spaceId: 1);

    // 学习
    final studyRoot = await db.createTag('学习', spaceId: 1);
    final flutterTag = await db.createTag('Flutter', parentId: studyRoot.id, spaceId: 1);
    final englishTag = await db.createTag('英语', parentId: studyRoot.id, spaceId: 1);
    final photoTag = await db.createTag('摄影', parentId: studyRoot.id, spaceId: 1);

    // 属性标签分组
    await db.createAttributeTagGroup('心情', 1);
    await db.createAttributeTagGroup('地点', 1);

    // 属性标签
    final happyTag = await db.createAttributeTag('开心', groupId: 1, spaceId: 1);
    await db.createAttributeTag('平静', groupId: 1, spaceId: 1);
    final tiredTag = await db.createAttributeTag('疲惫', groupId: 1, spaceId: 1);
    final outdoorTag = await db.createAttributeTag('户外', groupId: 2, spaceId: 1);
    final homeTag = await db.createAttributeTag('家', groupId: 2, spaceId: 1);

    // ——— 入口 1 记录（跨 3 天）———

    // D-2: 第一天
    await db.createEntry(
      '今天终于开始晨跑了！\n'
      '虽然只跑了 **3** 公里，但这是一个好的开始。\n\n'
      '- 配速：6分10秒\n'
      '- 路线：小区绕圈\n'
      '- 感受：*气喘吁吁但很爽*',
      title: '第一次晨跑',
      tagIds: [lifeRoot.id!, sportTag.id!, runTag.id!],
      attributeTagIds: [happyTag.id!, outdoorTag.id!],
      projectId: fitness.id,
      spaceId: 1,
      createdAt: daysAgo(2),
    );

    await db.createEntry(
      '今天的午餐是 *自制三明治*！\n'
      '全麦面包 + 鸡胸肉 + 生菜 + 番茄，健康又美味。',
      tagIds: [lifeRoot.id!, foodTag.id!, lunchTag.id!],
      attributeTagIds: [happyTag.id!],
      spaceId: 1,
      createdAt: daysAgo(2),
    );

    // D-1: 第二天
    await db.createEntry(
      '学习了 Flutter 的 **Riverpod** 状态管理：\n'
      '- Provider 的升级版，编译安全\n'
      '- 无需 BuildContext\n'
      '- autodispose 自动释放\n\n'
      '下一步要实践的：\n'
      '1. 结合 go_router 使用\n'
      '2. 写单元测试',
      title: 'Riverpod 学习笔记',
      tagIds: [studyRoot.id!, flutterTag.id!],
      projectId: flutterStudy.id,
      spaceId: 1,
      createdAt: daysAgo(1),
    );

    await db.createEntry(
      '制定本周英语计划：\n'
      '- 每天背 **30** 个单词\n'
      '- 听完 2 篇 BBC 新闻\n'
      '- 写 1 篇英语日记\n\n'
      '*坚持就是胜利！*',
      title: '本周英语计划',
      tagIds: [studyRoot.id!, englishTag.id!],
      projectId: (await db.getAllProjects(spaceId: 1))
          .firstWhere((p) => p.name == '英语学习').id,
      spaceId: 1,
      createdAt: daysAgo(1),
    );

    // D-0: 今天
    await db.createEntry(
      '今晚做了 *红烧排骨*，味道不错！\n'
      '做饭真是一种享受，**专注**且放松。',
      tagIds: [lifeRoot.id!, foodTag.id!, dinnerTag.id!],
      attributeTagIds: [tiredTag.id!, homeTag.id!],
      spaceId: 1,
    );

    await db.createEntry(
      '读完《设计数据密集型应用》第三章，收获：\n\n'
      '**存储与检索**\n'
      '- LSM-Tree vs B-Tree 的取舍\n'
      '- 事务处理与分析处理的差异\n'
      '- 列式存储的优势\n\n'
      '> 一个好的数据系统应该在 20 年后仍然适用。',
      title: 'DDIA 第三章读书笔记',
      tagIds: [studyRoot.id!],
      projectId: reading.id,
      spaceId: 1,
    );

    // ==================== 入口 2：工作 ====================

    // 先用 createSpace 创建第二个入口
    await db.createSpace('工作');

    // 项目分组
    await db.createProjectGroup('产品', 2);
    await db.createProjectGroup('技术', 2);

    // 项目
    final projectX = await db.createProject('智能助手项目', groupId: 1, spaceId: 2);
    await db.createProject('用户增长项目', groupId: 1, spaceId: 2);
    await db.createProject('架构升级', groupId: 2, spaceId: 2);

    // 树状标签
    final devRoot = await db.createTag('开发', spaceId: 2);
    final frontend = await db.createTag('前端', parentId: devRoot.id, spaceId: 2);
    final backend = await db.createTag('后端', parentId: devRoot.id, spaceId: 2);
    await db.createTag('Flutter', parentId: frontend.id, spaceId: 2);
    await db.createTag('Go', parentId: backend.id, spaceId: 2);

    final meetingRoot = await db.createTag('会议', spaceId: 2);
    final standup = await db.createTag('站会', parentId: meetingRoot.id, spaceId: 2);
    final review = await db.createTag('评审', parentId: meetingRoot.id, spaceId: 2);

    final docRoot = await db.createTag('文档', spaceId: 2);
    final apiDoc = await db.createTag('API文档', parentId: docRoot.id, spaceId: 2);

    // 属性标签
    await db.createAttributeTagGroup('状态', 2);
    await db.createAttributeTagGroup('优先级', 2);
    await db.createAttributeTagGroup('会议类型', 2);
    final urgentTag = await db.createAttributeTag('紧急', groupId: 2, spaceId: 2);
    final normalTag = await db.createAttributeTag('普通', groupId: 2, spaceId: 2);
    final weeklyTag = await db.createAttributeTag('周会', groupId: 3, spaceId: 2);
    final codeReview = await db.createAttributeTag('代码审查', groupId: 3, spaceId: 2);

    // ——— 入口 2 记录（跨 3 天）———

    // D-2
    await db.createEntry(
      '项目启动会要点：\n\n'
      '**智能助手项目**正式立项！\n\n'
      '1. 项目周期：3 个月\n'
      '2. 团队：5 人\n'
      '3. 技术栈：Flutter + Go\n\n'
      '- 下周一确认技术方案\n'
      '- 周三前端启动开发',
      title: '项目启动会议',
      tagIds: [meetingRoot.id!, review.id!],
      attributeTagIds: [urgentTag.id!],
      projectId: projectX.id,
      spaceId: 2,
      createdAt: daysAgo(2),
    );

    // D-1
    await db.createEntry(
      '今日站会同步：\n\n'
      '**昨日完成：**\n'
      '- 登录模块 UI 完成 80%\n'
      '- 修复了 2 个 bug\n\n'
      '**今日计划：**\n'
      '- 完成登录模块\n'
      '- 与后端联调接口\n\n'
      '**阻塞项：**\n'
      '- 等待 API 文档更新',
      title: '站会记录',
      tagIds: [meetingRoot.id!, standup.id!, devRoot.id!],
      attributeTagIds: [normalTag.id!, weeklyTag.id!],
      projectId: projectX.id,
      spaceId: 2,
      createdAt: daysAgo(1),
    );

    await db.createEntry(
      'Code Review 了小王的前端 PR：\n\n'
      '- 整体代码质量 **不错**\n'
      '- 建议：状态管理改用 Riverpod\n'
      '- 发现一处内存泄漏隐患\n\n'
      '*已标注 inline comment，明天跟进。*',
      title: '代码审查',
      tagIds: [devRoot.id!, frontend.id!],
      attributeTagIds: [normalTag.id!, codeReview.id!],
      projectId: projectX.id,
      spaceId: 2,
      createdAt: daysAgo(1),
    );

    // D-0: 今天
    await db.createEntry(
      '本周总结：\n\n'
      '**完成：**\n'
      '1. 登录模块开发 ✅\n'
      '2. API 联调完成 ✅\n'
      '3. 单元测试覆盖率 75%\n\n'
      '**下周计划：**\n'
      '1. 支付模块设计评审\n'
      '2. 性能优化\n'
      '3. 技术分享：Flutter 3.x 新特性',
      title: '本周工作总结',
      tagIds: [devRoot.id!, docRoot.id!],
      attributeTagIds: [urgentTag.id!],
      projectId: projectX.id,
      spaceId: 2,
    );

    await db.createEntry(
      '编写支付模块的 API 文档：\n\n'
      '## 接口列表\n'
      '1. POST /api/pay/create — 创建订单\n'
      '2. POST /api/pay/callback — 支付回调\n'
      '3. GET /api/pay/status — 查询状态\n\n'
      '*文档放到了团队的飞书文档，@了相关人 review。*',
      title: 'API 文档编写',
      tagIds: [docRoot.id!, apiDoc.id!],
      projectId: projectX.id,
      spaceId: 2,
    );
  }
}
