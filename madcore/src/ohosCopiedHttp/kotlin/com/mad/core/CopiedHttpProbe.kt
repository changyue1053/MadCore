@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
package com.mad.core

/** Opt-in component probe. No network is performed and no bridge support is asserted. */
@CName("madcore_copied_http_link_probe")
fun copiedHttpLinkProbe(): Int = try { com.mad.core.net.copiedHttpLinkProbe() } catch (_: Exception) { -1 }
