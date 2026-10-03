package jp.nogut.ytdlp_flutter

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadForegroundPolicyTest {
    @Test fun includesMediaProcessingOnAndroid15AndLater() {
        for (sdk in listOf(35, 36)) {
            assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING, DownloadForegroundPolicy.types(sdk))
        }
    }

    @Test fun usesDataSyncBeforeAndroid15() {
        for (sdk in listOf(29, 30, 33, 34)) {
            assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC, DownloadForegroundPolicy.types(sdk))
        }
    }
}
