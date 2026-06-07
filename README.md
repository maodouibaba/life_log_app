# 生活记录 App

纯本地的个人日记/记录 App，支持多平台（iOS / Windows / Web）。

## 功能

- 📝 时间线首页（按天分组、展开/折叠）
- 🏷️ 树状标签 + 属性标签双分类
- 📁 项目分组管理
- 📋 列表视图（多重筛选、批量操作）
- 🔍 全文搜索（内容/标签/属性标签）
- 🤖 AI 助写（支持 DeepSeek / 通义千问 / Claude / OpenAI）
- ☁️ 坚果云 WebDAV 多端同步
- ↩️ 常驻撤销按钮
- 📊 Excel 导出
- 🔄 JSON 备份与恢复
- 🌓 主题切换（系统/日间/夜间）
- 🔒 隐私锁（密码 + 面容/指纹）

## 技术栈

- **框架**：Flutter (Dart)
- **数据库**：sqflite（本地 SQLite）+ WebDatabase（Web 内存版）
- **同步**：坚果云 WebDAV（`http` + `xml` 包）
- **导出**：excel 包
- **平台**：iOS / Windows / Web

## 开发

```bash
# 获取依赖
flutter pub get

# Web 预览
flutter run -d web-server --web-port 8100

# Windows 桌面
flutter build windows --debug

# iOS 编译（需 macOS + Xcode）
flutter build ios --debug --no-codesign
```
