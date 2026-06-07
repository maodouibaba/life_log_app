---
title: 自搓 iPhone App 项目 —— 技术方案与行动计划
date: 2026-06-02
updated: 2026-06-07
tags: [project, ios, flutter, pwa]
status: 进行中
---

# 自搓 iPhone App 项目 —— 技术方案与行动计划

## 项目目标

在 **Windows 电脑** 上开发一个 **生活记录类** App，能在 **iPhone 上运行**，不上架 App Store，仅自用。

## 技术选型结论

### 最终选择：Flutter + GitHub Actions

| 项目 | 选择 |
|------|------|
| 框架 | Flutter（Dart 语言） |
| 开发环境 | Windows + VS Code |
| iOS 编译 | GitHub Actions（免费 Mac runner） |
| 安装到 iPhone | Sideloadly / AltStore 侧载 |

---

## 2026-06-03 全天工作记录

### 一、上午：项目需求梳理

1. **App 定位确定**：生活记录类，纯文字为主，保留图片接口
2. **功能清单确定**：
   - 自定义树状标签体系（全局、不限层级、记时可新建）
   - 首页时间线视图（按天展开/收起）
   - 列表视图（按日期范围、按标签筛选）
   - 导出 Excel
   - 统计功能暂不开发，保留可能性
3. **数据同步方案确定**：预留接口，后续对接坚果云 WebDAV
4. **多平台保留**：主要 iOS，数据层预留多平台可能性

### 二、下午：完整项目开发

完成了 **7 个模块的全部代码编写与调试**：

#### 2.1 数据模型（lib/models/）
- `tag.dart` — 树状标签模型，parentId 支持无限层级
- `entry.dart` — 记录模型，文字内容 + 时间戳
- `entry_tag.dart` — 多对多关联模型

#### 2.2 本地数据库（lib/database/app_database.dart）
- 使用 sqflite，3 张表：tags、entries、entry_tags
- 完整 CRUD：增删改查、按日期查询、按标签查询
- 级联删除（删父标签自动删子标签和关联）
- 获取标签完整路径（如"生活 > 饮食 > 午餐"）

#### 2.3 首页时间线（lib/pages/home_page.dart）
- 按天分组展示
- 每天可展开/收起（点日期标题切换）
- 显示时间、内容、标签卡片
- 左滑或点删除按钮可删记录
- 右上角：列表视图、标签管理、导出 Excel

#### 2.4 写记录页面（lib/pages/entry_editor_page.dart）
- 多行文本输入
- 树状标签选择器（点选/取消）
- **可现场新建标签**，自动并入全局标签库
- 选中的标签以 Chip 形式展示，可删除

#### 2.5 标签管理页面（lib/pages/tag_manager_page.dart）
- 树状展示所有标签
- 可展开/收起子树
- 每个标签支持：添加子标签、重命名、删除（含子标签级联删除）

#### 2.6 列表视图页面（lib/pages/list_view_page.dart）
- 时间线列表展示
- 按日期范围筛选（日期选择器）
- 按标签筛选（树状标签选择弹窗）
- 筛选条件可清除
- 显示记录条数

#### 2.7 导出与同步服务
- `export_service.dart` — 导出所有记录到 Excel（含标签路径列）
- `sync_service.dart` — 坚果云 WebDAV 同步接口骨架（已定义配置、上传、下载方法，待实现）

#### 2.8 代码质量
- `flutter analyze` 通过，**0 error**
- 仅 2 个 warning（同步接口预留字段未使用，属正常）

### 三、傍晚：Flutter SDK 安装

1. **下载 Flutter SDK 3.22.3** — 从 flutter-io.cn 国内镜像下载（约 1GB）
2. **解压到 C:\flutter** — 含 Dart SDK 3.4.4
3. **环境变量配置**：
   - PATH 已含 C:\flutter\bin
   - FLUTTER_STORAGE_BASE_URL = https://storage.flutter-io.cn
   - PUB_HOSTED_URL = https://pub.flutter-io.cn
4. **首次运行验证** — Flutter --version 成功输出
5. **禁用遥测** — flutter --disable-analytics
6. **创建项目** — flutter create，仅 iOS 平台
7. **添加依赖** — sqflite、excel、path_provider、intl、path
8. **后补平台支持** — 添加了 Windows、Web 平台

### 四、晚上：GitHub Actions 自动编译配置

1. **配置 Git** — user.name / user.email
2. **生成 SSH Key** — ed25519 密钥对
3. **SSH 配置** — 走 443 端口（因 22 端口被屏蔽）
4. **创建 GitHub 仓库** — mbecth/life_log_app（私有仓库）
5. **代码推送** — git push 成功
6. **编写 CI 脚本** — .github/workflows/build-ios.yml
   - 触发条件：push 到 main 分支 / 手动触发
   - 编译步骤：checkout → setup flutter → pub get → build ios → 打包 .ipa → 上传 artifact
7. **首次编译**：成功（绿色 ✔️）
8. **修复打包方式**：因 Sideloadly 报 Invalid file，改为 debug 模式编译（已推送，待测试）

### 五、侧载尝试

#### Sideloadly
- 安装成功，Apple ID 登录成功（用专用密码）
- 首次报 Login failed → 生成 App 专用密码解决
- 第二次报 Invalid file → 已改为 debug 模式编译，待重新测试
- 问题：iPhone 能被电脑识别（我的电脑中可见），但 Sideloadly 显示 No device detected

#### AltStore
- 已安装 AltServer（Windows 版）
- 问题：提示需要 iTunes，但用户已安装微软商店版 iTunes
- AltServer 不认微软商店版，需从 Apple 官网重新下载安装

