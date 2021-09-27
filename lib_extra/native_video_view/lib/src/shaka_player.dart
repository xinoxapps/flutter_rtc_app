import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Callback that is called when the playback of a video is completed.
typedef ShakaPlayerStateCallback = void Function(
    ShakaPlayerController? controller);

/// Callback that is called when the player had an error trying to load/play
typedef ShakaPlayerErrorCallback = void Function(
    ShakaPlayerController? controller, ShakaPlayerError error);

/// Callback that indicates the progression of the media being played.
typedef ShakaPlayerProgressionCallback = void Function(
    int? currentTime, int? duration);

class ShakaPlayerView extends StatefulWidget {
  /// Wraps the [PlatformView] in an [AspectRatio]
  /// to resize the widget once the video is loaded.
  final bool keepAspectRatio;
  final ShakaPlayerStateCallback? stateCallback;
  final ShakaPlayerProgressionCallback? progressCallback;
  final ShakaPlayerErrorCallback? errorCallback;

  ShakaPlayerView({
    Key? key,
    this.keepAspectRatio = true,
    this.stateCallback,
    this.errorCallback,
    this.progressCallback,
  }) : super(key: key);

  @override
  _ShakaPlayerViewState createState() => _ShakaPlayerViewState();
}

enum ShakaPlayerEventType {
  created,
  loaded,
  play,
  pause,
  ended,
  timeupdate,
  seeking,
  seeked,
  unknown
}

enum ShakaPlayerState {
  initialize,
  created,
  loaded,
  playing,
  pause,
  seeking,
  finished
}

class ShakaPlayerEvent {
  final ShakaPlayerEventType? type;

  final bool? paused;
  final int? currentTime;
  final int? duration;
  final double? height;
  final double? width;

  double get aspectRatio =>
      height != null && width != null && height! > 0 && width! > 0
          ? width! / height!
          : 4 / 3;

  ShakaPlayerEvent(
      {this.type,
      this.paused,
      this.currentTime,
      this.duration,
      this.height,
      this.width});

  factory ShakaPlayerEvent.fromJson(Map<String, dynamic> json) {
    var type = json["type"] as String?;
    var paused = json["paused"] != null ? json["paused"] as bool? : true;

    var currentTime = json["currentTime"] != null
        ? (json["currentTime"] as num).round()
        : null;
    var duration =
        json["duration"] != null ? (json["duration"] as num).round() : null;
    var width =
        json["width"] != null ? (json["width"] as num).toDouble() : null;
    var height =
        json["height"] != null ? (json["height"] as num).toDouble() : null;

    return ShakaPlayerEvent(
        type: ShakaPlayerEventType.values.firstWhere(
            (elem) => elem.toString().endsWith(type!),
            orElse: () => ShakaPlayerEventType.unknown),
        paused: paused,
        currentTime: currentTime,
        duration: duration,
        width: width,
        height: height);
  }

  @override
  String toString() => "ShakaPlayerEvent $type";
}

class ShakaPlayerError {
  final String? code;

  ShakaPlayerError({this.code});

  factory ShakaPlayerError.fromJson(Map<String, dynamic> json) {
    return ShakaPlayerError(code: json["code"] as String?);
  }

  @override
  String toString() => "ShakaPlayerError $code";
}

class ShakaPlayerController {
  final WebViewController webViewController;
  final List<Size> _sizes = [Size.infinite];
  final List<int?> _durations = [];
  final List<ShakaPlayerState> _states = [ShakaPlayerState.initialize];

  ShakaPlayerController(this.webViewController);

  set state(ShakaPlayerState current) {
    if (state != current) {
      _states.insert(0, current);
      if (_states.length > 10) {
        _states.length = 10;
      }
    }
  }

  set size(Size current) {
    if (size != current) {
      _sizes.insert(0, current);
      if (_sizes.length > 10) {
        _sizes.length = 10;
      }
    }
  }

  set duration(int? seconds) {
    if (duration != seconds) {
      _durations.insert(0, seconds);
      if (_durations.length > 10) {
        _durations.length = 10;
      }
    }
  }

  int? get duration => _durations.isNotEmpty ? _durations.first : null;
  Size get size => _sizes.isNotEmpty ? _sizes.first : Size.infinite;
  ShakaPlayerState get state =>
      _states.isNotEmpty ? _states.first : ShakaPlayerState.initialize;

  @override
  String toString() =>
      "states: $_states, sizes: $_sizes, durations: $_durations";

  Future<void> load(
      {String? manifestUrl, String? licenseUrl, String? mimeType}) {
    var json = jsonEncode({
      'command': 'load',
      'params': {
        'manifestUrl': manifestUrl,
        'widevineLicenseUrl': licenseUrl,
        'mimeType': mimeType
      }
    });
    return webViewController.evaluateJavascript('externalCommand($json);');
  }

