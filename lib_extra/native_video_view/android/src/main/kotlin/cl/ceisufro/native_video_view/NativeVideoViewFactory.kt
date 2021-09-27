package cl.ceisufro.native_video_view

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory


class NativeVideoViewFactory(private val messenger: BinaryMessenger)
    : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val params = args as Map<String, Any>
        val map = mapOf(
                "videoUrl" to "https://storage.googleapis.com/wvmedia/cenc/h264/tears/tears_sd.mpd",
                "drmLicenseUrl" to "https://proxy.uat.widevine.com/proxy?provider=widevine_test")
        return DrmVideoPlayer(context, messenger, id, params)
    }
}