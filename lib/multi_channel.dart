import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:native_video_view/native_video_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'kpn.dart';

/// MultiChannel Example
class MultiChannel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<MultiChannel> {
  String stateText = "Loading..";
  bool showDefaultWebView = false;
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
    return Column(children: [
      Text(stateText),
      Expanded(
          child: FutureBuilder<StreamManifest>(
              future: KPNStreaming()
                  .fetchManifest(), // a previously-obtained Future<String> or null
              builder: (BuildContext context,
                  AsyncSnapshot<StreamManifest> manifest) {
                if (manifest.hasData) {
                  return this.showDefaultWebView
                      ? _renderWeb()
                      : _renderVideoPlayer(context, manifest.data!);
                } else if (manifest.hasError) {
                  return Container(
                    child:
                        Text("Error, failed to fetch stream manifest from KPN"),
                  );
                } else {
                  return Container(
                    child: Text("Loading"),
                  );
                }
              }))
    ]);
  }

  Widget _renderWeb() {
    print("render default");
    return Container(
        color: Colors.red,
        alignment: Alignment.center,
        child: WebView(
          initialUrl: 'https://shaka-player-demo.appspot.com/support.html',
        ));
  }

  Widget _renderVideoPlayer(
      BuildContext context, StreamManifest streamManifest) {
    return Container(
      color: Colors.green,
      alignment: Alignment.center,
      child: NativeVideoView(
        keepAspectRatio: true,
        showMediaController: true,
        useShakaPlayer: true,
        useExoPlayer: false,
        onCreated: (controller) {
          setState(() {
            stateText = "created";
          });

          controller.setVideoSource(streamManifest.metadata.srcURL.toString(),
              drmCertificateUrl:
                  streamManifest.metadata.certificateURL?.toString(),
              drmLicenseUrl:
                  streamManifest.metadata.licenseAcquisitionURL?.toString(),
              mimeType: streamManifest.metadata.mimeType.name);

          /* controller.setVideoSource(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
              mimeType: 'video/mp4');
           */
        },
        onPrepared: (controller, info) {
          print("ready");
          setState(() {
            stateText = "ready";
          });
          controller.play();
        },
        onError: (controller, what, extra, message) {
          print("error");
          setState(() {
            showDefaultWebView = true;
            stateText = 'Player Error ($what | $extra | $message)';
          });
        },
        onCompletion: (controller) {
          print("completed");
          setState(() {
            stateText = 'Completed';
          });
        },
        onProgress: (progress, duration) {
          print('$progress | $duration');
        },
      ),
    );
  }
}
