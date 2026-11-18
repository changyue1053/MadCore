package example.beta

import com.mad.core.storage.StringStore

/** Independently compiled simulated upper SDK B accepts A's shared Core value. */
object UpperBeta {
    fun useStore(store: StringStore): StringStore {
        store.put("upper.beta", "shared")
        return store
    }
    fun coreType(): Class<*> = StringStore::class.java
}
