package example.upper
import com.mad.core.storage.MemoryStringStore
import com.mad.core.storage.StringStore
object Alpha {
    fun create(): StringStore = MemoryStringStore()
    fun type(): Class<*> = StringStore::class.java
}
