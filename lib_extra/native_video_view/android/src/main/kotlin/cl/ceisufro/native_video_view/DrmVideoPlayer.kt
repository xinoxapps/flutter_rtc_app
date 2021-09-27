package cl.ceisufro.native_video_view
import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.Player.REPEAT_MODE_ALL
import com.google.android.exoplayer2.Player.REPEAT_MODE_OFF

import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.ExoPlaybackException;
import com.google.android.exoplayer2.Format;
import com.google.android.exoplayer2.MediaItem;
import com.google.android.exoplayer2.PlaybackParameters;
import com.google.android.exoplayer2.Player;
import com.google.android.exoplayer2.Player.EventListener;
import com.google.android.exoplayer2.SimpleExoPlayer;
import com.google.android.exoplayer2.audio.AudioAttributes;
import com.google.android.exoplayer2.source.ProgressiveMediaSource;
import com.google.android.exoplayer2.source.hls.HlsMediaSource;
import com.google.android.exoplayer2.source.smoothstreaming.DefaultSsChunkSource;
import com.google.android.exoplayer2.source.smoothstreaming.SsMediaSource;
import com.google.android.exoplayer2.drm.DefaultDrmSessionManager
import com.google.android.exoplayer2.drm.DrmSessionManager
import com.google.android.exoplayer2.drm.HttpMediaDrmCallback
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.dash.DashMediaSource
import com.google.android.exoplayer2.source.dash.DefaultDashChunkSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.ui.StyledPlayerView
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory
import com.google.android.exoplayer2.util.Util
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.*
import kotlin.collections.HashMap

