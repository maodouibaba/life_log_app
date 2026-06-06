import '../database/app_database.dart';

/// 演示数据生成器
/// 以区级国有城投公司造价工程师的身份，填充 2 个入口、跨 3 天的数据
class SeedData {
  static Future<void> load(AppDatabase db) async {
    DateTime daysAgo(int d) =>
        DateTime.now().subtract(Duration(days: d));

    // ==================== 入口 1：工作 ====================

    // 项目分组
    final g1 = await db.createProjectGroup('在建项目', 1);
    final g2 = await db.createProjectGroup('前期项目', 1);
    final g3 = await db.createProjectGroup('已竣工', 1);

    // 项目
    final p1 = await db.createProject('翠苑安置房项目', groupId: g1.id, spaceId: 1);
    final p2 = await db.createProject('滨江路市政改造工程', groupId: g1.id, spaceId: 1);
    final p3 = await db.createProject('新城小学新建工程', groupId: g1.id, spaceId: 1);
    final p4 = await db.createProject('城北排水管网项目', groupId: g2.id, spaceId: 1);
    await db.createProject('东湖生态公园项目', groupId: g2.id, spaceId: 1);
    final p5 = await db.createProject('老城区立面改造项目', groupId: g3.id, spaceId: 1);

    // 树状标签
    // 造价工作
    final zjRoot = await db.createTag('造价管理', spaceId: 1);
    final ysTag = await db.createTag('预算编制', parentId: zjRoot.id, spaceId: 1);
    final jsTag = await db.createTag('结算审核', parentId: zjRoot.id, spaceId: 1);
    final zjTag = await db.createTag('招标控制价', parentId: zjRoot.id, spaceId: 1);
    final qdTag = await db.createTag('清单编制', parentId: zjRoot.id, spaceId: 1);

    // 项目管理
    final pmRoot = await db.createTag('项目管理', spaceId: 1);
    final htTag = await db.createTag('合同管理', parentId: pmRoot.id, spaceId: 1);
    final xcTag = await db.createTag('现场签证', parentId: pmRoot.id, spaceId: 1);
    final sjTag = await db.createTag('设计变更', parentId: pmRoot.id, spaceId: 1);

    // 会议与沟通
    final mtRoot = await db.createTag('会议沟通', spaceId: 1);
    final zlTag = await db.createTag('专题会议', parentId: mtRoot.id, spaceId: 1);
    final zbtTag = await db.createTag('招标答疑', parentId: mtRoot.id, spaceId: 1);
    final xcjhTag = await db.createTag('现场踏勘', parentId: mtRoot.id, spaceId: 1);

    // 个人提升
    final upRoot = await db.createTag('个人提升', spaceId: 1);
    final zcTag = await db.createTag('职称评审', parentId: upRoot.id, spaceId: 1);
    final kcTag = await db.createTag('考证学习', parentId: upRoot.id, spaceId: 1);

    // 属性标签分组
    final stateGroup = await db.createAttributeTagGroup('工作状态', 1);
    final urgentGroup = await db.createAttributeTagGroup('紧急程度', 1);
    final typeGroup = await db.createAttributeTagGroup('事项类型', 1);

    // 属性标签
    final doingTag = await db.createAttributeTag('进行中', groupId: stateGroup.id, spaceId: 1);
    final doneTag = await db.createAttributeTag('已完成', groupId: stateGroup.id, spaceId: 1);
    final waitTag = await db.createAttributeTag('待办', groupId: stateGroup.id, spaceId: 1);
    final urgentTag = await db.createAttributeTag('紧急', groupId: urgentGroup.id, spaceId: 1);
    final normalTag = await db.createAttributeTag('普通', groupId: urgentGroup.id, spaceId: 1);
    final reviewTag = await db.createAttributeTag('审核', groupId: typeGroup.id, spaceId: 1);
    final meetingTag = await db.createAttributeTag('会议', groupId: typeGroup.id, spaceId: 1);

    // ——— 入口 1 工作记录（跨 3 天）———

    // D-2
    await db.createEntry(
      '**翠苑安置房项目**预算编制启动会要点：\n\n'
      '1. 项目概况：总建筑面积约 8.6 万㎡，其中地上 6.2 万㎡\n'
      '2. 编制依据：2018 版定额 + 最新信息价\n'
      '3. **时间节点**：下周五前完成初稿\n'
      '4. 人员分工：我负责 **土建** 部分，小张负责安装\n\n'
      '-# 需协调事项\n'
      '- 设计院图纸未完全到位，已催办\n'
      '- 材料信息价需等造价站发布',
      title: '翠苑项目预算编制启动会',
      tagIds: [zjRoot.id!, ysTag.id!, mtRoot.id!, zlTag.id!],
      attributeTagIds: [doingTag.id!, urgentTag.id!, meetingTag.id!],
      projectId: p1.id,
      spaceId: 1,
      createdAt: daysAgo(2),
    );

    await db.createEntry(
      '滨江路改造工程 **现场签证** 审核：\n\n'
      '施工方上报签证编号 **BJ-2026-008**：\n'
      '- 内容：污水井移位增加 2 座\n'
      '- 上报金额：*48,652 元*\n'
      '- 审核意见：单价偏高，建议参照同期同类项目 **38,000 元** 核定\n\n'
      '已与施工方沟通，明早现场复核。',
      title: '滨江路签证审核',
      tagIds: [pmRoot.id!, xcTag.id!, zjRoot.id!, jsTag.id!],
      attributeTagIds: [doingTag.id!, normalTag.id!, reviewTag.id!],
      projectId: p2.id,
      spaceId: 1,
      createdAt: daysAgo(2),
    );

    // D-1
    await db.createEntry(
      '今日现场踏勘记录——新城小学项目：\n\n'
      '**参与方：** 施工方、监理、设计、我\n\n'
      '**踏勘内容：**\n'
      '1. 基础开挖至持力层，现场标高确认 ✅\n'
      '2. 基坑支护方案实施情况基本符合设计要求\n'
      '3. 发现 *#* 问题：西南角有 **不明管线**，需协调管线单位确认\n\n'
      '**签证意向：** 涉及土方二次转运约 320m³，需做好现场记录',
      title: '新城小学现场踏勘',
      tagIds: [pmRoot.id!, xcTag.id!, mtRoot.id!, xcjhTag.id!],
      attributeTagIds: [doingTag.id!, urgentTag.id!],
      projectId: p3.id,
      spaceId: 1,
      createdAt: daysAgo(1),
    );

    await db.createEntry(
      '编制城北排水管网项目 **招标控制价**：\n\n'
      '**项目概况：**\n'
      '- 新建雨水管 D800 约 1.2km\n'
      '- 新建污水管 D400 约 0.8km\n'
      '- 检查井 45 座\n\n'
      '**今日完成：**\n'
      '1. 工程量清单初稿已完成\n'
      '2. 主材价按 2026 年 5 月信息价计取\n'
      '3. 控制价汇总约 *685 万元*\n\n'
      '待领导审核后发招标代理。',
      title: '城北排水管网招标控制价',
      tagIds: [zjRoot.id!, zjTag.id!, qdTag.id!],
      attributeTagIds: [doingTag.id!, normalTag.id!],
      projectId: p4.id,
      spaceId: 1,
      createdAt: daysAgo(1),
    );

    // D-0：今天
    await db.createEntry(
      '**老城区立面改造项目**结算审核——这周要完成！\n\n'
      '施工单位上报结算金额：*1,286 万元*\n\n'
      '审核要点：\n'
      '1. 外墙面真石漆面积有争议，施工方多报约 8%\n'
      '2. 脚手架租赁时间与施工日志不一致\n'
      '3. 新增店招项目缺报价依据\n\n'
      '已约施工方 **周四下午** 对账。',
      title: '老城立面改造结算审核',
      tagIds: [zjRoot.id!, jsTag.id!],
      attributeTagIds: [doingTag.id!, urgentTag.id!, reviewTag.id!],
      projectId: p5.id,
      spaceId: 1,
    );

    await db.createEntry(
      '参加 **一级造价工程师** 考前培训：\n\n'
      '**《建设工程计价》** 第三章笔记：\n\n'
      '1. 设计概算的编制方法：\n'
      '   - 概算定额法（初步设计达一定深度）\n'
      '   - 概算指标法（方案阶段）\n'
      '   - 类似工程预算法（有类似项目参照）\n'
      '2. 施工图预算的审查方法要重点掌握\n\n'
      '*距离考试还有 98 天，坚持每天刷题！*',
      title: '一造备考：计价第三章',
      tagIds: [upRoot.id!, kcTag.id!],
      attributeTagIds: [normalTag.id!],
      spaceId: 1,
    );

    // ==================== 入口 2：个人生活 ====================

    final lifeSpace = await db.createSpace('个人生活');
    final ls = lifeSpace.id!;

    // 项目分组
    final hg = await db.createProjectGroup('健康', ls);
    final fg = await db.createProjectGroup('家庭', ls);
    final sg = await db.createProjectGroup('兴趣', ls);

    // 项目
    final runProj = await db.createProject('跑步计划', groupId: hg.id, spaceId: ls);
    final cookProj = await db.createProject('学做菜', groupId: fg.id, spaceId: ls);
    final photoProj = await db.createProject('摄影入门', groupId: sg.id, spaceId: ls);
    await db.createProject('读书清单', groupId: sg.id, spaceId: ls);

    // 树状标签
    final lifeRoot = await db.createTag('日常生活', spaceId: ls);
    final foodTag = await db.createTag('饮食', parentId: lifeRoot.id, spaceId: ls);
    final cookTag = await db.createTag('做饭', parentId: foodTag.id, spaceId: ls);
    final eatingOut = await db.createTag('下馆子', parentId: foodTag.id, spaceId: ls);

    final sportTag = await db.createTag('运动', parentId: lifeRoot.id, spaceId: ls);
    final runTag = await db.createTag('跑步', parentId: sportTag.id, spaceId: ls);
    final bikeTag = await db.createTag('骑行', parentId: sportTag.id, spaceId: ls);

    final familyRoot = await db.createTag('家庭', spaceId: ls);
    final kidTag = await db.createTag('带娃', parentId: familyRoot.id, spaceId: ls);
    final parentTag = await db.createTag('父母', parentId: familyRoot.id, spaceId: ls);

    final hobbyRoot = await db.createTag('兴趣爱好', spaceId: ls);
    final readTag = await db.createTag('阅读', parentId: hobbyRoot.id, spaceId: ls);
    final photoTag = await db.createTag('摄影', parentId: hobbyRoot.id, spaceId: ls);

    // 属性标签
    final moodGroup = await db.createAttributeTagGroup('心情', ls);
    final placeGroup = await db.createAttributeTagGroup('地点', ls);

    final happyTag = await db.createAttributeTag('开心', groupId: moodGroup.id, spaceId: ls);
    final calmTag = await db.createAttributeTag('平静', groupId: moodGroup.id, spaceId: ls);
    final tiredTag = await db.createAttributeTag('疲惫', groupId: moodGroup.id, spaceId: ls);
    final outdoorTag = await db.createAttributeTag('户外', groupId: placeGroup.id, spaceId: ls);
    final homeTag = await db.createAttributeTag('家', groupId: placeGroup.id, spaceId: ls);
    final officeTag = await db.createAttributeTag('办公室', groupId: placeGroup.id, spaceId: ls);

    // ——— 入口 2 个人记录（跨 3 天）———

    // D-2
    await db.createEntry(
      '周末 **晨跑 10 公里** 完成！🏃\n\n'
      '- 配速：5′45″\n'
      '- 路线：沿河绿道来回\n'
      '- 本月跑量累计：*42 km*\n\n'
      '跑完在路边早餐店吃了 *豆浆油条*，满足。',
      title: '周末晨跑',
      tagIds: [lifeRoot.id!, sportTag.id!, runTag.id!],
      attributeTagIds: [happyTag.id!, outdoorTag.id!],
      projectId: runProj.id,
      spaceId: ls,
      createdAt: daysAgo(2),
    );

    await db.createEntry(
      '带女儿去 **科技馆** 玩了一天：\n\n'
      '- 恐龙展区看了 *半小时* 不肯走 🦕\n'
      '- 体验了 VR 过山车\n'
      '- 在科学实验区做了小火山喷发\n\n'
      '小家伙回家路上就睡着了。*\n'
      '孩子的快乐真简单。*',
      title: '带娃逛科技馆',
      tagIds: [familyRoot.id!, kidTag.id!],
      attributeTagIds: [happyTag.id!],
      spaceId: ls,
      createdAt: daysAgo(2),
    );

    // D-1
    await db.createEntry(
      '今天试做 **红烧牛腩**，成功！\n\n'
      '**步骤记录（方便下次复刻）：**\n'
      '1. 牛腩切块 **焯水** 去血沫\n'
      '2. 炒糖色：冰糖小火炒至琥珀色\n'
      '3. 加八角、桂皮、香叶、姜片爆香\n'
      '4. 加入料酒、生抽、老抽，加热水没过\n'
      '5. *小火慢炖 2 小时* 至软烂\n\n'
      '老婆说比外面餐厅的还好吃 😋',
      title: '红烧牛腩成功',
      tagIds: [lifeRoot.id!, foodTag.id!, cookTag.id!],
      attributeTagIds: [happyTag.id!, homeTag.id!],
      projectId: cookProj.id,
      spaceId: ls,
      createdAt: daysAgo(1),
    );

    await db.createEntry(
      '晚饭后去江边 **骑行** 了 15 公里 🚴\n\n'
      '- 第一次骑这么远，屁股疼\n'
      '- 江风很舒服，夜景很美\n'
      '- 下周挑战 20 公里',
      title: '夜骑 15 公里',
      tagIds: [lifeRoot.id!, sportTag.id!, bikeTag.id!],
      attributeTagIds: [happyTag.id!, outdoorTag.id!],
      projectId: runProj.id,
      spaceId: ls,
      createdAt: daysAgo(1),
    );

    // D-0：今天
    await db.createEntry(
      '下班路上用手机拍了几张 **日落** 🌇\n\n'
      '发现光影真的要靠 **等**。\n'
      '在桥上站了 15 分钟，拍到了满意的瞬间。\n\n'
      '-# 今日摄影心得\n'
      '- 黄金时刻（日落前 30 分钟）出片率最高\n'
      '- 手机摄影要点：低角度 + 三分构图\n'
      '- 后期用手机自带编辑就行，不用急着上 LR',
      title: '日落摄影练习',
      tagIds: [hobbyRoot.id!, photoTag.id!],
      attributeTagIds: [calmTag.id!, outdoorTag.id!],
      projectId: photoProj.id,
      spaceId: ls,
    );

    await db.createEntry(
      '今天工作有点累，*不想做饭*，\n'
      '在楼下兰州拉面馆吃了碗牛肉拉面 **加蛋**。\n\n'
      '和老板聊了几句，他们是甘肃人，\n'
      '一家人在城里开店十几年了。\n'
      '平凡人的生活，各有各的故事。',
      title: '楼下拉面馆',
      tagIds: [lifeRoot.id!, foodTag.id!, eatingOut.id!],
      attributeTagIds: [tiredTag.id!],
      projectId: cookProj.id,
      spaceId: ls,
    );
  }
}
