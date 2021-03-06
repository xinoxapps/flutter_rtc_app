import 'dart:developer';

import 'package:agora_rtc_engine/rtc_channel.dart';
import 'package:agora_rtc_engine/rtc_engine.dart';
import 'package:agora_rtc_engine/rtc_local_view.dart' as RtcLocalView;
import 'package:agora_rtc_engine/rtc_remote_view.dart' as RtcRemoteView;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_plugin_test/native_view_example.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import 'config_rtc.dart' as config;

const _channelId0 = 'channel0';
const _channelId1 = 'channel1';

/// MultiChannel Example
class MultiChannel extends StatefulWidget {
  RtcEngine? _engine;
  RtcChannel? _channel0, _channel1;

  @override
  State<StatefulWidget> createState() => _State();
}

class _State extends State<MultiChannel> {
  late VideoPlayerController _controller;

  String? renderChannelId;
  bool isJoined0 = false, isJoined1 = false;
  List<int> remoteUid0 = [], remoteUid1 = [];

  @override
  void initState() {
    super.initState();
    this._initEngine();

    _controller = VideoPlayerController.asset('assets/example.mp4');
    _controller.addListener(() {
      setState(() {});
    });
    _controller.setLooping(true);
    _controller.initialize().then((_) => setState(() {}));
    _controller.play();
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
    widget._engine?.destroy();
  }

  _initEngine() async {
    widget._engine =
        await RtcEngine.createWithConfig(RtcEngineConfig(config.appId));

    await widget._engine?.enableVideo();
    await widget._engine?.startPreview();
    await widget._engine?.setChannelProfile(ChannelProfile.LiveBroadcasting);
    await widget._engine?.setClientRole(ClientRole.Broadcaster);
  }

  Future<void> _handleCameraAndMic(Permission permission) async {
    final status = await permission.request();
    print(status);
  }

  _joinChannel0() async {
    await _handleCameraAndMic(Permission.camera);
    await _handleCameraAndMic(Permission.microphone);

    widget._channel0 = await RtcChannel.create(_channelId0);
    if (widget._channel0 != null) {
      this._addListener(widget._channel0!);

      await widget._channel0!.setClientRole(ClientRole.Broadcaster);
      await widget._channel0!
          .joinChannel(null, null, 0, ChannelMediaOptions(true, true));
    }
  }

  _joinChannel1() async {
    widget._channel1 = await RtcChannel.create(_channelId1);
    if (widget._channel1 != null) {
      this._addListener(widget._channel1!);

      await widget._channel1!.setClientRole(ClientRole.Broadcaster);
      await widget._channel1!
          .joinChannel(null, null, 0, ChannelMediaOptions(true, true));
    }
  }

  _addListener(RtcChannel channel) {
    String channelId = channel.channelId;
    channel.setEventHandler(
        RtcChannelEventHandler(joinChannelSuccess: (channel, uid, elapsed) {
      log('joinChannelSuccess ${channel} ${uid} ${elapsed}');
      if (channelId == _channelId0) {
        setState(() {
          isJoined0 = true;
        });
      } else if (channelId == _channelId1) {
        setState(() {
          isJoined1 = true;
        });
      }
    }, userJoined: (uid, elapsed) {
      log('userJoined ${channel.channelId} $uid $elapsed');
    }, userOffline: (uid, reason) {
      log('userOffline ${channel.channelId} $uid $reason');
    }, leaveChannel: (stats) {
      log('leaveChannel ${channel.channelId} ${stats.toJson()}');
      if (channelId == _channelId0) {
        this.setState(() {
          isJoined0 = false;
          remoteUid0.clear();
        });
      } else if (channelId == _channelId1) {
        this.setState(() {
          isJoined1 = false;
          remoteUid1.clear();
        });
      }
    }, remoteVideoStateChanged: (uid, state, reason, elapsed) {
      log('remoteVideoStateChanged ${uid} ${state} ${reason} ${elapsed}');
      if (state == VideoRemoteState.Starting) {
        if (channelId == _channelId0) {
          this.setState(() {
            remoteUid0.add(uid);
          });
        } else if (channelId == _channelId1) {
          this.setState(() {
            remoteUid1.add(uid);
          });
        }
      } else if (state == VideoRemoteState.Stopped) {
        if (channelId == _channelId0) {
          this.setState(() {
            remoteUid0.removeWhere((element) => element == uid);
          });
        } else if (channelId == _channelId1) {
          this.setState(() {
            remoteUid1.removeWhere((element) => element == uid);
          });
        }
      }
    }));
  }

