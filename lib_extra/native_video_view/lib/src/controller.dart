part of native_video_view;

abstract class VideoViewController {
  VideoFile? get videoFile;
  void dispose();

  Future<void> setVideoSource(
    String videoUrl, {
    String? drmLicenseUrl,
    String? drmCertificateUrl,
    String? mimeType, //='video/mp4'
    bool requestAudioFocus = false,
    bool isKpnWeb = false,
  });

  bool isReady();

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<int> currentPosition();
  Future<void> seekTo(int position);
  Future<bool?> isPlaying();
  Future<void> toggleSound();
  Future<void> setVolume(double volume);
}

class ShakaVideoViewController implements VideoViewController {
  final ShakaPlayerController shaka;
  ShakaVideoViewController(this.shaka);

  bool isReady() => shaka.size != Size.infinite;

  VideoFile get videoFile {
    return VideoFile._(
        source: "",
        info: VideoInfo._(
          height: shaka.size.height,
          width: shaka.size.width,
          duration: 0,
        ));
  }

  void dispose() {}

  Future<void> setVideoSource(
    String videoUrl, {
    String? drmLicenseUrl,
    String? drmCertificateUrl,
    String? mimeType, //='video/mp4'
    bool requestAudioFocus = false,
    bool isKpnWeb = false,
  }) async {
    assert(shaka.state != ShakaPlayerState.initialize);
    return shaka.load(
        manifestUrl: videoUrl, licenseUrl: drmLicenseUrl, mimeType: mimeType);
  }

  Future<void> play() async {
    return shaka.play();
  }

  Future<void> pause() async {
    return shaka.pause();
  }

  Future<bool> stop() => pause().then((value) => value as bool);

  Future<int> currentPosition() async {
    return shaka.currentTime();
  }

  Future<void> seekTo(int position) async {
    return shaka.seekTo(position);
  }

  Future<bool> isPlaying() async {
    return Future.value(shaka.state == ShakaPlayerState.playing);
  }

  Future<void> toggleSound() async {
    // return shaka.toggleMuted();
  }

  Future<void> setVolume(double volume) async {
    return shaka.volume(volume);
  }
}

/// Controller used to call the functions that
/// controls the [VideoView] in Android and the [AVPlayer] in iOS.
class NativeVideoViewController implements VideoViewController {
  /// MethodChannel to call methods from the platform.
  final MethodChannel channel;

  /// State of the [StatefulWidget].
  final _NativeVideoViewState _videoViewState;

  /// Current video file loaded in the player.
  /// The [info] attribute is loaded when the player reaches
  /// the prepared state.
  VideoFile? _videoFile;

  /// Returns the video file loaded in the player.
  /// The [info] attribute is loaded when the player reaches
  /// the prepared state.
  @override
  VideoFile? get videoFile => _videoFile;

  /// Timer to control the progression of the video being played.
  Timer? _progressionController;

  static const int kUninitializedTextureId = -1;
  int _textureId = kUninitializedTextureId;
  int get textureId => _textureId;

  bool isReady() => true;

