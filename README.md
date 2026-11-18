# MadCore

独立 Core 基础 SDK 的初始源码提取稿。目标为 Android、iOS、鸿蒙，供后续业务 SDK 共用。

**当前不是可发布的三端 SDK。平台运行验证尚未完成。**

## 本批内容

| 模块 | 功能 | 生产依赖 |
|---|---|---|
| core-extension | 服务注册、扩展注册和注解 | Kotlin 标准库 |
| core-time | 系统/注入时钟、时钟偏差校正 | core-extension |
| core-json | MiniJson 解析 | Kotlin 标准库 |
| core-logging | 结构化日志、级别过滤、敏感记录默认丢弃 | core-time |
| core-config | 不可变配置、分层覆盖、严格类型读取 | Kotlin 标准库 |
| core-net | HTTP 契约、限额、JVM/Android URLConnection、iOS NSURLSession 适配 | Kotlin 标准库 / 平台网络库 |
| madcore | 统一消费入口、iOS umbrella 配置 | 上述六个模块 |

原 Kotlin 源码及测试保持不变，包名保留 `com.mad.core.*`。来源固定在 `SOURCE-PROVENANCE.json`，没有修改源仓库。新构建不依赖原仓库的 build-logic、产品装配或本地绝对路径。

没有将原仓库的 AGENTS/工作卡机制复制到新仓库。所有者已确认将本批提取代码公开到本仓库。尚未选择项目开源许可证；公开可见不等于授予任意再分发许可。Gradle wrapper 保留其原许可声明。

## 构建入口

需要 JDK 21 和 Gradle wrapper 所列分发包及插件可访问。本地工作区首次下载因网络不可达失败，编译验证改由 GitHub Actions 执行。

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

- JVM：`6394541` 云端全部测试、Maven 本地发布及仓外 Kotlin/Java 制品消费者通过，包括真实回环 HTTP 行为测试。
- Android：`6394541` 云端 Release AAR 构建及八模块产物存在性检查通过；未做独立 App 集成/设备测试。
- iOS：`cc69dec` 包含原生 NSURLSession 适配器的 arm64 真机/模拟器 XCFramework、产物检查及独立 Swift 类型检查通过；模拟器 HTTP 行为测试任务通过，未验证真机 App。
- 鸿蒙：`6394541` 云端 fork 工具链及 ohosArm64 klib 编译通过。**尚无 NAPI/ArkTS 入口、独立 HAR 和 App，不能称为鸿蒙可接入。**
- 后续多个 SDK 共用 Core 的静态链接和类型身份策略仍待设计/实测，不承诺当前 umbrella 可直接与其他独立 framework 组合。

## 下一批

1. 强化 iOS 原生网络运行结果门禁，保留各平台独立构建门禁。
2. 加三端仓外消费者；完成鸿蒙 HAR/ArkTS 及 Swift 友好 API。
3. 扩展网络平台适配、观测和生命周期；已有基础日志/配置不等于完整观测和配置平台。
4. 可选身份/存储配额/韧性/i18n 按需分包；Compose UI、登录路由、升级业务和测试夹具不进入默认基础包。

## 验证纪律

结构检查只证明来源和依赖边界，不证明 Kotlin 编译正确。三端分别报告通过/失败/未执行，不能以 JVM 通过替代 Android/iOS/鸿蒙验证。不得提交密钥、服务凭据或私有下载地址。

## 验证基础设施（开发分支）

`core-testkit` 提供单线程测试用 `ManualClock`，支持推进时间、独立墙钟跳变及溢出保护；它不进入 `madcore` 默认依赖。

GitHub Actions 工作流会执行 JVM 测试、本地 Maven 发布，并将 `examples/jvm-consumer` 复制到仓库外，只通过 Maven 制品坐标消费。工作流定义不是通过证明，以对应提交的运行结果为准。该 JVM 验证不覆盖三端 App、Swift 导出或鸿蒙 HAR；iOS 有独立 Swift 类型检查门禁。

云端验证记录：https://github.com/changyue1053/MadCore/actions/runs/44245263396 。其中鸿蒙任务独立判定，其他任务通过不代表鸿蒙通过。

## 结构化日志（开发分支）

`StructuredLogger` 通过宿主注入 `LogSink`，默认无操作接收器，不落盘、不上传、不依赖 shellhost 或 UI。所有构建形态默认丢弃敏感记录；只有显式 `FieldPrivacy.Public` 的记录能进入 sink。域/码仅接受短 ASCII 标识符。字段仍由调用方审查，不承诺自动识别个人数据，禁止将凭据或用户内容标记为 Public。不使用弱哈希假装匿名化。普通 sink/clock 异常被隔离，严重 Error 不吞；调用在当前线程进行，宿主负责线程安全及非阻塞。

本模块是独立实现，不是原仓 `core-obs` 的完整复制；暂不包含指标、事件分析、平台日志适配或诊断包。

## 本地配置模型（开发分支）

`ConfigSnapshot` 防御性复制输入，叠加产生新快照，可供多个读者共享。缺失值返回 null，存在但不合法的类型值抛 `ConfigValueException`，不将错误配置静默当成缺失。异常与 `toString` 不输出配置值。快照只存字符串，不是安全凭据容器；不包含账号、产品/BOM、签名协议、远程拉取或持久化。此模块独立实现，不复制原仓带业务协议的完整 `core-config`。

## 网络基础（开发分支）

`HttpClient` + `HttpTransport` 为阻塞接口，宿主必须放到非 UI 线程。`UrlConnectionTransport` 仅在 JVM/Android 提供，支持 GET/POST，默认只允许 HTTPS、不自动跟随重定向、不加应用层重试。请求/响应体限额在 JVM/Android 适配器中执行；连接和读取超时是 socket 超时，不是包含 DNS/写入的全程 deadline，不提供取消。平台代理、CookieHandler、Authenticator 等全局网络钩子仍可能生效；不是 SSRF 防火墙。Android App 须自行声明 INTERNET 权限。

响应非 2xx 仍返回状态/响应体；网络异常仅返回枚举错误，不附带 URL、头或正文。请求禁止 URL 内凭据、片段、换行头及传输层所有的头。TLS 校验采用平台默认，不关闭证书或主机名校验。测试仅显式给本机回环 HTTP 开绿灯。鸿蒙目前只有公共网络契约，须注入宿主适配器，不宣称已有原生 HTTP 实现。

### iOS 原生网络

`IosUrlSessionTransport` 使用每次调用独立的 ephemeral NSURLSession；拒绝主线程调用，关闭 cookie/凭据存储/缓存，保留平台 TLS 校验。流式检查响应限额、不跟随重定向，超时会取消底层请求。Foundation 只有单个空闲超时，取连接/读取限额中的较小值，另有 `callTimeoutMillis` 总等待上限。公开接口仍是阻塞式，不提供调用方主动取消。系统代理、ATS 及其他宿主网络策略仍适用。

CI 的 iOS 模拟器测试使用本机 Python HTTP 服务，覆盖 GET/POST、错误响应、重定向拒绝、固定/分块响应限额、超时及之后的新请求。测试配置存在不等于测试通过；`cc69dec` 的模拟器测试任务已通过（运行 https://github.com/changyue1053/MadCore/actions/runs/44246999178）；后续还增加 JUnit 用例非空/未跳过检查。以上平台状态为已确认结果。没有真机、真实公网 TLS 或宿主 App 集成结果。