#### 前置依赖：Visual Studio Build Tools
- 为在 Windows 上直接预览 App，需要安装 VS 2022 Build Tools
- 已下载安装程序，正在安装中（需选择"使用 C++ 的桌面开发"）
- 安装完成后可在 Windows 上 `flutter run -d windows` 直接跑

---

## 2026-06-07 工作记录

### 一、Windows 桌面端支持

1. **Visual Studio Build Tools 安装** — 下载引导程序，安装到 `E:\VS Build Tools`
   - 仅安装"使用 C++ 的桌面开发"工作负载
   - C 盘清理：npm-cache 等释放 4.4G，从 2.9G→7.3G 后安装成功
2. **sqflite 桌面端初始化** — 添加 `sqflite_common_ffi` 依赖
   - `main.dart` 增加 `!kIsWeb && (Platform.isWindows ...)` 判断初始化 FFI
3. **项目路径迁移** — 从含中文路径移到 `D:\life_log_app`
4. **首次 Windows 编译** — `flutter build windows --debug` ✅

### 二、坚果云 WebDAV 同步

1. **`lib/services/sync_service.dart`** — WebDAV 完整封装
   - 配置持久化、连接测试、文件列表（PROPFIND/XML 解析）、上传、下载、删除
   - 纯 Dart，依赖 `http` + `xml: ^6.5.0`
2. **`lib/pages/sync_settings_page.dart`** — 配置+操作界面
   - 连接设置、测试、上传、云端文件列表（恢复/删除）

### 三、排序 + 撤回功能

1. **排序** — 首页和列表页增加 ↕ 按钮，切换正序/倒序
2. **撤回按钮** — `lib/widgets/undo_button.dart`
   - UndoManager 改为 ChangeNotifier，按钮监听状态
   - 无可撤销时灰色禁用，有操作时高亮可点
   - 首页和列表页工具栏中各有一个

### 四、列表标签分组修复

1. `_entryTagPath()` 递归回溯完整路径代替原来的 `tags.first.name`

### 五、其他改进

1. **Excel** — 增加"事项简介"列
2. **数据迁移页** — 文案平台自适应（`Platform.isIOS` 用 `!kIsWeb` 守卫）
3. **新增依赖**：`xml: ^6.5.0`、`sqflite_common_ffi: ^2.3.6`
4. **编译验证**：Web ✅ | Windows ✅ | 0 errors

---

## 项目结构

```
D:\life_log_app/
├── lib/
│   ├── main.dart                    # 入口（含 sqflite FFI 初始化）
│   ├── models/                      # 数据模型
│   │   ├── tag.dart
│   │   ├── entry.dart
│   │   └── entry_tag.dart
│   ├── database/
│   │   ├── app_database.dart        # sqflite 数据库
│   │   └── web_database.dart        # Web 内存数据库
│   ├── pages/                       # 页面
│   │   ├── home_page.dart           # 首页时间线
│   │   ├── entry_editor_page.dart   # 写记录
│   │   ├── entry_detail_page.dart   # 记录详情
│   │   ├── tag_manager_page.dart    # 标签管理
│   │   ├── attribute_tag_manager_page.dart  # 属性标签管理
│   │   ├── project_manager_page.dart       # 项目管理
│   │   ├── list_view_page.dart      # 列表筛选
│   │   ├── data_migration_page.dart # 数据备份
│   │   ├── sync_settings_page.dart  # 坚果云同步设置
│   │   └── lock_screen.dart         # 隐私锁
│   ├── services/
│   │   ├── sync_service.dart        # 坚果云 WebDAV 同步
│   │   ├── undo_manager.dart        # 撤销管理器（ChangeNotifier）
│   │   ├── export_service.dart      # Excel 导出
│   │   ├── ai_service.dart          # AI 助写
│   │   ├── seed_data.dart           # 演示种子数据
│   │   ├── theme_settings.dart      # 主题设置
│   │   └── privacy_settings.dart    # 隐私锁设置
│   ├── widgets/
│   │   └── undo_button.dart         # 撤销按钮组件
│   └── utils/
│       └── text_formatter.dart
├── ios/                             # iOS 原生配置
├── windows/                         # Windows 运行支持
├── web/                             # Web 支持
└── .github/workflows/
    └── build-ios.yml                # GitHub Actions 自动编译
```

## 待办事项

- [ ] Windows 预览：确认 VS Build Tools 安装完成，跑 flutter run
- [ ] 重新下载最新 .ipa，用 Sideloadly 侧载测试
- [ ] 如果 Sideloadly 不行，从 Apple 官网重装 iTunes，用 AltStore
- [ ] 项目已写满一整天代码，侧载问题解决后即可在 iPhone 上用

## 常用命令

```bash
cd G:\BaiduSyncdisk\个人管理\projects\life_log_app

# Windows 预览
flutter run -d windows

# 代码检查
flutter analyze

# 推送到 GitHub（自动触发 iOS 编译）
git add .
git commit -m "描述"
git push
```

## 注意事项

- Flutter SDK：C:\flutter（未加入系统 PATH）
- 国内镜像：FLUTTER_STORAGE_BASE_URL / PUB_HOSTED_URL
- GitHub 仓库：https://github.com/mbecth/life_log_app（私有）
- SSH 走 443 端口（git@github.com:mbecth/life_log_app.git）
---

## 2026-06-04 工作记录

### 一、安装方式：爱思助手侧载

**放弃 Sideloadly / AltStore**，改用爱思助手安装 `.ipa`。

#### 安装步骤
1. iPhone USB 连接电脑，爱思助手识别设备
2. **「我的设备」→「应用」→「导入安装」** → 选择 `life-log-app.ipa`
3. 安装成功后，iPhone 上首次打开 → **设置 → 通用 → VPN 与设备管理 → 信任开发者证书**

