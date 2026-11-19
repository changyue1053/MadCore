# MadCore

面向多个全新 App 和上层 SDK 的独立通用基础库，目标 Android、iOS、HarmonyOS。不是旧工程的等价迁移，不依赖其产品装配、UI 或构建工程。

**已有三端构建与范围明确的模拟器实测，仍是开发评估版本，不是已批准发布的三端 SDK。** 当前验证范围与剩余发布门槛统一维护在 [交付状态](docs/DELIVERY_GATES.md)，不要把历史提交或编译通过当作当前设备兼容承诺。

## 模块

| 模块 | 能力 |
|---|---|
| core-extension | 服务/扩展注册与注解 |
| core-time | 系统与注入时钟、偏差校正 |
| core-json | 有界 JSON 解析 |
| core-logging | 结构化日志、级别过滤、默认丢弃敏感记录 |
| core-config | 不可变配置、分层覆盖、严格类型读取 |
| core-net | 有界 HTTP 契约、Android/JVM 与 iOS 适配；独立异步契约 |
| core-storage | 非敏感字符串存储、命名空间、Android/iOS 持久化适配 |
| core-lifecycle | 显式资源所有权、逆序清理与 detach |
| madcore | 生产模块统一入口与 iOS umbrella |
| core-testkit | 可选测试时钟/脚本传输，不进入默认生产依赖 |

## 接入与当前平台边界

- [新 App 接入](docs/NEW_APP_INTEGRATION.md)、[多个上层 SDK 共用 Core](docs/SHARED_CORE_INTEGRATION.md)。Android 双 AAR、iOS 两个 Kotlin 上层库加单 umbrella、Harmony 双 HAR 均有独立宿主验证；这不是任意独立 iOS framework 重复打包 Kotlin 的兼容保证。
- Harmony 有独立 ArkTS RCP、Preferences 和生命周期封装；[API23 模拟器证据](docs/HARMONY_RUNTIME_EVIDENCE.md)包括原生调用、存储重启、网络与双 HAR。API18 编译不等于 API18 运行验证。
- [实验 Kotlin↔RCP 异步桥](docs/HARMONY_ASYNC_HTTP_EXPERIMENT.md)已实际传递请求/结果，并验证关闭、迟到结果、配额恢复。默认构建不包含它；`isDrained` 不因取消或超时变成 true。
- Harmony ArkTS Preferences **不是** Kotlin `StringStore` 的跨语言持久化实现，不能宣称三端 Kotlin 存储完全对等。

## 构建入口

需要 JDK 21、对应平台工具链及固定依赖可访问。Android 使用 SDK36；iOS 需要 macOS/Xcode；Harmony 使用单独固定的 CPF Kotlin fork，不能与上游 Kotlin 目标混在同一次构建。

```sh
python3 tools/check_source_boundary.py
./gradlew -Pmadcore.target=jvm jvmTest
./gradlew -Pmadcore.target=jvm publishAllPublicationsToStagingRepository
./gradlew -Pmadcore.target=android assembleRelease publishAllPublicationsToStagingRepository
bash tools/build_ios_xcframework.sh
# Harmony 构建暂停，许可审查前不要运行 ohos 入口。
```

开发坐标为 `com.mad.core:madcore:0.1.0-SNAPSHOT`，staging 仓按目标隔离为 `build/staging-repository/<madcore.target>`，例如 `jvm`、`android`、`ios`。这里的 publish 任务只写本地开发仓，不向远端发布。Harmony 工具执行目前暂停，等待独立 SDK 用途的许可适用审查；工具/SDK不随本仓库分发。

Android 的 `assembleRelease` / `:madcore:bundleReleaseAar` 只构建 AAR，不会准备独立消费者所需的 Maven 依赖仓；使用上面的 publish 任务生成 `build/staging-repository/android`。`madcore` AAR 不是包含全部模块的 fat AAR。包含两个独立上层 AAR 和 HTTP/TLS fixture 的完整验收步骤见 [Android 独立消费者](examples/android-consumer/README.md)。

同一 SNAPSHOT 坐标的 KMP 根元数据只描述该次构建配置的目标，不能把不同目标的暂存目录合并。按目标把 `-PmadcoreRepository` 指向对应子目录；旧版无目标后缀的暂存根目录不再使用，不要将它作为后备仓库。CI 各目标消费者也使用对应子目录。这是预览产物隔离，不是一个聚合三端的正式 Maven 发布仓。

固定工具版本是本项目实际测试组合，不等于 JetBrains 官方支持组合；Kotlin2.2.21 配合 Gradle9.4.1 / AGP8.13.2 超出其表列支持范围，见 [工具链证据边界](docs/DELIVERY_GATES.md#tested-toolchain-versus-upstream-compatibility)。

## 必须保留的使用限制

- 日志不自动落盘或上传，敏感记录默认丢弃。调用者不能把凭据、用户内容误标为 Public；sink/clock 必须满足宿主线程与非阻塞要求。
- 配置不是凭据容器，不自动远程拉取或持久化。默认 Core 没有产品登录、升级、隐式授权、重试或遥测。
- 稳定 Kotlin HTTP API 是阻塞接口，不能在 UI 线程等待。使用平台 TLS，不自动跟随重定向；请求/响应有界，非2xx保留状态。平台代理/ATS等策略仍适用，不是 SSRF 防火墙。超时不证明服务端未执行。
- 存储仅限非敏感偏好，值上限64 KiB UTF-8。无加密、全量清空、事务、多进程一致性或掉电持久保证。命名空间只是键分区，不是权限沙箱。宿主负责独立文件/suite、备份、同步与平台flush语义。
- iOS 构建脚本附带有限用途的 privacy manifest；不等于最终 App Store 合规或完整第三方 API 审查。
- 每平台的编译、链接、模拟器与真机证据分开报告。精确 CI 提交、设备矩阵、实验桥限制和发布决策见 [交付状态](docs/DELIVERY_GATES.md)。

## 来源与许可

初始提取文件及固定来源记录在 `SOURCE-PROVENANCE.json`；来源仓未修改。后续独立实现和验证以本仓提交记录为准，不能把初始提取时的说明当作全部当前代码的来源声明。

所有者已授权公开本仓源码，但**项目 LICENSE 尚未选定，公开可见不等于任意再分发授权**。Gradle wrapper 保留原许可声明。第三方工具链/runtime的精确组件、NOTICE及二进制分发权限仍须按 [分发审查清单](docs/DISTRIBUTION_REVIEW.md)处理；构建授权不是二进制发布授权。当前 Draft PR 不授权 merge 或 release。
