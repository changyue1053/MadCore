# MadCore

独立 Core 基础 SDK 的初始源码提取稿。目标为 Android、iOS、鸿蒙，供后续业务 SDK 共用。

**当前不是可发布的三端 SDK。平台运行验证尚未完成。**

## 本批内容

| 模块 | 功能 | 生产依赖 |
|---|---|---|
| core-extension | 服务注册、扩展注册和注解 | Kotlin 标准库 |
| core-time | 系统/注入时钟、时钟偏差校正 | core-extension |
| core-json | MiniJson 解析 | Kotlin 标准库 |
| madcore | 统一消费入口、iOS umbrella 配置 | 上述三个模块 |

原 Kotlin 源码及测试保持不变，包名保留 `com.mad.core.*`。来源固定在 `SOURCE-PROVENANCE.json`，没有修改源仓库。新构建不依赖原仓库的 build-logic、产品装配或本地绝对路径。

没有将原仓库的 AGENTS/工作卡机制复制到新仓库。所有者已确认将本批提取代码公开到本仓库。尚未选择项目开源许可证；公开可见不等于授予任意再分发许可。Gradle wrapper 保留其原许可声明。

## 构建入口（配置尚未经过编译验证）

需要 JDK 21 和 Gradle wrapper 所列分发包及插件可访问。此工作区无已缓存 Gradle，首次下载因网络不可达失败。

```sh
python3 tools/check_source_boundary.py
./gradlew -Pmadcore.target=jvm jvmTest
./gradlew -Pmadcore.target=jvm publishAllPublicationsToStagingRepository
./gradlew -Pmadcore.target=android :madcore:bundleReleaseAar
./gradlew -Pmadcore.target=ios :madcore:assembleMadCoreReleaseXCFramework
./gradlew -Pmadcore.target=ohos :madcore:compileKotlinOhosArm64
```

`madcore.target` 为单选，鸿蒙使用原仓钉定的 CPF Kotlin fork，不能把它与上游 Kotlin 目标放在同一构建运行。Android 需要 SDK 36；iOS 需要 macOS/Xcode；鸿蒙需要对应 fork 工具链。

本地制品仓为 `build/staging-repository`。拟用坐标 `com.mad.core:madcore:0.1.0-SNAPSHOT`，只有本地发布成功后才能被外部工程消费；不向远端仓库发布。

## 平台状态

- JVM：提交 `869bf64` 的云端编译、测试、Maven 本地发布及仓外制品消费者运行均已通过。
- Android：提交 `869bf64` 的云端 Release AAR 构建及五模块产物存在性检查通过；未做独立 App 集成/设备测试。
- iOS：提交 `869bf64` 的云端 arm64 真机/模拟器 XCFramework 构建、产物检查及独立 Swift 版本入口 typecheck 通过；未运行 App，未完整验证泛型 API 消费。
- 鸿蒙：只配置 ohosArm64 编译目标。**尚无 NAPI/ArkTS 入口、独立 HAR 和 App，不能称为鸿蒙可接入。**
- 后续多个 SDK 共用 Core 的静态链接和类型身份策略仍待设计/实测，不承诺当前 umbrella 可直接与其他独立 framework 组合。

## 下一批

1. 完成鸿蒙 fork 工具链编译验证，保留各平台独立构建门禁。
2. 加三端仓外消费者；完成鸿蒙 HAR/ArkTS 及 Swift 友好 API。
3. 按公共边界提取网络、观测、配置、平台适配和生命周期；这些本批未实现。
4. 可选身份/存储配额/韧性/i18n 按需分包；Compose UI、登录路由、升级业务和测试夹具不进入默认基础包。

## 验证纪律

结构检查只证明来源和依赖边界，不证明 Kotlin 编译正确。三端分别报告通过/失败/未执行，不能以 JVM 通过替代 Android/iOS/鸿蒙验证。不得提交密钥、服务凭据或私有下载地址。

## 验证基础设施（开发分支）

`core-testkit` 提供单线程测试用 `ManualClock`，支持推进时间、独立墙钟跳变及溢出保护；它不进入 `madcore` 默认依赖。

GitHub Actions 工作流会执行 JVM 测试、本地 Maven 发布，并将 `examples/jvm-consumer` 复制到仓库外，只通过 Maven 制品坐标消费。工作流定义不是通过证明，以对应提交的运行结果为准。该验证不覆盖三端 App、Swift 导出或鸿蒙 HAR。

云端验证记录：https://github.com/changyue1053/MadCore/actions/runs/44239436313 。其中鸿蒙任务独立判定，其他任务通过不代表鸿蒙通过。
