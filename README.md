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
bash tools/build_ios_xcframework.sh
./gradlew -Pmadcore.target=ohos :madcore:compileKotlinOhosArm64
```

`madcore.target` 为单选，鸿蒙使用原仓钉定的 CPF Kotlin fork，不能把它与上游 Kotlin 目标放在同一构建运行。Android 需要 SDK 36；iOS 需要 macOS/Xcode；鸿蒙需要对应 fork 工具链。

本地制品仓为 `build/staging-repository`。拟用坐标 `com.mad.core:madcore:0.1.0-SNAPSHOT`，只有本地发布成功后才能被外部工程消费；不向远端仓库发布。

## 平台状态

- 已验证代码提交：`108015e`，四项云端任务全部通过：https://github.com/changyue1053/MadCore/actions/runs/44256063080 。
- JVM：全部测试、Maven 本地发布及仓外 Kotlin/Java 制品消费者通过，包括真实回环 HTTP 行为测试。
- Android：Release AAR 构建及八模块产物存在性检查通过；未做独立 App 集成/设备测试。
- iOS：原生 NSURLSession 适配器的 arm64 真机/模拟器 XCFramework、独立 Swift 类型检查和模拟器真实 HTTP 行为测试通过；JUnit 门禁确认用例非空且未跳过，未验证真机 App。
- 鸿蒙：ohosArm64 klib、独立 `libmadcore.so` / NAPI 桥、真实字节码 HAR 构建和仓外 HAR 消费者编译通过；只依赖该 HAR 的独立示例 App 也成功生成未签名 HAP。当前 ArkTS 仅有 ABI版本、墙钟、JSON对象校验三个接口，**未验证设备运行或完整 Core 功能对等，未签名 HAP 不是可直接安装的发布包。**
- 后续多个 SDK 共用 Core 的静态链接和类型身份策略仍待设计/实测，不承诺当前 umbrella 可直接与其他独立 framework 组合。

## 下一批

1. 保留四项构建/测试门禁，扩展 Android 仓外 App 和设备验证。
2. 扩展鸿蒙 ArkTS 公共 API 和真实设备验证，补 iOS App 集成和 Swift 友好 API。
3. 扩展网络平台适配、观测和生命周期；已有基础日志/配置不等于完整观测和配置平台。
4. 可选身份/存储配额/韧性/i18n 按需分包；Compose UI、登录路由、升级业务和测试夹具不进入默认基础包。

## 验证纪律

结构检查只证明来源和依赖边界，不证明 Kotlin 编译正确。三端分别报告通过/失败/未执行，不能以 JVM 通过替代 Android/iOS/鸿蒙验证。不得提交密钥、服务凭据或私有下载地址。

## 验证基础设施（开发分支）

`core-testkit` 提供单线程测试用 `ManualClock`，支持推进时间、独立墙钟跳变及溢出保护；它不进入 `madcore` 默认依赖。

GitHub Actions 工作流会执行 JVM 测试、本地 Maven 发布，并将 `examples/jvm-consumer` 复制到仓库外，只通过 Maven 制品坐标消费。工作流定义不是通过证明，以对应提交的运行结果为准。该 JVM 验证不覆盖三端 App、Swift 导出或鸿蒙 HAR；iOS 有独立 Swift 类型检查门禁。

云端验证记录：https://github.com/changyue1053/MadCore/actions/runs/44256063080 。其中鸿蒙任务独立判定，其他任务通过不代表鸿蒙通过。

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

## 鸿蒙 C/NAPI 边界预览（开发中）

`madcore` 增加 ohosArm64 shared library 目标，C ABI v1 仅暴露版本、墙钟毫秒及有 64 KiB 上限的 JSON 对象校验。`harmony/native` 为独立 NAPI 桥源码，直接链接 `libmadcore.so`，不含产品装配、Compose、IM 或动态产品加载。此阶段不是完整 Core 的 ArkTS 映射。C 指针调用方必须提供有效、可读的长度范围；不跨 ABI 持有 Kotlin 对象。

`0249ba3` 的 shared library 链接、AArch64/C 导出符号检查及独立 NAPI 桥编译链接已通过云端验证；`9a4ce27` 进一步通过限定导出面、移除仅属于可执行程序的 Scrt1.o、禁止未解析引用及零入口/无 main 重定位检查；没有伪造 main 桩。`108015e` 已通过实际字节码 HAR 打包、仓外 ArkTS HAR 消费和独立未签名 HAP 组装。CI 核对 HAR 声明入口、非空 ABC 代码及两份 native 库，绝非仅把源码压缩。尚无真机/模拟器执行结果，不能称为可发布 SDK。工具链/SDK 仅用于构建，不随仓库分发。

官方 Linux CLI 5.1.0.840 的只读探测已校验下载包哈希并确认内置 SDK 5.1.0.125/API18、Hvigor 5.18.5。只读探测未执行 SDK/Hvigor。所有者随后明确同意使用该版本的工具/SDK/Hvigor进行云端构建；分发许可范围仍待明确。只读探测不再自动随 PR 运行，新的 HAR 构建门禁仅使用这一已批准版本。工具协议对使用/下载、再分发及 SDK 用途有约束，不把可下载等同于任意使用许可，也不把 API18 编译候选等同于已验证最低运行版本。

### 鸿蒙独立消费验证

示例位于 `examples/harmony-consumer`。云端将构建出的 HAR 复制到完全独立目录，再安装此本地制品并运行 `assembleHap`，没有依赖源仓或 MadCore Kotlin 源码。测试 App 使用已获准 SDK 的 C++ runtime，仅在临时 CI 目录组包，不发布。API18 只是本次构建配置，不能据此保证最低运行版本。

发布前仍需处理：SDK/运行库分发许可、签名与设备运行、生成声明的 ArkTS 警告、工具链 SemVer 警告，旧构建曾报告 CLI 安装 pnpm 的 high 安全告警，现已通过下述官方 npm 路线移除该安装路径。没有运行 `npm audit fix --force` 或隐藏这些警告。

## 受限本地字符串存储（开发中）

`core-storage` 提供 `StringStore`、单线程 `MemoryStringStore`、Android `SharedPreferencesStringStore` 和 iOS `UserDefaultsStringStore`。仅用于非敏感偏好：键为 1..128 字符的小写 ASCII 标识符，值限 64 KiB UTF-8；空字符串不等于缺失。无枚举/清空全部、事务、加密、多进程一致性或崩溃持久性承诺。错误不包含键值或平台诊断。宿主提供独立文件/suite，并管理备份策略与线程。

Android 使用同步 commit，失败返回 Backend，但平台内存可能已经变化，失败不等于回滚。iOS 遵循 UserDefaults 异步写盘语义，不调用 Apple 不建议使用的 synchronize；只确认内存更新，注册默认值可能在删除后重新出现。测试重新构造适配器，不冒充进程重启或掉电恢复验证。鸿蒙 Kotlin 侧有公共契约/内存实现；另有独立 ArkTS `PreferencesStringStore` 接受宿主已有 Preferences，get/put/remove 仅操作缓存，flush() 异步等待平台刷盘确认。两次默认值探测区别实际空串和错误存储类型，宿主必须串行化所有访问。该 ArkTS 类不是 Kotlin 接口的跨语言实现；当前仅有 HAR/消费者编译门禁，尚无鸿蒙存储设备执行证据。

Apple 要求 UserDefaults 的隐私清单理由声明；本 SDK 是仅由宿主调用的包装 API，对应 C56D.1 的候选用途。使用 `bash tools/build_ios_xcframework.sh` 构建的开发 XCFramework 会将 UserDefaults 包装理由 C56D.1 与应用内间隔/计时理由 35F9.1 写入每个 framework slice；仅直接运行原始 Gradle assemble 不包含这一步。CI 读取每份 plist 核验。发布前仍须审查 Kotlin/runtime 全部 required-reason API 和宿主实际用途，不能据此宣称 App Store 合规。参见 [Apple 官方理由说明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。

### Android 独立运行已验证

`3f46501` 的 [云端运行](https://github.com/changyue1053/MadCore/actions/runs/44258322761) 已通过仓外 Maven 消费、APK 编译及 API30 标准 AOSP x86_64 模拟器真实网络测试。该记录不覆盖本节新加的存储代码；存储行为以之后对应提交 CI 为准。未接受 ATD 专用协议，标准镜像使用 runner 已有 SDK 许可；没有自动同意命令。真机、API24 和真实公网 TLS 尚未验证。

### 鸿蒙构建依赖安全（已验证 npm 路线）

pnpm 8.13.1 的独立元数据审计确认多条 advisory 汇总为一个 high 受影响包，而非单一漏洞。本分支改用 [华为官方支持的 hvigor.dependency.useNpm 配置](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/ide-hvigor-set-options-V5/)，不盲升 pnpm 大版本或修改 SDK。CI 使用临时 HOME/空 npm 用户配置，避免读取用户 token 和共享执行缓存，并在构建后检查 wrapper 未安装 pnpm。`bc93473` 及 `f1ecc55` 已通过实际 HAR/仓外消费/HAP 构建和无 wrapper pnpm 门禁；没有据此宣称 Node/npm/Hvigor 整体无漏洞。

API18 的 Harmony NetworkKit 暂无已确认的禁用重定向参数；官方 maxRedirects 从 API23 才支持。因此不能把自动跟随重定向的适配器冒充现有网络安全契约实现，目前保留宿主注入边界，不以响应后的检查替代发送前拒绝。

iOS 清单只声明本 SDK 当前 API 的有限用途，不替宿主声明完整的数据收集/跟踪政策。禁止借计时 API 做指纹识别或发送设备启动时间；可发送的仅限应用内事件间隔。SDK 不自行上传存储或日志。最终应用、三方依赖和分发流程仍须隐私审查。参考 [Kotlin 官方说明](https://kotlinlang.org/docs/multiplatform/multiplatform-privacy-manifest.html)。


### 当前完整 CI 里程碑

`f1ecc55b34c17ad96d3d6a073fff93fddc9f17b5` 的 [运行 44264199192](https://github.com/changyue1053/MadCore/actions/runs/44264199192) 四项全部通过：JVM、Android独立App模拟器3用例、iOS原生HTTP/存储及两片framework隐私清单、鸿蒙字节码HAR/独立消费/未签名HAP与npm模式门禁。此后本README更新不改变该已验证代码。通过不等于真机/全部平台功能等价、SDK分发许可或可直接发布。

## 资源生命周期（开发中）

`core-lifecycle` 的 `ResourceScope` 接收显式 `CloseableResource`，关闭时先解除全部所有权再逆序清理；普通异常计数并隔离，严重 Throwable 在尝试清理整个批次后重新抛出。重复/重入关闭返回空报告，注册句柄 detach 只转移所有权而不关闭。关闭后注册失败，资源仍归调用方；同实例重复注册会分别关闭，调用方须避免误注册。

这是宿主串行调用的资源管理器，不是线程安全容器、调度器、异步取消或平台生命周期自动绑定。不得用它隐式接管宿主窗口、账号或全局资源。报告不保存资源信息和异常内容。跨语言回调还须宿主遵守相同线程及异常约定。
