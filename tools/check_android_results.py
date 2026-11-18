"""Require independent emulator execution, not just assembly."""
import sys
from test_result_gate import require_cases
required = {
    ("com.mad.consumer.SharedCoreIntegrationTest", "twoIndependentAarsShareCore"),
    ("com.mad.consumer.StorageIntegrationTest", "independentNamespaces"),
    ("com.mad.consumer.CoreIntegrationTest", "untrustedTlsIsRejected"),
    ("com.mad.consumer.LifecycleIntegrationTest", "publishedLifecycleOwnership"),
    ("com.mad.consumer.CoreIntegrationTest", "publishedCoreAndRealHttp"),
    ("com.mad.consumer.StorageIntegrationTest", "publishedStorageAndPlatformPersistence"),
    ("com.mad.consumer.StorageIntegrationTest", "failedCommitsAndPlatformErrorsAreRedacted"),
}
require_cases(sys.argv[1], required, "Independent Android emulator behavior")