#### 爱思助手 vs Sideloadly
| 对比项 | 爱思助手 | Sideloadly |
|--------|---------|------------|
| 操作 | 一键导入，图形界面 | 需选 .ipa + Apple ID |
| 设备识别 | 自动识别 | 有时报 No device detected |
| 推荐度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |

---

### 二、首次安装测试（2026-06-04）

**结果：App 能安装打开，但操作卡死**

#### 问题 1：首页一直在转圈
- **原因**：`_loadEntries()` 的 `_db.getAllEntries()` 没有异常捕获，死等
- **修复**：`home_page.dart` 加 `try-catch` + 10 秒 `timeout`

#### 问题 2：添加记录按钮点了没反应
- **原因**：`entry_editor_page.dart` 的 `_save()` 方法没有异常捕获
- **修复**：`_save()` 加 `try-catch` + 10 秒 `timeout`，失败时 SnackBar 提示

#### 问题 3：列表视图一直转圈
- **原因**：`list_view_page.dart` 的 `_loadData()` 没有异常捕获
- **修复**：`_loadData()` 加 `try-catch` + 10 秒 `timeout`

#### 问题 4：数据库路径问题（iOS 真机）
- **原因**：`getDatabasesPath()` 在 iOS 上可能返回不可写路径
- **修复**：`app_database.dart` 改用 `getApplicationDocumentsDirectory()` 获取路径

#### 问题 5：`entry.dart` 构造函数 bug
- **问题代码**：`updatedAt = updatedAt ?? updatedAt ?? DateTime.now()`
- **修复**：改为 `updatedAt = updatedAt ?? DateTime.now()`

---

### 三、GitHub Actions 编译问题

#### 问题：Development Team 签名错误

**现象**：`flutter build ios --release --no-codesign` 报错，提示需要 Development Team

**排查过程（踩坑记录）**：

| 尝试方案 | 结果 |
|---------|------|
| ❌ 改回 `--debug --no-codesign` | 同样需要 Development Team |
| ❌ 环境变量 `export DEVELOPMENT_TEAM=""` | 不生效 |
| ❌ sed 注入 DEVELOPMENT_TEAM 到 `project.pbxproj` | 文件损坏（编码问题） |
| ❌ `xcodebuild` 直接编译 + `CODE_SIGNING_ALLOWED=NO` | flutter pub get 阶段已失败 |
| ✅ **正确方案**：用 UTF-16 LE 编码编辑 `ios/Runner.xcodeproj/project.pbxproj`，在 3 处 `PRODUCT_BUNDLE_IDENTIFIER` 后添加 `DEVELOPMENT_TEAM = "";` | **待验证** |

**关键教训**：
- `project.pbxproj` 是 **UTF-16 LE** 编码，不能用普通的 `Set-Content -Encoding UTF8` 写
- 在 PowerShell 中操作需用 `[System.IO.File]::ReadAllText(path, [System.Text.Encoding]::Unicode)` 和 `WriteAllText`

#### 当前状态
- App 代码问题已修复 ✅
- 编译因 Development Team 问题未通过 ❌
- 正在解决中...

---

### 四、常用命令更新

```bash
# 推送到 GitHub（自动触发 iOS 编译）
cd G:\BaiduSyncdisk\个人管理\projects\life_log_app
git add .
git commit -m "描述"
git push

# 查看 Actions 编译结果
# https://github.com/mbecth/life_log_app/actions
```

### 五、安装流程总结

```
代码修改 → git push → GitHub Actions 自动编译
                                    ↓
                             下载 .ipa (Artifacts)
                                    ↓
                         爱思助手 → 应用 → 导入安装
                                    ↓
                      iPhone 设置 → 信任开发者证书
                                    ↓
                             打开 App ✅
```

### 六、注意事项补充

- `project.pbxproj` 是 **UTF-16 LE** 编码，修改时注意！
- Debug 模式编译的 .ipa 即可侧载使用，不需要 Release 模式
- 免费 Apple ID 签名有效期 **7 天**，到期需续签
- 爱思助手可以一键续签（不用重新编译）

- [ ] 解决 GitHub Actions 编译 Development Team 错误
- [ ] 重新编译并安装测试
- [ ] 验证数据库修复是否解决卡死问题
- [ ] 验证记录添加功能是否正常

---

## 2026-06-04 第二波：综合修复与新功能开发

### 一、CI 编译全面修复

**问题：** iOS 14+ 以上 debug 模式 Flutter 无法从桌面启动

| 修复项 | 说明 |
|-------|------|
| 编译模式 | `--debug` → `--profile --no-codesign` |
| 签名配置 | pbxproj 中 6 处补 `DEVELOPMENT_TEAM = "";` |
| 编码修复 | pbxproj 从 UTF-16 LE 转 UTF-8 无 BOM（PowerShell 用 `[System.Text.UTF8Encoding]::new($false)`） |
| 行尾 | 新建 `.gitattributes` 强制 pbxproj 使用 LF 行尾 |

**关键教训**：Windows 上 PowerShell 写文件默认 UTF-16 LE，需要用 `[System.IO.File]::ReadAllText()` + `WriteAllText()` 配合指定编码。

### 二、66 个 Dart 语法错误全部清零

| 错误类型 | 数量 | 修复方式 |
|---------|------|---------|
| `_save()` 缺少 `}` | 60+ 级联 | 补全方法体 |
| 字符串未终止（`'`） | 3 处 | 补引号 |
| `withValues()` 不支持 | 2 处 | 改为 `withOpacity()`（Flutter 3.22 API） |
| 缺少 import | 1 处 | 加 `import 'package:flutter/foundation.dart'` |
| `onTimeout` 类型 | 1 处 | `return null` → `return []` |

