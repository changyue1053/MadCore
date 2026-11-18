package probe.beta

import com.mad.core.storage.StringStore
import com.mad.core.storage.StorageException

class BetaSdk {
    @Throws(StorageException::class)
    fun mutateAndReturn(store: StringStore): StringStore {
        store.put("upper.beta", "shared")
        return store
    }
}