  Future<void> volume(double volume) async =>
      _command('volume', params: <String, dynamic>{'volume': volume});

  Future<void> muted(bool muted) async =>
      _command('muted', params: <String, dynamic>{'muted': muted});

  Future<void> seekTo(int currentTime) async =>
      _command('seekTo', params: <String, dynamic>{'currentTime': currentTime});

  Future<void> play() async => _command('play');

  Future<void> pause() async => _command('pause');

  Future<int> currentTime() async {
    var value =
        await webViewController.evaluateJavascript('externalCurrentTime();');
    return double.tryParse(value)?.round() ?? 0;
  }

  Future<String> _command(String command,
      {Map<String, dynamic>? params}) async {
    var json = jsonEncode({'command': command, 'params': params});
    var value =
        await webViewController.evaluateJavascript('externalCommand($json);');
    return value;
  }
}

class _ShakaPlayerViewState extends State<ShakaPlayerView> {
  WebViewController? _controller;
  ShakaPlayerController? _shakaPlayerController;

  double _aspectRatio = 640.0 / 360.0;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    var child = WebView(
      initialMediaPlaybackPolicy: AutoMediaPlaybackPolicy.always_allow,
      allowsInlineMediaPlayback: true,
      // We cannot embed the content as asset because of the SSL errors
      initialUrl: 'https://kpn-pca.web.app/shakaplayer.html?v=3',
      javascriptMode: JavascriptMode.unrestricted,
      javascriptChannels: Set.from([
        JavascriptChannel(
            name: 'messageHandler',
            onMessageReceived: (JavascriptMessage jsMessage) {
              Map<String, dynamic> json = jsonDecode(jsMessage.message);
              if (json['event'] != null) {
                var event = ShakaPlayerEvent.fromJson(
                    json['event'].cast<String, dynamic>());
                assert(_shakaPlayerController != null);
                var oldState = _shakaPlayerController!.state;
                if (event.type == ShakaPlayerEventType.timeupdate) {
                  widget.progressCallback!(event.currentTime, event.duration);
                } else if (event.type == ShakaPlayerEventType.created) {
                  _shakaPlayerController!.state = ShakaPlayerState.created;
                } else if (event.type == ShakaPlayerEventType.loaded) {
                  _shakaPlayerController!.state = ShakaPlayerState.loaded;
                  _shakaPlayerController!.size =
                      Size(event.width!, event.height!);
                  _shakaPlayerController!.duration = event.duration;
                  _aspectRatio = event.aspectRatio;
                  _loaded = true;
                } else if (event.type == ShakaPlayerEventType.play) {
                  _shakaPlayerController!.state = ShakaPlayerState.playing;
                } else if (event.type == ShakaPlayerEventType.pause) {
                  _shakaPlayerController!.state = ShakaPlayerState.pause;
                } else if (event.type == ShakaPlayerEventType.ended) {
                  _shakaPlayerController!.state = ShakaPlayerState.finished;
                } else if (event.type == ShakaPlayerEventType.seeking) {
                  _shakaPlayerController!.state = ShakaPlayerState.seeking;
                } else if (event.type == ShakaPlayerEventType.seeked) {
                  _shakaPlayerController!.state = event.paused!
                      ? ShakaPlayerState.pause
                      : ShakaPlayerState.playing;
                }
                if (oldState != _shakaPlayerController!.state) {
                  try {
                    widget.stateCallback?.call(_shakaPlayerController);
                  } catch (exc) {
                    widget.errorCallback?.call(_shakaPlayerController,
                        ShakaPlayerError(code: "internal"));
                  }
                  if (mounted) {
                    setState(() {});
                  }
                }
              } else if (json['error'] != null) {
                print("error  ${jsMessage.message}");
                var error = ShakaPlayerError.fromJson(
                    json['error'].cast<String, dynamic>());
                widget.errorCallback!(_shakaPlayerController, error);
              }
            })
      ]),
      onWebViewCreated: (WebViewController webviewController) {
        _controller = webviewController;
        _shakaPlayerController = ShakaPlayerController(webviewController);
      },
      onWebResourceError: (error) {
        print("onWebResourceError $error");
      },
      debuggingEnabled: true,
    );
    Widget videoView = child;
    return Opacity(opacity: _loaded ? 1.0 : 0.0, child: videoView);
  }

  // We cannot embed the content as asset because of the SSL errors
  /*
  _loadHtmlFromAssets() async {
    String file = await rootBundle
        .loadString('packages/native_video_view/assets/shakaplayer.html');
    _controller.loadUrl(Uri.dataFromString(file,
            mimeType: 'text/html', encoding: Encoding.getByName('utf-8'))
        .toString());
  }
   */

  handleError(ShakaPlayerError error) {
    print("$error");
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.code!)));
  }
}