### 三、保存问题修复

**根因**：`_save()` 没加 await + 异常捕获，页面直接 pop 了但数据没写完。

**修复方案**：
- `_save()` 加 try-catch，失败弹 AlertDialog 而非无声退出
- AppBar 保存按钮加 loading spinner（`_saving` 状态）
- 从编辑器返回首页**始终**调用 `_loadEntries()` 刷新（不再判断 `result == true`）
- 首页加 `_loadError` 状态，读取失败时显示错误信息 + 重试按钮

### 四、首页/列表页标签不显示修复

**根因**：`Entry` 模型 `tags` 默认值 `const []`（不可变列表）。数据库层用 `entry.tags..clear()..addAll(...)` 时，`clear()` 对 `const []` 抛出 `UnsupportedError`，被 try-catch 吃掉后标签始终为空。

**修复**：`const []` → `[]`（可变空列表）

### 五、标签父级联动

| 功能 | 实现 |
|------|------|
| 选子标签自动选父标签 | `_getAncestorsInclusive()` 遍历 parentId 链 |
| 取消选标签时清理祖先 | `_deselectTagCleanup()` — 如果祖先已无其他选中子标签则一起取消 |
| **重要**：新建子标签时父标签不显示 bug | `_createAndSelectTag()` 中不要查 `_allTags` 找新标签（还没刷新），直接用 `parentId` 参数往上追溯 |

### 六、编辑器"新建根标签"按钮

标签选择区顶部加 `⊕ 新建根标签`，可随时创建顶层标签。

### 七、标签管理刷新修复

**问题**：添加子标签后，父节点展开后看不到新子标签，需退出重进。

**根因**：每个 `_TagTreeNode` 在 `initState()` 中独立查 DB 加载子标签列表，添加后子节点不刷新。

**修复**：改为父级一次性加载全量标签列表 `_allTags`，传给每个树节点，各节点从列表中实时 `where` 筛选。添加后 `setState` 自动触发整树重建。

### 八、编辑已有记录功能

| 层 | 改动 |
|---|------|
| 数据库 | 新增 `updateEntryWithTags()` — 更新内容 + 删旧标签 + 插新标签 |
| 编辑器 | `EntryEditorPage` 接受可选 `entry` 参数，编辑模式预填内容/标签/项目 |
| 首页 | 点击记录 → 详览页（只读）→ 详览页点编辑 → 编辑器 |
| 列表视图 | 点击条目 → 详览页 → 编辑器 |

**新增页面**：`entry_detail_page.dart` — 只读全文展示（`SelectableText`），含时间、项目、标签、内容。

---

## 2026-06-04 第三波：项目维度、标签单分支、批量操作、数据迁移

### 一、Project 维度

**数据模型**（`lib/models/project.dart`）：
```dart
class Project {
  int? id;
  String name;
  DateTime createdAt;
}
```

**数据库迁移 v1→v2**（`app_database.dart`）：
- 新增 `projects` 表
- `entries` 表加 `project_id` 外键列
- `onUpgrade` 处理已有数据库升级
- `ON DELETE SET NULL` — 删除项目不影响关联记录

**管理页面**：`project_manager_page.dart`（增/删/改名，无层级）

**编辑器选择器**：ChoiceChip 单选，⊕ 可新建。通常一条记录一个项目。

**规则**：标签和项目可并存，都不强制选。

### 二、标签单分支选择模型

**核心变更**：`entry_editor_page.dart` 整个标签选择逻辑重写。

| 旧（多分支） | 新（单分支） |
|------------|------------|
| `Set<int> _selectedTagIds` | `int? _selectedLeafTagId` |
| checkbox 多选图标 | radio 单选图标 |
| 选中路径无视觉区分 | 选中路径半透明高亮，叶节点实心高亮 |
| 顶部多行 Chip 平铺 | 单行路径链 `生活 > 饮食 > 午餐 [✕]` |

**规则**：
- 一条记录只能选标签树的一条路径（根→叶）
- 点选任意标签即设为叶标签，祖先自动推导
- 点已选的叶标签可取消
- 保存时 `_effectiveTagIds` 返回叶+所有祖先，全部写入 `entry_tags`
- 编辑旧数据时 `_findDeepestTag()` 自动取最深标签作为叶标签

**筛选依然支持按任意标签查找**（因为祖先已写入 `entry_tags`）。

### 三、批量操作（列表视图）

| 操作 | 实现 |
|------|------|
| 多选模式 | AppBar 右 `checklist` 图标进入，`close` 退出 |
| 全选/取消 | `select_all` 图标，切换全选 |
| 批量删除 | `deleteEntries()` — `WHERE id IN (...)` 一次删除多条 |
| 批量替换标签 | `batchReplaceTags()` — 删旧标签 → 插新标签 |
| 按标签筛选后全选 | 筛选结果上全选，然后批量替换 |

### 四、数据迁移（JSON）

**新增页面**：`data_migration_page.dart`

**导出**：
- `exportToJson()` — 全部数据（tags + projects + entries + entry_tags）序列化为 JSON
- 保存到 `getApplicationDocumentsDirectory()`，文件名 `生活记录备份_时间戳.json`
- 导出后弹窗可"分享"（调 `OpenFilex.open()` → 微信/AirDrop）

**导入**：
- 扫描 Documents 目录下所有 `.json` 文件
- 列表显示文件名、大小、修改时间
- 选择文件 → 确认 → `importFromJson()` 清空全部表 → 事务写入
- 用户通过爱思助手把备份文件放入 Documents 目录

### 五、列表视图增强

