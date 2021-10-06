part of native_video_view;

/// Callback that is called when the view is created and ready.
typedef ViewCreatedCallback = void Function(VideoViewController controller);

/// Callback that is called when the playback of a video is completed.
typedef CompletionCallback = void Function(VideoViewController controller);

/// Callback that is called when the player had an error trying to load/play
/// the video source. The values [what] and [extra] are Android exclusives and
/// [message] is iOS exclusive.
typedef ErrorCallback = void Function(
    VideoViewController controller, int what, int extra, String? message);

/// Callback that is called when the player finished loading the video
/// source and is prepared to start the playback. The [controller]
/// and [videoInfo] is given as parameters when the function is called.
/// The [videoInfo] parameter contains info related to the file loaded.
typedef PreparedCallback = void Function(
    VideoViewController controller, VideoInfo videoInfo);

/// Callback that indicates the progression of the media being played.
typedef ProgressionCallback = void Function(int elapsedTime, int? duration);

/// Callback that indicates that the volume has been changed using the
/// media controller.
typedef VolumeChangedCallback = void Function(double volume);

/// Widget that displays a video player.
/// This widget calls an underlying player in the
/// respective platform, [VideoView] in Android and
/// [AVPlayer] in iOS.
class NativeVideoView extends StatefulWidget {
  /// Wraps the [PlatformView] in an [AspectRatio]
  /// to resize the widget once the video is loaded.
  final bool? keepAspectRatio;

  /// Shows a default media controller to control the player state.
  final bool? showMediaController;

  /// Forces the use of ExoPlayer instead of the native VideoView.
  ///
  /// Only in Android.
  final bool? useExoPlayer;

  /// Only in Android.
  final bool? useShakaPlayer;

  /// Determines if the controller should hide automatically.
  final bool? autoHide;

  /// The time after which the controller will automatically hide.
  final Duration? autoHideTime;

  /// Enables the drag gesture over the video to control the volume.
  ///
  /// Default value is false.
  final bool? enableVolumeControl;
  final bool? enableRewindControl;

  /// Instance of [ViewCreatedCallback] to notify
  /// when the view is finished creating.
  final ViewCreatedCallback onCreated;

  /// Instance of [CompletionCallback] to notify
  /// when a video has finished playing.
  final CompletionCallback onCompletion;

  /// Instance of [ErrorCallback] to notify
  /// when the player had an error loading the video source.
  final ErrorCallback? onError;

  /// Instance of [ProgressionCallback] to notify
  /// when the time progresses while playing.
  final ProgressionCallback? onProgress;

  /// Instance of [PreparedCallback] to notify
  /// when the player is ready to start the playback of a video.
  final PreparedCallback onPrepared;

  /// Constructor of the widget.
  const NativeVideoView({
    Key? key,
    this.keepAspectRatio,
    this.showMediaController,
    this.useExoPlayer,
    this.useShakaPlayer,
    this.autoHide,
    this.autoHideTime,
    this.enableVolumeControl,
    this.enableRewindControl,
    required this.onCreated,
    required this.onPrepared,
    required this.onCompletion,
    this.onError,
    this.onProgress,
  })  : assert(onCreated != null && onPrepared != null && onCompletion != null),
        super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _NativeVideoViewState();
  }
}

/// State of the video widget.
class _NativeVideoViewState extends State<NativeVideoView> {
  int get _unInitializedtextureId => -1;

  //_textureId is using for web player
  int? _textureId;

  /// Completer that is finished when [onPlatformViewCreated]
  /// is called and the controller created.
  final Completer<VideoViewController> _controller =
      Completer<VideoViewController>();

  /// Value of the aspect ratio. Changes depending of the
  /// loaded file.
  double _aspectRatio = 4 / 3;

  /// Controller of the MediaController widget. This is used
  /// to update the.
  _MediaControlsController? _mediaController;

  @override
  void initState() {
    super.initState();
    _mediaController = _MediaControlsController();
    _textureId = _unInitializedtextureId;
  }

  /// Disposes the state and remove the temp files created
  /// by the Widget.
  @override
  void dispose() {
    _disposeController();
    super.dispose();
    _textureId = _unInitializedtextureId;
  }

