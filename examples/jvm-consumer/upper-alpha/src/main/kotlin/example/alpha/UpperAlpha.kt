package example.alpha

import com.mad.core.storage.MemoryStringStore
import com.mad.core.storage.StringStore

/** Simulated upper SDK A. Public API exposes Core, but its JAR does not embed Core. */
object UpperAlpha {
    fun createStore(): StringStore = MemoryStringStore()
    fun coreType(): Class<*> = StringStore::class.java
}