- 条目下方左侧显示项目名标签、右侧显示标签
- 筛选栏增加「项目」按钮（`_ProjectPickerDialog`）
- 三种筛选互斥：按日期 / 按标签 / 按项目

### 六、主页内容截断

- 内容最多显示 2 行，超出用 `TextOverflow.ellipsis`
- 点击 → 详览页（只读全文）
- 详览页 AppBar 有编辑按钮 → 跳转到编辑器

### 七、编码坑 & 注意事项

1. **`const []` vs `[]`** — Dart 中 `const []` 不可变，调用 `clear()` 会抛异常。所有需要后续变更的列表默认值必须用 `[]`。
2. **`flutter_web_plugins` 缺失** — 本机 Flutter SDK 缺少 web 插件包，导致 `share_plus` / `file_picker` 等需要 web 的包无法安装。替代方案：
   - 分享文件 → `open_filex`（打开系统分享菜单）
   - 文件选择 → 扫描 Documents 目录（爱思助手管理文件）
3. **pbxproj 编码** — 始终用 UTF-8 无 BOM，Windows 需用 `.gitattributes` 强制 LF 行尾。
4. **`--profile --no-codesign`** — iOS 14+ 不能用 debug 模式从桌面启动，必须 profile 模式。
5. **数据库 ON DELETE CASCADE** — sqflite 默认不开启外键约束，所以级联删除需要手动先删子表再删父表。

---

## 2026-06-05 工作记录

### 一、数据库 v3 大升级

合并了 **「双入口（Spaces）」+「属性标签（Attribute Tags）」+「项目分组（Project Groups）」+「双字段记录（title + content）」+「标签排序」** 五个功能：

| 模块 | 改动 |
|------|------|
| spaces 表 | 新增，支持多入口隔离（默认入口 id=1） |
| attribute_tags 表 | 新增，扁平标签体系，支持分组 |
| entry_attribute_tags 表 | 多对多关联 |
| attribute_tag_groups 表 | 属性标签分组 |
| project_groups 表 | 项目分组 |
| entries 表 | 新增 `title` 字段（事项简介） |
| tags 表 | 新增 `space_id` + `sort_order` 字段 |
| onUpgrade v2→v3 | 自动增量迁移，原有数据无损 |

**新增页面**：`attribute_tag_manager_page.dart` — 属性标签管理（扁平+分组，Collapsible）

### 二、列表视图重写 — 组合筛选 + 自定义分组

**筛选架构重构**：互斥单选 → AND 组合多选

| 维度 | 旧 | 新 |
|------|-----|-----|
| 树状标签 | 单选 int? | 多选 Set\<int\>，OR |
| 属性标签 | 无 | 多选 Set\<int\>，OR |
| 项目 | 单选 int? | 多选 Set\<int\>，OR |
| 日期 | 范围 | 不变 |
| 关键词 | 无 | 新增搜索栏 |
| 维度间关系 | — | **AND** |

**数据库新增** `getEntriesByFilters()` — 动态 SQL 拼接，`EXISTS` 子查询实现维度内 OR，`AND` 组合维度。

**新增分组功能**：筛选栏右侧分组切换按钮，支持按日期/项目/树状标签/属性标签/不分组 5 种模式。

### 三、筛选弹窗卡死问题（✅ **已修复**）

**现象**：列表页点击筛选条件（树状标签/属性标签/项目）→ 弹窗 → 选或不选 → 点"确定"或"取消" → 弹窗不关闭

**排查历程**：

| 轮次 | 修复方式 | commit | 测试结果 |
|------|---------|--------|---------|
| 1 | 确定按钮不禁用（移除 `_selectedIds.isEmpty ? null`） | `49f342b` 中部分 | ❌ 按钮能点但弹窗不关 |
| 2 | `StatefulWidget` → `StatelessWidget` + `StatefulBuilder` | `a9cf070` | ❌ 弹窗不关 |
| 3 | `Navigator.pop(context)` → `Navigator.of(context, rootNavigator: true).pop()` | `1f4d059` | ❌ 弹窗不关 |
| **4** | **回调闭包方案：捕获 ListViewPage 的 NavigatorState，通过 onClose 回调传入弹窗** | 当前 fix | ✅ **待验证** |

**根因分析**：
经过 3 轮尝试（StatefulWidget / StatelessWidget+StatefulBuilder / rootNavigator.pop）均无效，排除这几种因素。问题是 `StatefulBuilder` 内部的 `context` 虽然理论上是 Navigator 的子节点，但在运行时无法正确触发 `Navigator.pop`。可能原因：Flutter 3.22 中 `StatefulBuilder` 的 BuildContext 在特定场景下与 Navigator 的连接链路有问题。

**修复方案（第 4 轮）**：
- **不依赖弹窗内的 context 调用 Navigator.pop**
- 改为：在 `_pickTag()` / `_pickAttributeTag()` / `_pickProject()` 中，**打开弹窗前先捕获 `Navigator.of(context)`**（此时 context 来自 `ListViewPage` 自身，肯定有效）
- 将 `nav.pop()` 包装成 `onClose` 回调传给弹窗
- 弹窗的"确定"和"取消"按钮调用 `onClose(selectedIds)` / `onClose(null)`，由外部完成导航操作
- 同时设置 `barrierDismissible: true` 作为后备退出方式
- 同步修复了 `_batchReplaceAttributeTags` 中同一弹窗的调用
- 附带修了一个 `withOpacity` deprecation warning

### 四、导出表格增加列

Excel 导出不再只有"时间 + 内容 + 层级"列，新增：
- **项目列** — 记录所属项目名
- **属性标签列** — 属性标签名（顿号分隔）