  /// Builds the view based on the platform that runs the app.
  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = <String, dynamic>{
      'useExoPlayer': widget.useExoPlayer ?? false,
    };
    if (widget.useShakaPlayer!) {
      var view = ShakaPlayerView(
          keepAspectRatio: false,
          stateCallback: (ShakaPlayerController? controller) {
            if (controller?.state == ShakaPlayerState.created) {
              //controller.load(manifestUrl: mpdUrl);
              if (widget.onCreated != null) {
                VideoViewController videoViewController =
                    ShakaVideoViewController(controller!);
                widget.onCreated(videoViewController);
              }
            } else if (controller?.state == ShakaPlayerState.loaded) {
              if (widget.onPrepared != null) {
                VideoViewController videoViewController =
                    ShakaVideoViewController(controller!);
                widget.onPrepared(
                    videoViewController,
                    VideoInfo._(
                        height: controller.size.height,
                        width: controller.size.width,
                        duration: controller.duration));
              }
            } else if (controller!.state == ShakaPlayerState.finished) {
              if (widget.onCompletion != null) {
                widget.onCompletion(ShakaVideoViewController(controller));
              }
            }
          },
          errorCallback: (controller, ShakaPlayerError error) {
            if (widget.onError != null) {
              widget.onError!(ShakaVideoViewController(controller!), 0, 0,
                  "Video Error: '${error.code}'");
            }
          },
          progressCallback:
              (int? currentTimeInSeconds, int? durationInSeconds) {
            if (widget.onProgress != null &&
                currentTimeInSeconds != null &&
                durationInSeconds != null) {
              widget.onProgress!(
                  currentTimeInSeconds * 1000, durationInSeconds * 1000);
            }
          });
      return _buildVideoView(child: view);
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        widget.useExoPlayer!) {
      var view = PlatformViewLink(
        viewType: 'native_video_view',
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'native_video_view',
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: StandardMessageCodec(),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(onPlatformViewCreated)
            ..create();
        },
      );
      return _buildVideoView(child: view);
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _buildVideoView(
        child: UiKitView(
          viewType: 'native_video_view',
          onPlatformViewCreated: onPlatformViewCreated,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    } else {
      return Container();
    }
  }

  /// Builds the video view depending of the configuration.
  Widget _buildVideoView({Widget? child}) {
    bool keepAspectRatio = widget.keepAspectRatio ?? false;
    bool showMediaController = widget.showMediaController ?? false;
    Widget? videoView = keepAspectRatio
        ? AspectRatio(
            child: child,
            aspectRatio: _aspectRatio,
          )
        : child;
    var widgetOf = showMediaController
        ? _MediaController(
            child: videoView,
            controller: _mediaController,
            autoHide: widget.autoHide,
            autoHideTime: widget.autoHideTime,
            enableVolumeControl: widget.enableVolumeControl,
            enableRewindControl: widget.enableRewindControl,
            onControlPressed: _onControlPressed,
            onPositionChanged: _onPositionChanged,
            onVolumeChanged: _onVolumeChanged,
          )
        : videoView;

    return widgetOf ?? Container();
  }

  /// Callback that is called when the view is created in the platform.
  Future<void> onPlatformViewCreated(int id) async {
    print("onPlatformViewCreated  $id ");
    final VideoViewController controller =
        await NativeVideoViewController.init(id, this);
    print("onPlatformViewCreated  complete ");
    _controller.complete(controller);
    print("onPlatformViewCreated after complete ");
    if (widget.onCreated != null) widget.onCreated(controller);
  }

  /// Callback that is called when the view is created in the platform.
  Future<void> onPlatformViewCreatedWeb(int id) async {
    /*TODO limiting the call to VideoViewController.init method in web version. Reason explained below.
    Web player build on HtmlElementViewEx which works with videoElement tag(appended with texture).
    When for the first time call to init(-1) with default value -1, creates channel between player widget
    and NativeVideoViewWebPlugin. And the same time video tag will be generated as 'videoPlayer-$id' (videoPlayer-1)
    and is ready for use. Once tag generated in plugin, we are notifying web widget with valid
    tag(appended with texture). This is sufficient to display and play the video.

    But, once we notify the web widget of valid 'videoPlayer-$id', again full widget is reloading and calling
    init(1) method with the generated texture(1), it again generates another videoPlayer tag (videoPlayer-2)
    and it repeats n number of times. So which is not needed. We just need the first valid videoPlayer-1 tag.

    Solutions added is: once the init() called and created a VideoViewController that assigned to _controller.
    Next time before calling init we are checking _controller already initialized and ready for use.
    if it is ready we are skipping the subsequent init calls.

    **Note:** inside the init method we are registering native_video_view without appending id for the web version.
    * */
    print("onPlatformViewCreatedWeb1");
    if (!_controller.isCompleted) {
      print("onPlatformViewCreatedWeb2");
      try {
        final VideoViewController controller =
            await NativeVideoViewController.init(id, this);
        _controller.complete(controller);
        print("onPlatformViewCreated after complete ");
        widget.onCreated(controller);
      } catch (exc) {
        print("onPlatformViewCreated after error ");
      }
    }
  }

