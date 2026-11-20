package probe.alpha

import com.mad.core.storage.MemoryStringStore
import com.mad.core.storage.StringStore

/** A separate published upper KLIB, not another copy of Core source. */
class AlphaSdk {
    fun createStore(): StringStore = MemoryStringStore()
}