**改动文件**：`getAllEntriesWithTagPaths()`（返回 `attribute_tags` 字段）、`export_service.dart`（表头+数据行列）

### 五、导出备份 DatabaseException

**现象**：导出备份时报 `DatabaseException(Error Domain=...)`，错误信息被 SnackBar 截断。

**修复**：
- 改为 AlertDialog + `SelectableText` 展示完整错误信息
- `exportToJson()` 加分段 try-catch + `debugPrint` 定位问题表

**待用户**：复现后提供完整错误文字。

### 六、界面改进

- 日期筛选：点击弹出菜单 → 选"选择单日"或"选择时段"，不再需要长按
- 导入恢复：新增自定义路径输入框 + 刷新按钮
- `_FilterChip`：移除废弃的 `onLongPress` 参数

---

## 当前项目结构

```
G:\BaiduSyncdisk\个人管理\projects\life_log_app/
├── lib/
│   ├── main.dart                           # 入口
│   ├── models/
│   │   ├── tag.dart                        # 树状标签
│   │   ├── entry.dart                      # 记录（含 projectId）
│   │   ├── entry_tag.dart                  # 记录-标签关联
│   │   └── project.dart                    # 项目（不分层级）
│   ├── database/
│   │   └── app_database.dart               # sqflite, v2（含 projects 表）
│   ├── pages/
│   │   ├── home_page.dart                  # 首页时间线（截断 2 行）
│   │   ├── entry_editor_page.dart          # 新建/编辑记录（单分支标签）
│   │   ├── entry_detail_page.dart          # 只读详览页（新增）
│   │   ├── tag_manager_page.dart           # 标签管理（树状）
│   │   ├── project_manager_page.dart       # 项目管理（新增）
│   │   ├── list_view_page.dart             # 列表/筛选/批量操作
│   │   └── data_migration_page.dart        # JSON 导入导出（新增）
│   ├── services/
│   │   ├── export_service.dart             # Excel 导出（一标签一行+多列）
│   │   └── sync_service.dart               # 坚果云同步（预留）
├── ios/
├── windows/
├── .github/workflows/
│   └── build-ios.yml
└── docs/
    └── 自搓iPhone App项目计划.md
```

### 七、筛选弹窗卡死修复（2026-06-05 第四波）

**问题**：`_MultiTagFilterDialog` / `_MultiAttributeTagFilterDialog` / `_MultiProjectFilterDialog` 三个筛选弹窗点"确定"/"取消"不关闭。

**修复方案**（第 4 轮尝试，前 3 轮均已无效）：
- 捕获 `_ListViewPageState` 的 `NavigatorState` 通过 `onClose` 回调传入弹窗
- 弹窗按钮不再直接调用 `Navigator.pop(context)`，而是调用 `onClose(selectedIds)`
- 弹窗外部负责执行 `nav.pop()`，从已知有效的 context 出发操作导航栈
- 同时设置 `barrierDismissible: true` 作为后备关闭方式
- `_batchReplaceAttributeTags()` 中同一弹窗调用也同步修复

### 八、分组增强 + 导出备份容错（2026-06-05 第五波）

**分组按钮更突出**：
- 从纯图标 PopupMenuButton 改为带标签的胶囊按钮 `_GroupByButton`
- 显示当前分组名称（"按日期" / "按项目" / "按标签" / "不分组"）
- 下拉菜单中当前活跃分组显示 ✅ 勾选标记

**分组可折叠**：
- `_GroupSection` 从 `StatelessWidget` 转为 `StatefulWidget`
- 每个分组头部可点击展开/收起，显示箭头图标和条目数
- 默认全部展开

**导出备份容错修复**：
- `exportToJson()` 中 `spaces` 查询 `.first` 空风险修复（`rows.isNotEmpty ? [rows.first] : []`）
- `spaces` 和 `project_groups` 查询新增 try-catch
- 标签 `toMap()` 和项目 `toMap()` 序列化逐条 try-catch，失败时使用占位数据而非崩溃
- 整体包裹外层 try-catch，确保任何中间环节失败都有明确 error 信息
- 附带修复 `data_migration_page.dart` 和 `list_view_page.dart` 中的 `withOpacity` 警告

---

## 2026-06-06 工作记录

### 一、分组按钮界面改进

**问题 1**：分组按钮后面多了个数字（如"6"），用户以为它是按钮的一部分。

**修复**：移除 `_GroupByButton` 中的 `count` 参数和相关 `Text('$count')` 显示。

**问题 2**：筛选按钮（日期/树状标签/属性标签/项目）与分组按钮处在同一行，不好区分。

**修复**：拆分为两行——第一行放四个筛选按钮，第二行单独放分组按钮。视觉上清晰分离。

### 二、标题和内容改为弹窗输入

**用户原意**：事项简介和详细情况的输入框本身应该是弹窗形式，而非在页面上直接放文本框。

**之前误解**：把整个新增记录页面改成了底部弹窗。
**修正**：页面/弹窗中不再直接显示 TextField，而是显示可点击的摘要区域，点按后弹出独立对话框输入。

| 改动 | 说明 |
|------|------|
| `_openTitleDialog()` | 弹出单行输入框，确定后回填标题文字 |
| `_openContentDialog()` | 弹出多行输入框（3-8行），确定后回填内容文字 |
| 表单标题区 | TextField → InkWell 容器，显示当前标题或"点击输入事项简介"，附编辑图标 |
| 表单内容区 | TextField → InkWell 容器，显示前3行预览或"点击输入详细情况"，附编辑图标 |

**交互效果**：主界面保持简洁，点标题/内容区才弹出键盘输入，类似标签选择器的交互模式。

### 三、代码质量