internal class DrmVideoPlayer(
        private val context: Context,
        private val messenger: BinaryMessenger,
        private val id: Int,
        private val params: Map<String, Any>) : PlatformView, MethodChannel.MethodCallHandler {

    private val TAG = "DVP"
    private val FORMAT_SS = "ss"
    private val FORMAT_DASH = "dash"
    private val FORMAT_HLS = "hls"
    private val FORMAT_OTHER = "other"

    private var view: View? = null

    private var methodChannel: MethodChannel?

    private var isInitialized = false

    private var player: SimpleExoPlayer? = null
    private var playerView: StyledPlayerView?

    private var eventChannel: EventChannel?

    private val eventSink: QueuingEventSink = QueuingEventSink()

    override fun getView(): View {
        return view!!
    }

    init {
        if (view == null) {
            view = LayoutInflater.from(context).inflate(R.layout.exoplayer_layout, null)
        }
        playerView = view!!.findViewById(R.id.video_view)

        eventChannel = EventChannel(messenger, "native_video_view_events_$id")
        methodChannel = MethodChannel(messenger, "native_video_view_$id")
        methodChannel?.setMethodCallHandler(this)

        initializePlayer();
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "player#seekTo" -> {
                seekTo(call, result)
            }
            "player#start" -> {
                play(result);
            }
            "player#stop" -> {
                stop(result);
            }
            "player#pause" -> {
                pause(result);
            }
            "player#setVolume" -> {
                setVolume(call);
            }
            "player#setLooping" -> {
                setLooping(call);
            }
            "player#setPlaybackSpeed" -> {
                setPlaybackSpeed(call);
            }
            "player#currentPosition" -> {
                getPosition(result)
            }
            "player#isPlaying" -> {
                isPlaying(result)
            }
            "player#dispose" -> {
                dispose()
            }
            "player#setVideoSource" -> {
                setVideoSource(call, result)
            }
        }
    }

    private fun setVideoSource(call: MethodCall, result: MethodChannel.Result) {
        val videoUrl: String? = call.argument("videoUrl")
        val drmLicenseUrl: String? = call.argument("drmLicenseUrl")
        var formatHint: String? = null

        var drmSessionManager: DrmSessionManager? = null;

        if (drmLicenseUrl != null && drmLicenseUrl.isNotEmpty()) {
            val drmCallback = HttpMediaDrmCallback(drmLicenseUrl, DefaultHttpDataSourceFactory())
            drmSessionManager = DefaultDrmSessionManager.Builder().build(drmCallback)
        }
        val dataSourceFactory: DataSource.Factory
        dataSourceFactory = if (drmLicenseUrl != null && isHTTP(Uri.parse(drmLicenseUrl))) {
            DefaultHttpDataSourceFactory(
                    "ExoPlayer",
                    null,
                    DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS,
                    DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS,
                    true
            )
        } else {
            DefaultDataSourceFactory(context, "ExoPlayer")
        }


        val mediaSource: MediaSource = buildMediaSource(Uri.parse(videoUrl), dataSourceFactory, formatHint, context, drmSessionManager)!!

        if (isInitialized) {
            player?.stop()
            isInitialized = false
        }

        player?.playWhenReady = false
        player?.setMediaSource(mediaSource)
        player?.prepare()
        result.success(null)
    }

    private fun isPlaying(result: MethodChannel.Result) {
        val arguments = HashMap<String, Any>()
        arguments["isPlaying"] = player?.isPlaying ?: false
        result.success(arguments)
    }

    private fun getPosition(result: MethodChannel.Result) {
        val arguments = HashMap<String, Any>()
        arguments["currentPosition"] = player?.currentPosition ?: 0
        result.success(arguments)
    }

    private fun setPlaybackSpeed(call: MethodCall) {
        val mapped = call.arguments as Map<String, Any>
        var value = mapped["position"] as Double;

        // We do not need to consider pitch and skipSilence for now as we do not handle them and
        // therefore never diverge from the default values.
        val playbackParameters = PlaybackParameters(value.toFloat())
        player?.setPlaybackParameters(playbackParameters)
    }

    private fun setLooping(call: MethodCall) {
        val mapped = call.arguments as Map<String, Any>
        var value = mapped["looping"] as Boolean;
        player?.repeatMode = if (value) REPEAT_MODE_ALL else REPEAT_MODE_OFF
    }

    private fun seekTo(call: MethodCall, result: MethodChannel.Result) {
        val mapped = call.arguments as Map<String, Any>
        var position = mapped["position"] as Int;
        player?.seekTo(position.toLong())
        result.success(null);
    }

    private fun play(result: MethodChannel.Result) {
        player?.playWhenReady = true
        player?.play()
        result.success(null);
    }

    private fun stop(result: MethodChannel.Result) {
        player?.playWhenReady = false
        if (isInitialized) {
            isInitialized = false
            player?.stop()
        }
        result.success(null);
    }

    private fun pause(result: MethodChannel.Result) {
        player?.playWhenReady = false
        player?.pause()
        result.success(null);
    }

    private fun setVolume(call: MethodCall) {
        val mapped = call.arguments as Map<String, Any>
        var volume = mapped["position"] as Double;

        val bracketedValue = Math.max(0.0, Math.min(1.0, volume)).toFloat()
        player?.volume = bracketedValue
    }

    private fun initializePlayer() {
        Log.v(TAG, "initializePlayer");
        val trackSelector = DefaultTrackSelector(context)
        trackSelector.setParameters(
                trackSelector.buildUponParameters().setMaxVideoSizeSd()
        )

        player = SimpleExoPlayer.Builder(context)
                .setTrackSelector(trackSelector)
                .build()

        player?.setAudioAttributes(getAudioAttributes(), true)

        playerView?.player = player
        player?.playWhenReady = false
        Log.v(TAG, "initializePlayer Channel");
        eventChannel?.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, events: EventSink?) {
                        Log.v(TAG, "Channel eventSink")
                        eventSink.setDelegate(events)
                    }

                    override fun onCancel(args: Any?) {
                        eventSink.setDelegate(null)
                    }
                })

        Log.v(TAG, "initializePlayer listener");
        player?.addListener(
                object : Player.EventListener {
                    override fun onPlaybackStateChanged(playbackState: Int) {
                        Log.v(TAG, "onPlaybackStateChanged $playbackState");
                        if (playbackState == Player.STATE_BUFFERING) {
                            sendBufferingUpdate()
                        } else if (playbackState == Player.STATE_READY) {
                            if (!isInitialized) {
                                isInitialized = true
                                sendInitialized()
                            }
                        } else if (playbackState == Player.STATE_ENDED) {
                            val event: HashMap<String, Any> = HashMap()
                            event["event"] = "completed"
                            methodChannel?.invokeMethod("player#onCompletion", event)
                            eventSink.success(event)
                        }
                    }

                    override fun onPlayerError(error: ExoPlaybackException) {
                        Log.w(TAG, "onPlayerError " + (error.message ?: ""));
                        val arguments = HashMap<String, Any>()
                        arguments["what"] = error.type
                        arguments["extra"] = error.message ?: ""
                        methodChannel?.invokeMethod("player#onError", arguments)

                        eventSink.error("VideoError", "Video player had error $error", null)

                    }
                })
        Log.v(TAG, "initializePlayer done");
    }

    private fun getAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.CONTENT_TYPE_MOVIE)
                .build()
    }

    private fun buildMediaSource(
            uri: Uri, mediaDataSourceFactory: DataSource.Factory, formatHint: String?, context: Context, drmSessionManager: DrmSessionManager?): MediaSource? {
        val type: Int = if (formatHint == null || formatHint.isEmpty()) {
            Util.inferContentType(uri.lastPathSegment!!)
        } else {
            when (formatHint) {
                FORMAT_SS -> C.TYPE_SS
                FORMAT_DASH -> C.TYPE_DASH
                FORMAT_HLS -> C.TYPE_HLS
                FORMAT_OTHER -> C.TYPE_OTHER
                else -> -1
            }
        }
        return when (type) {
            C.TYPE_SS -> SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSourceFactory(context, null, mediaDataSourceFactory))
                    .setDrmSessionManager(drmSessionManager)
                    .createMediaSource(MediaItem.fromUri(uri))
            C.TYPE_DASH -> DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSourceFactory(context, null, mediaDataSourceFactory))
                    .setDrmSessionManager(drmSessionManager)
                    .createMediaSource(MediaItem.fromUri(uri))
            C.TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                    .setDrmSessionManager(drmSessionManager)
                    .createMediaSource(MediaItem.fromUri(uri))
            C.TYPE_OTHER -> ProgressiveMediaSource.Factory(mediaDataSourceFactory)
                    .setDrmSessionManager(drmSessionManager)
                    .createMediaSource(MediaItem.fromUri(uri))
            else -> {
                throw IllegalStateException("Unsupported type: $type")
            }
        }
    }


    private fun isHTTP(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        val scheme = uri.scheme
        return scheme == "http" || scheme == "https"
    }


    private fun sendBufferingUpdate() {
        val event: HashMap<String, Any> = HashMap()
        event["event"] = "bufferingUpdate"
        val range: List<Number?> = listOf(0, player?.bufferedPosition)
        // iOS supports a list of buffered ranges, so here is a list with a single range.
        event["values"] = Collections.singletonList(range)
        eventSink.success(event)
    }

    override fun dispose() {
        if (isInitialized) {
            player?.stop()
        }
        eventChannel?.setStreamHandler(null)

        player?.release()
    }

    private fun sendInitialized() {
        if (isInitialized) {
            val event: HashMap<String, Any> = HashMap()
            event.put("event", "initialized")
            event.put("duration", player!!.duration)

            if (player?.videoFormat != null) {
                val videoFormat: Format? = player?.videoFormat
                var width: Int = videoFormat!!.width
                var height: Int = videoFormat!!.height
                val rotationDegrees: Int = videoFormat.rotationDegrees
                // Switch the width/height if video was taken in portrait mode
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = player?.videoFormat!!.height
                    height = player?.videoFormat!!.width
                }
                event.put("width", width)
                event.put("height", height)
            }

            methodChannel?.invokeMethod("player#onPrepared", event)
            eventSink.success(event)
        }
    }

}