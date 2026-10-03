package jp.nogut.ytdlp_flutter

import android.content.pm.ServiceInfo

object DownloadForegroundPolicy {
    fun types(sdk: Int): Int = if (sdk >= 35) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
    } else {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    }
}