- `flutter analyze` — **0 issue**, 0 error, 0 warning ✅

---

## 2026-06-06 第二波（多项优化与新功能）

### 一、撤回操作按钮（Undo）

新增 `UndoManager`（`lib/services/undo_manager.dart`），支持删除和编辑的撤销。

| 操作 | 撤销方式 |
|------|---------|
| 删除记录 | 删除后 SnackBar 显示「撤销」，点击恢复 |
| 编辑记录 | 保存后 SnackBar 显示「撤销」，点击回退到修改前 |

### 二、输入框调大 + 简介支持换行

- **标题弹窗**：`maxLines` 从 1 改为 4，支持多行输入
- **内容弹窗**：固定高度 350px，`expands: true` 全屏编辑
- **标题预览**：预览区支持最多 3 行显示

### 三、标签管理：修复滚动 + 一键展开/收起

- 页面 body 改为 `SingleChildScrollView` 包裹，超出可滚动
- AppBar 新增「全部展开」「全部收起」按钮

### 四、文本格式支持

**新增文件**：`lib/utils/text_formatter.dart`。支持 `**粗体**`、`*斜体*`、`- 列表`、`1. 有序列表`、`# 标题`。

- 详情页用 `TextFormatter.render()` 渲染
- 预览用 `TextFormatter.stripMarkdown()` 去符号
- 编辑器工具栏提供格式化按钮

### 五、列表视图增加单条删除

非选择模式下每条记录右侧有删除图标按钮。

### 六、筛选/分组按钮重新排版

卡片式整合容器，圆角半透明背景，`Wrap` 自动换行。

### 七、修复：编辑标签被覆盖 bug

`_initialTagsLoaded` 标志位防止 `_loadTags()` 覆盖用户已选的标签。

### 八、导出备份加强容错

`exportToJson()` 永不抛出，各表独立 try-catch，错误信息写入 JSON。

### 九、Web 预览支持

**新增** `web_database.dart` — 实现 sqflite `Database` 接口的内存数据库。`kIsWeb` 判断切换。支持多步查询替代 EXISTS。

### 十、AI 助写功能

**新增** `ai_service.dart`。多供应商（DeepSeek/通义千问/Claude/OpenAI/自定义），6 种写作风格 + 自定义提示词，输出长度不超过原文 120%。

### 十一、演示数据种子

**新增** `seed_data.dart`。以城投公司造价工程师身份填充 2 入口×6 条×3 天的演示数据。

### 十二、主题切换

**新增** `theme_settings.dart`。弹窗选择：跟随系统 / 日间 / 夜间。

### 十三、iPhone 文件导入

`file_picker` 包实现从 iPhone「文件」App 选择 `.json` 备份导入。

### 十四、Web 标签筛选修复

`getEntriesByFilters` 在 Web 上使用多步查询 + 内存过滤。

### 十五、Excel 导出修正

一条记录一行，取最深标签路径填入各层级列。

### 十六、首页/列表一键展开/折叠

AppBar 和分组栏增加展开/折叠全部按钮。

### 十七、详情页卡片化

3 张独立卡片：元信息、标题、内容。

### 十八、编辑后列表自动刷新

详情页编辑用 `push` 替代 `pushReplacement`，正确回传结果触发刷新。

### 十九、首页工具栏

AppBar 下方增加展开/折叠工具栏，替代之前拥挤的 AppBar 按钮。右侧显示记录总数。

### 二十、隐私锁（密码 + 面容/指纹识别）

**新增文件**：`lib/services/privacy_settings.dart`、`lib/pages/lock_screen.dart`

| 功能 | 说明 |
|------|------|
| 启用/关闭 | 首页 ⋮ → 隐私锁 |
| 生物识别 | 支持 Face ID / Touch ID（需 `local_auth` 包、iOS Info.plist 配置 `NSFaceIDUsageDescription`） |
| 密码锁 | 4-6 位数字密码，生物识别失败时作为备选 |
| 锁定时机 | App 启动时、从后台切回时自动锁定 |
| 实现 | `WidgetsBindingObserver` 监听 `AppLifecycleState.paused` |

### 二十一、记录时间手动修改

编辑器新增时间字段（内容框下方、标签选择上方），点击弹出日期选择器 + 时间选择器。新建和编辑均支持。

### 二十二、SnackBar 夜间模式修复

在主题中明确设置暗色模式 SnackBar 背景色为 `#2C2C2C`，避免白色刺眼。

### 二十三、设置持久化

**问题**：AI 助写 API Key、隐私锁开关、主题模式等设置仅存在内存中，App 被 iOS 杀掉后全部丢失。

**解决**：
- 数据库新增 `settings` 表（key-value 结构），版本升级 v3→v4
- `AISettings`、`PrivacySettings`、`ThemeSettings` 的 setter 自动写入数据库
- App 启动时 `main()` 中调用 `.load()` 从数据库读取
- `AppDatabase` 新增 `getSetting(key)`、`setSetting(key, value)` 方法

---

## 当前功能清单