  /// Constructor of the class.
  NativeVideoViewController._(
    this.channel,
    this._videoViewState,
  ) : assert(channel != null) {
    channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Initialize the controller.
  static Future<VideoViewController> init(
    int id,
    _NativeVideoViewState videoViewState,
  ) async {
    print("VideoViewController init $id");
    assert(id != null);
    /*TODO registering channel name without $id appended for web separately
       as we cannot append in the plugin [NativeVideoViewWebPlugin] registerWith method*/
    final MethodChannel channel = kIsWeb
        ? MethodChannel('native_video_view')
        : MethodChannel('native_video_view_$id');
    return NativeVideoViewController._(
      channel,
      videoViewState,
    );
  }

  /// Disposes and stops some tasks from the controller.
  @override
  void dispose() {
    _stopProgressTimer();
  }

  /// Handle the calls from the listeners of state of the player.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'player#onCompletion':
        _stopProgressTimer();
        _videoViewState.notifyControlChanged(_MediaControl.stop);
        _videoViewState.onCompletion(this);
        break;
      case 'player#onError':
        _videoFile = null;
        int what = call.arguments['what'] ?? -1;
        int extra = call.arguments['extra'] ?? -1;
        String? message = call.arguments['message'];
        _videoViewState.onError(this, what, extra, message);
        break;
      case 'player#onPrepared':
        VideoInfo videoInfo = VideoInfo._fromJson(call.arguments);
        _videoFile =
            _videoFile!._copyWith(changes: VideoFile._(info: videoInfo));
        _videoViewState.onPrepared(this, videoInfo);
        break;
    }
  }

  /// Sets the video source from an asset file.
  /// The [sourceType] parameter could be [VideoSourceType.asset],
  /// [VideoSourceType.file] or [VideoSourceType.network]
  @override
  Future<void> setVideoSource(
    String videoUrl, {
    String? drmLicenseUrl,
    String? drmCertificateUrl,
    String? mimeType, //='video/mp4'
    bool requestAudioFocus = false,
    bool isKpnWeb = false,
  }) async {
    Map<String, dynamic> args = {
      "videoUrl": videoUrl,
      "drmLicenseUrl": drmLicenseUrl,
      "drmCertificateUrl": drmCertificateUrl,
      "sourceType": VideoSourceType.network.toString(),
      "requestAudioFocus": requestAudioFocus,
      "isKpnWeb": isKpnWeb,
    };
    try {
      var result =
          await channel.invokeMethod<dynamic>("player#setVideoSource", args);
      if (result is LinkedHashMap) {
        //Logic to get the currentTextureId used for web player widget display
        LinkedHashMap<dynamic, dynamic> linkedHashMap = result;
        HashMap<String, int> valuesMap =
            linkedHashMap.map((a, b) => MapEntry(a as String, b as int))
                as HashMap<String, int>;
        //result value is using for *Only web player* to get the asynchronous texture id value.
        print('result------- ${valuesMap}');
        _textureId = valuesMap['currentTextureId'] ?? -1;
        _videoViewState.notifyTextureChanged(_textureId);
      }
      _videoFile =
          VideoFile._(source: videoUrl, sourceType: VideoSourceType.network);
    } catch (ex) {
      print(ex);
    }
  }

  /// Starts/resumes the playback of the video.
  Future<void> play() async {
    await channel.invokeMethod("player#start");
    _startProgressTimer();
    _videoViewState.notifyControlChanged(_MediaControl.play);
  }

  /// Pauses the playback of the video. Use
  /// [play] to resume the playback at any time.
  Future<void> pause() async {
    await channel.invokeMethod("player#pause");
    _stopProgressTimer();
    _videoViewState.notifyControlChanged(_MediaControl.pause);
  }

  /// Stops the playback of the video.
  Future<void> stop() async {
    await channel.invokeMethod("player#stop");
    _stopProgressTimer();
    _onProgressChanged(null);
    _videoViewState.notifyControlChanged(_MediaControl.stop);
  }

  /// Gets the current position of time in seconds.
  /// Returns the current position of playback in milliseconds.
  Future<int> currentPosition() async {
    final result = await channel.invokeMethod("player#currentPosition");
    return result['currentPosition'] ?? 0;
  }

  /// Moves the cursor of the playback to an specific time.
  /// Must give the [position] of the specific millisecond of playback, if
  /// the [position] is bigger than the duration of source the duration
  /// of the video is used as position.
  Future<void> seekTo(int position) async {
    assert(position != null);
    Map<String, dynamic> args = {"position": position};
    await channel.invokeMethod<void>("player#seekTo", args);
  }

  /// Gets the state of the player.
  /// Returns true if the player is playing or false if is stopped or paused.
  Future<bool?> isPlaying() async {
    final result = await channel.invokeMethod("player#isPlaying");
    return result['isPlaying'];
  }

  /// Changes the state of the volume between muted and not muted.
  /// Returns true if the change was successful or false if an error happened.
  Future<void> toggleSound() async {
    await channel.invokeMethod("player#toggleSound");
    _videoViewState.notifyControlChanged(_MediaControl.toggle_sound);
  }

  /// Sets the volume of the player.
  Future<void> setVolume(double volume) async {
    Map<String, dynamic> args = {"volume": volume};
    await channel.invokeMethod("player#setVolume", args);
  }

  /// Starts the timer that monitor the time progression of the playback.
  void _startProgressTimer() {
    if (_progressionController == null) {
      _progressionController =
          Timer.periodic(Duration(milliseconds: 100), _onProgressChanged);
    }
  }

  /// Stops the progression timer. If [resetCount] is true the elapsed
  /// time is restarted.
  void _stopProgressTimer() {
    if (_progressionController != null) {
      _progressionController!.cancel();
      _progressionController = null;
    }
  }

  /// Callback called by the timer when an event is called.
  /// Updates the elapsed time counter and notifies the widget
  /// state.
  void _onProgressChanged(Timer? timer) async {
    int position = await currentPosition();
    int duration = this.videoFile?.info?.duration ?? 1000;
    _videoViewState.onProgress(position, duration);
  }
}
