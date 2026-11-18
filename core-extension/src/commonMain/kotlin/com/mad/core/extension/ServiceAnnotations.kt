// core-extension · 服务图注解（RFC-2026-003 §2 签名原文）：provides / requires 的输入面，供 KSP 导出 services.json。
// 现阶段与 capability.toml、feature.toml 的 [services] 并存，读者仍读 toml；注解只写键类引用，不写 id 字面量。
package com.mad.core.extension

import kotlin.reflect.KClass

/** 能力域节点：标在 capability-*-ffi 的 CapabilityEntry 生产实现（object）上，每模块恰一处；KSP 以它为导出根。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class CapabilityNode(
    val id: String,                        // 等于模块目录中段与入口 val id（capability-im-ffi → "im"）
    val capabilities: Array<String> = [],  // 能力闭包（原顶层 requires），等于入口 val requires
    val twoPhase: Boolean = false,         // 原 [services].two_phase
)

/** 特性节点：标在 feature-*-impl 的 FeatureEntry 生产实现（object）上，每模块恰一处。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class FeatureNode(
    val id: String,                        // 等于模块目录中段与入口 val id（feature-consent-impl → "consent"）
    val capabilities: Array<String> = [],  // 原顶层 requires，等于入口 val requires；产品清单 capabilities 须覆盖
    val twoPhase: Boolean = false,
)

/** 本节点自己登记的全部键，两个作用域合计（原 [services].provides）；值序即导出序。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class Provides(vararg val keys: KClass<out ServiceKey<*>>)

/** 其中应用期登记进 AppScope 表的子集（原 [services].provides_app）；须 ⊆ Provides（N7）。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class ProvidesApp(vararg val keys: KClass<out ServiceKey<*>>)

/** 硬依赖：消费方 require，缺 provider 生成期判红（原 [services].requires）。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class Requires(vararg val keys: KClass<out ServiceKey<*>>)

/** 软依赖：消费方 get + 回退，缺 provider 只 warn（原 [services].requires_soft）。 */
@Retention(AnnotationRetention.SOURCE)
@Target(AnnotationTarget.CLASS)
annotation class RequiresSoft(vararg val keys: KClass<out ServiceKey<*>>)
