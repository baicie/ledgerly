# ADR-001：客户端统一使用 Flutter

* 状态：Accepted
* 日期：2026-08-03

## 决策

所有应用端统一使用 Flutter：Android、iOS、Web、Windows、macOS、Linux。

共享：页面/组件、设计系统、领域模型、本地 Schema、同步引擎、校验、路由、状态、报表、错误处理。

平台差异仅允许存在于 PlatformCapability、LocalDatabaseExecutor、BackgroundScheduler、SecureStorage、FilePicker、NotificationService、BiometricService、WindowService。

## 后果

- 优点：一套客户端覆盖全平台；同步逻辑只实现一次。
- 代价：进入 Dart/Flutter 生态；Web 非标准 DOM；包体通常更高。

## 补充

官网/帮助中心/隐私政策不使用 Flutter（Astro/Next.js）。Flutter Web 仅承担登录后的应用型界面。
