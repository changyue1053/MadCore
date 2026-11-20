import com.mad.core.net.HttpLimits;
import com.mad.core.net.HttpRequest;
import com.mad.core.net.HttpTransportException;
import com.mad.core.net.UrlConnectionTransport;

/** Compile-only contract check: not invoked, so no external requests occur in the smoke consumer. */
public final class JavaConsumer {
    public static boolean checkedFailureIsCatchable(HttpRequest request, HttpLimits limits) {
        try {
            new UrlConnectionTransport().execute(request, limits);
            return true;
        } catch (HttpTransportException expected) {
            return false;
        }
    }
}
