import '../database/app_database.dart';

/// 演示数据生成器
/// 调用 loadSeedData() 即可填充示例数据
class SeedData {
  static Future<void> load(AppDatabase db) async {
    // ==================== 项目分组 ====================
    await db.createProjectGroup('工作', 1);
    await db.createProjectGroup('个人', 1);
    await db.createProjectGroup('学习', 1);

    // ==================== 项目 ====================
    final projectA = await db.createProject('项目A', groupId: 1, spaceId: 1);
    await db.createProject('项目B', groupId: 1, spaceId: 1);
    final fitness = await db.createProject('健身计划', groupId: 2, spaceId: 1);
    final reading = await db.createProject('阅读清单', groupId: 2, spaceId: 1);
    final flutterStudy = await db.createProject('Flutter学习', groupId: 3, spaceId: 1);
    await db.createProject('英语学习', groupId: 3, spaceId: 1);

    // ==================== 树状标签 ====================
    // 工作
    final workRoot = await db.createTag('工作', spaceId: 1);
    final meetingTag = await db.createTag('会议', parentId: workRoot.id, spaceId: 1);
    final taskTag = await db.createTag('任务', parentId: workRoot.id, spaceId: 1);
    final taskDoing = await db.createTag('进行中', parentId: taskTag.id, spaceId: 1);
    final taskDone = await db.createTag('已完成', parentId: taskTag.id, spaceId: 1);

    // 生活
    final lifeRoot = await db.createTag('生活', spaceId: 1);
    final foodTag = await db.createTag('饮食', parentId: lifeRoot.id, spaceId: 1);
    await db.createTag('早餐', parentId: foodTag.id, spaceId: 1);
    await db.createTag('午餐', parentId: foodTag.id, spaceId: 1);
    final dinnerTag = await db.createTag('晚餐', parentId: foodTag.id, spaceId: 1);
    final sportTag = await db.createTag('运动', parentId: lifeRoot.id, spaceId: 1);
    final runTag = await db.createTag('跑步', parentId: sportTag.id, spaceId: 1);
    await db.createTag('健身', parentId: sportTag.id, spaceId: 1);

    // 学习
    final studyRoot = await db.createTag('学习', spaceId: 1);
    final flutterTag = await db.createTag('Flutter', parentId: studyRoot.id, spaceId: 1);
    final englishTag = await db.createTag('英语', parentId: studyRoot.id, spaceId: 1);

    // ==================== 属性标签分组 ====================
    await db.createAttributeTagGroup('心情', 1);
    await db.createAttributeTagGroup('地点', 1);
    await db.createAttributeTagGroup('优先级', 1);

    // ==================== 属性标签 ====================
    // 心情（groupId=1）
    final happyTag = await db.createAttributeTag('开心', groupId: 1, spaceId: 1);
    await db.createAttributeTag('平静', groupId: 1, spaceId: 1);
    await db.createAttributeTag('焦虑', groupId: 1, spaceId: 1);
    final tiredTag = await db.createAttributeTag('疲惫', groupId: 1, spaceId: 1);

    // 地点（groupId=2）
    await db.createAttributeTag('家', groupId: 2, spaceId: 1);
    final officeTag = await db.createAttributeTag('公司', groupId: 2, spaceId: 1);
    await db.createAttributeTag('户外', groupId: 2, spaceId: 1);
    await db.createAttributeTag('咖啡馆', groupId: 2, spaceId: 1);

    // 优先级（groupId=3）
    final importantTag = await db.createAttributeTag('重要', groupId: 3, spaceId: 1);
    await db.createAttributeTag('普通', groupId: 3, spaceId: 1);

    // ==================== 演示记录 ====================

    // 1. 项目启动会议 —— 工作
    await db.createEntry(
      '今天参加了新项目的启动会议，讨论了以下事项：\n'
      '- 项目时间线确定\n'
      '- 各模块负责人\n'
      '- 第一阶段目标\n\n'
      '重点：**技术选型**需要在本周确定。\n\n'
      '# 后续行动\n'
      '1. 调研 Flutter 3.x 新特性\n'
      '2. 搭建项目脚手架\n'
      '3. 编写技术方案文档',
      title: '项目启动会议',
      tagIds: [workRoot.id!, meetingTag.id!, taskDoing.id!],
      projectId: projectA.id,
      spaceId: 1,
    );

    // 2. 晨跑记录 —— 生活·运动
    await db.createEntry(
      '今天天气不错，*空气清新*。\n'
      '跑了5公里，配速5分30秒，状态很好。\n\n'
      '- 路线：公园东门 → 湖边 → 南门折返',
      title: '晨跑5公里',
      tagIds: [lifeRoot.id!, sportTag.id!, runTag.id!],
      attributeTagIds: [happyTag.id!],
      projectId: fitness.id,
      spaceId: 1,
    );

    // 3. Flutter 学习笔记 —— 学习
    await db.createEntry(
      '学习了 Flutter 的 **Riverpod** 状态管理方案：\n'
      '- Provider vs Riverpod\n'
      '- 使用 Ref 替代 BuildContext\n'
      '- autodispose 机制\n\n'
      '需要继续深入学习的：\n'
      '1. 测试方案\n'
      '2. 性能优化\n'
      '3. 实战项目',
      title: 'Riverpod 学习笔记',
      tagIds: [studyRoot.id!, flutterTag.id!],
      projectId: flutterStudy.id,
      spaceId: 1,
    );

    // 4. 午餐 —— 生活·饮食
    await db.createEntry(
      '今天尝试了公司楼下的新餐厅，*番茄牛腩面*很不错！\n'
      '汤底浓郁，牛肉炖得烂，推荐。',
      tagIds: [lifeRoot.id!, foodTag.id!],
      attributeTagIds: [happyTag.id!, officeTag.id!],
      spaceId: 1,
    );

    // 5. 英语学习计划 —— 学习
    await db.createEntry(
      '制定本周英语学习计划：\n'
      '- 每天背 **30** 个单词\n'
      '- 听完 2 篇 BBC 新闻\n'
      '- 写 1 篇英语日记\n\n'
      '*坚持就是胜利！*',
      title: '本周英语计划',
      tagIds: [studyRoot.id!, englishTag.id!],
      projectId: (await db.getAllProjects(spaceId: 1))
          .firstWhere((p) => p.name == '英语学习').id,
      spaceId: 1,
    );

    // 6. 工作总结 · 已完成任务
    await db.createEntry(
      '本周工作完成情况：\n'
      '1. 完成了登录模块的 **UI 重构**\n'
      '2. 修复了 3 个线上 bug\n'
      '3. 代码 Review 了 5 个 PR\n\n'
      '下周计划：\n'
      '1. 开始支付模块开发\n'
      '2. 性能优化',
      title: '本周工作总结',
      tagIds: [workRoot.id!, taskTag.id!, taskDone.id!],
      attributeTagIds: [importantTag.id!, officeTag.id!],
      projectId: projectA.id,
      spaceId: 1,
    );

    // 7. 夜晚感慨 —— 生活·晚餐
    await db.createEntry(
      '今晚做了 *红烧排骨*，味道不错！\n'
      '做饭真是一种享受，**专注**且放松。',
      tagIds: [lifeRoot.id!, foodTag.id!, dinnerTag.id!],
      attributeTagIds: [tiredTag.id!],
      spaceId: 1,
    );

    // 8. 读书笔记 —— 阅读
    await db.createEntry(
      '读完《设计数据密集型应用》第三章，收获：\n\n'
      '**存储与检索**\n'
      '- LSM-Tree vs B-Tree 的取舍\n'
      '- 事务处理与分析处理的差异\n'
      '- 列式存储的优势\n\n'
      '精彩摘录：\n'
      '> 一个好的数据系统应该在 20 年后仍然适用。',
      title: 'DDIA 第三章读书笔记',
      tagIds: [studyRoot.id!],
      projectId: reading.id,
      spaceId: 1,
    );
  }
}
