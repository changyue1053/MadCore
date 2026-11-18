package example.upper
import com.mad.core.storage.StringStore
object Beta {
    fun consume(store: StringStore): StringStore {
        store.put("shared", "beta")
        return store
    }
    fun type(): Class<*> = StringStore::class.java
}