  /// Disposes the controller of the player.
  void _disposeController() async {
    final controller = await _controller.future;
    if (controller != null) controller.dispose();
  }

  /// Function that is called when the platform notifies that the video has
  /// finished playing.
  /// This function calls the widget's [CompletionCallback] instance.
  void onCompletion(VideoViewController controller) {
    if (widget.onCompletion != null) widget.onCompletion(controller);
  }

  /// Notifies when an action of the player (play, pause & stop) must be
  /// reflected by the media controller view.
  void notifyControlChanged(_MediaControl mediaControl) {
    if (_mediaController != null)
      _mediaController!.notifyControlPressed(mediaControl);
  }

  //TODO format is required
  void notifyTextureChanged(int textureId) {
    if (!kIsWeb) {
      return;
    }
    print('notifyTextureChanged $textureId');
    setState(() {
      _textureId = textureId;
    });
  }

  /// Notifies the player position to the media controller view.
  void notifyPlayerPosition(int position, int? duration) {
    if (_mediaController != null)
      _mediaController!.notifyPositionChanged(position, duration);
  }

  /// Function that is called when the platform notifies that an error has
  /// occurred during the video source loading.
  /// This function calls the widget's [ErrorCallback] instance.
  void onError(
      VideoViewController controller, int what, int extra, String? message) {
    if (widget.onError != null)
      widget.onError!(controller, what, extra, message);
  }

  /// Function that is called when the platform notifies that the video
  /// source has been loaded and is ready to start playing.
  /// This function calls the widget's [PreparedCallback] instance.
  void onPrepared(VideoViewController controller, VideoInfo videoInfo) {
    if (videoInfo != null) {
      setState(() {
        _aspectRatio = videoInfo.aspectRatio;
      });
      notifyPlayerPosition(0, videoInfo.duration);
      if (widget.onPrepared != null) widget.onPrepared(controller, videoInfo);
    }
  }

  /// Function that is called when the player updates the time played.
  void onProgress(int position, int duration) {
    if (widget.onProgress != null) widget.onProgress!(position, duration);
    notifyPlayerPosition(position, duration);
  }

  /// When a control is pressed in the media controller, the actions are
  /// realized by the [VideoViewController] and then the result is returned
  /// to the media controller to update the view.
  void _onControlPressed(_MediaControl mediaControl) async {
    VideoViewController controller = await _controller.future;
    if (controller != null) {
      switch (mediaControl) {
        case _MediaControl.pause:
          controller.pause();
          break;
        case _MediaControl.play:
          controller.play();
          break;
        case _MediaControl.stop:
          controller.stop();
          break;
        case _MediaControl.fwd:
          int? duration = controller.videoFile?.info?.duration;
          int position = await controller.currentPosition();
          if (duration != null && position != -1) {
            int newPosition =
                position + 3000 > duration ? duration : position + 3000;
            controller.seekTo(newPosition);
            notifyPlayerPosition(newPosition, duration);
          }
          break;
        case _MediaControl.rwd:
          int? duration = controller.videoFile?.info?.duration;
          int position = await controller.currentPosition();
          if (duration != null && position != -1) {
            int newPosition = position - 3000 < 0 ? 0 : position - 3000;
            controller.seekTo(newPosition);
            notifyPlayerPosition(newPosition, duration);
          }
          break;
        case _MediaControl.toggle_sound:
          controller.toggleSound();
          break;
      }
    }
  }

  /// When the position is changed in the media controller, the action is
  /// realized by the [VideoViewController] to change the position of
  /// the video playback.
  void _onPositionChanged(int position, int? duration) async {
    var controller = await _controller.future;
    controller.seekTo(position);
  }

  /// When the position is changed in the media controller, the action is
  /// realized by the [VideoViewController] to change the position of
  /// the video playback.
  void _onVolumeChanged(double volume) async {
    VideoViewController controller = await _controller.future;
    if (controller != null) controller.setVolume(volume);
  }
}