  _publishChannel0() async {
    await widget._channel1?.unpublish();
    await widget._channel0?.publish();
  }

  _publishChannel1() async {
    await widget._channel0?.unpublish();
    await widget._channel1?.publish();
  }

  _leaveChannel0() async {
    await widget._channel0?.leaveChannel();
  }

  _leaveChannel1() async {
    await widget._channel1?.leaveChannel();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: RaisedButton(
                    onPressed: () {
                      if (isJoined0) {
                        this._leaveChannel0();
                      } else {
                        this._joinChannel0();
                      }
                    },
                    child: Text('${isJoined0 ? 'Leave' : 'Join'} $_channelId0'),
                  ),
                )
              ],
            ),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: RaisedButton(
                    onPressed: () {
                      if (isJoined1) {
                        this._leaveChannel1();
                      } else {
                        this._joinChannel1();
                      }
                    },
                    child: Text('${isJoined1 ? 'Leave' : 'Join'} $_channelId1'),
                  ),
                )
              ],
            ),
            // Simple plugin showing a native canvas with text.
            _renderTextPlugIn(),
            // Video plugin, works fine in combination with the above plugin.
            _renderVideoPlayer(),
            // Enable TextureView or SurfaceView, in both cases the freeze occurs, or unstable framerate when _renderPlayer is included.
            _renderRtc(useTextureView: false),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RaisedButton(
                onPressed: this._publishChannel0,
                child: Text('Publish ${_channelId0}'),
              ),
              RaisedButton(
                onPressed: () {
                  setState(() {
                    renderChannelId = _channelId0;
                  });
                },
                child: Text('Render ${_channelId0}'),
              ),
              RaisedButton(
                onPressed: this._publishChannel1,
                child: Text('Publish ${_channelId1}'),
              ),
              RaisedButton(
                onPressed: () {
                  setState(() {
                    renderChannelId = _channelId1;
                  });
                },
                child: Text('Render ${_channelId1}'),
              ),
            ],
          ),
        )
      ],
    );
  }

  _renderTextPlugIn() {
    return SizedBox(height: 100, child: NativeExampleView());
  }

  _renderVideoPlayer() {
    return SizedBox(height: 200, child: VideoPlayer(_controller));
  }

  _renderRtc({bool useTextureView = false}) {
    List<int>? remoteUid;
    if (renderChannelId == _channelId0) {
      remoteUid = remoteUid0;
    } else if (renderChannelId == _channelId1) {
      remoteUid = remoteUid1;
    }
    return Expanded(
      child: Stack(
        children: [
          if (useTextureView)
            RtcLocalView.TextureView(
              channelId: renderChannelId,
              renderMode: VideoRenderMode.FILL,
              mirrorMode: VideoMirrorMode.Enabled,
            ),
          if (!useTextureView)
            RtcLocalView.SurfaceView(
              channelId: renderChannelId,
              renderMode: VideoRenderMode.FILL,
              mirrorMode: VideoMirrorMode.Enabled,
            ),
          if (remoteUid != null)
            Align(
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.of(remoteUid.map(
                    (e) => Container(
                      width: 120,
                      height: 120,
                      child: RtcRemoteView.TextureView(
                        renderMode: VideoRenderMode.FILL,
                        uid: e,
                        channelId: renderChannelId,
                      ),
                    ),
                  )),
                ),
              ),
            )
        ],
      ),
    );
  }
}
