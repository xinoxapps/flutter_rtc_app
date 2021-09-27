import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:native_video_view/native_video_view.dart';

/// MultiChannel Example
class MultiChannel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<MultiChannel> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _renderVideoPlayer(context);
  }

  @override
  Widget _renderVideoPlayer(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('shaka app'),
      ),
      body: Container(
        alignment: Alignment.center,
        child: NativeVideoView(
          keepAspectRatio: true,
          showMediaController: true,
          useShakaPlayer: true,
          useExoPlayer: false,
          onCreated: (controller) {
            controller.setVideoSource(
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                mimeType: 'video/mp4');
          },
          onPrepared: (controller, info) {
            controller.play();
          },
          onError: (controller, what, extra, message) {
            print('Player Error ($what | $extra | $message)');
          },
          onCompletion: (controller) {
            print('Video completed');
          },
          onProgress: (progress, duration) {
            print('$progress | $duration');
          },
        ),
      ),
    );
  }
}
