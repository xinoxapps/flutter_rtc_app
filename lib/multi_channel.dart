import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:native_video_view/native_video_view.dart';

import 'kpn.dart';

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
    return FutureBuilder<StreamManifest>(
        future: KPNStreaming()
            .fetchManifest(), // a previously-obtained Future<String> or null
        builder:
            (BuildContext context, AsyncSnapshot<StreamManifest> manifest) {
          if (manifest.hasData) {
            return _renderVideoPlayer(context, manifest.data!);
          } else if (manifest.hasError) {
            return Container(
              child: Text("Error, failed to fetch stream manifest from KPN"),
            );
          } else {
            return Container(
              child: Text("Loading"),
            );
          }
        });
  }

  Widget _renderVideoPlayer(
      BuildContext context, StreamManifest streamManifest) {
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
            controller.setVideoSource(streamManifest.metadata.srcURL.toString(),
                drmCertificateUrl:
                    streamManifest.metadata.certificateURL?.toString(),
                drmLicenseUrl:
                    streamManifest.metadata.licenseAcquisitionURL?.toString(),
                mimeType: streamManifest.metadata.mimeType.name);
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