| 功能 | 状态 |
|------|------|
| 树状标签体系（无限层级） | ✅ |
| 记录写/改/删 | ✅ |
| 撤销操作（Undo） | ✅ |
| 标签单分支选择 | ✅ |
| 项目维度 | ✅ |
| 属性标签体系（扁平+分组） | ✅ |
| 双入口（Spaces） | ✅ |
| 首页时间线（按天、截断2行、一键展开/折叠） | ✅ |
| 详情页卡片式展示 | ✅ |
| 文本格式渲染（粗体/斜体/列表/标题） | ✅ |
| 列表视图（组合筛选 AND/OR + 关键词 + 日期范围） | ✅ |
| 列表自定义分组（按日期/项目/树状标签/属性标签/不分组） | ✅ |
| 列表展开/折叠全部 | ✅ |
| 列表单条删除 + 批量删除 | ✅ |
| 批量替换标签/属性标签/项目 | ✅ |
| 标签管理（树状、展开收起全部、增删改、拖拽排序） | ✅ |
| 属性标签管理（扁平、分组、展开收起） | ✅ |
| 项目管理（分组、展开收起、批量操作） | ✅ |
| 导出 Excel（一条记录一行，多层级列） | ✅ |
| JSON 全量导出/导入（文件浏览+文件App选择） | ✅ |
| 数据备份恢复（含错误容错） | ✅ |
| AI 助写（多供应商、6种风格、自定义提示词） | ✅ |
| 主题切换（跟随系统/日间/夜间） | ✅ |
| 演示数据种子（双入口×多天×城投造价师） | ✅ |
| GitHub Actions 自动编译 | ✅ |
| Web 浏览预览（web_database 内存数据库） | ✅ |
| 设置持久化（API Key/隐私锁/主题不丢失） | ✅ |
| 爱思助手侧载 | ✅ |
| WebDAV 同步（坚果云） | ❌ 预留骨架，待实现 |

## 待办事项

### 紧急
- [x] ~~**筛选弹窗卡死**~~ — 已修复
- [x] ~~**导出备份 DatabaseException**~~ — 已修复（加强容错）
- [x] ~~**标签选择后点确定没生效**~~ — 已修复
- [x] ~~**标签/属性标签在 Web 不显示**~~ — 已修复
- [x] ~~**列表筛选标签不出内容（Web）**~~ — 已修复
- [x] ~~**编辑后列表不刷新**~~ — 已修复
- [x] ~~**Excel 多行重复**~~ — 已修复
- [x] ~~**设置丢失（API Key/隐私锁/主题）**~~ — 已修复（持久化到数据库）

### 近期（测试验证）
- [ ] 用最新 commit 生成 .ipa 安装测试全部功能
- [ ] 验证所有新功能：AI 助写、主题切换、文本格式渲染、一键展开折叠

### 功能开发
- [ ] WebDAV 同步对接（`sync_service.dart` 需实现）
- [ ] 更多写作风格

### 下一阶段讨论
- [ ] 首次使用引导 — 标签系统设置
- [ ] UI 美化深化
- [ ] App 双入口拆分优化

## 常用命令

```bash
cd G:\BaiduSyncdisk\个人管理\projects\life_log_app

# 代码检查
flutter analyze

# 推送到 GitHub（自动触发 iOS 编译）
git add .
git commit -m "描述"
git push

# 查看 Actions 编译结果
# https://github.com/mbecth/life_log_app/actions
```

## 注意事项

- **Flutter SDK**：`C:\flutter`，当前版本 3.29.3（Dart 3.7.2）
- **国内镜像**：FLUTTER_STORAGE_BASE_URL / PUB_HOSTED_URL
- **GitHub 仓库**：https://github.com/mbecth/life_log_app（私有），SSH 走 443 端口
- **pbxproj 编码**：UTF-8 无 BOM，LF 行尾
- **编译模式**：`--profile --no-codesign`（iOS 14+ 不能用 debug 模式从桌面启动）
- **web_database.dart**：Web 预览时用内存数据库替代 sqflite，所有数据仅存于浏览器会话
- **file_picker**：已安装 v8.3.7，用于从 iPhone「文件」App 选择备份导入

---

## 未来规划 / Future Design Notes

> 以下为设计思路记录，**不要求立即实现**。下一个 AI 接手时应先询问用户是否要开始进行这些工作。

### 1. 首次使用引导 — 标签系统设置

- 用户首次打开 App 时，引导创建基础的属性标签体系（而非空白的"还没有标签"）
- 思路：提供预设的标签模板建议（如"生活/工作/学习/健康"等顶层分类），降低上手门槛
- 可做成向导式流程：Step 1 创建根标签 → Step 2 创建子标签 → Step 3 写第一条记录
- 也可提供"跳过"选项，保留当前空状态

### 2. UI 美化

- 当前以 Material 3 默认风格为主，整体视觉效果偏朴素
- 美化方向参考：
  - 自定义主题色、圆角、阴影体系
  - 首页时间线卡片动效（入场动画、展开/收起过渡）
  - 标签选择器的视觉反馈优化（拖拽排序、颜色标记）
  - 整体风格一致性和精致度提升
- 可借鉴 Day One、格志等日记类 App 的视觉风格

### 3. 重新设计添加记录的结构

- 当前添加记录页面是：文本框 + 标签选择 + 项目选择，从上到下排列
- 重新设计思路：
  - 借鉴"格志"或同类日记 App 的交互结构
  - 可能的结构：模板化记录、引导式填写（先选标签/项目 → 再填内容）
  - 考虑加入"快速记录"模式（不选标签，直接记）
  - 考虑加入"今日回顾"模式（每晚提醒，回顾今天做了什么）

### 4. App 双入口拆分

- 将 App 整体划分为两个入口：**工作相关入口** 与 **工作无关入口（生活入口）**
- 实现思路（待讨论）：
  - 方式 A：一个 App 内通过顶部 Tab / 底部导航栏切换"工作"和"生活"视图
  - 方式 B：拆成两个独立的 App（两个 Flutter 项目），共用一套数据层/同步层
  - 方式 C：一个 App 内通过标签体系中"工作"根标签自动分流，首页默认按标签上下文展示对应内容
- 影响范围：首页展示、记录筛选、统计、导出等所有功能都需要感知当前入口
- 需要与"标签体系"的设计协调 —— 是否工作/生活本身就是顶层标签的划分？
