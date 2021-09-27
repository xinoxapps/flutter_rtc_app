part of native_video_view;

enum PlayPauseOverlayIcon { loading, play, pause, none }

class PlayPauseOverlay extends StatelessWidget {
  final GestureTapCallback? onTap;
  final PlayPauseOverlayIcon icon;
  final Color iconColor;
  final Widget? child;

  const PlayPauseOverlay(
      {this.onTap,
      this.iconColor = Colors.green,
      this.child,
      this.icon = PlayPauseOverlayIcon.loading});

  @override
  Widget build(BuildContext context) {
    if (icon == PlayPauseOverlayIcon.none && child == null) {
      return Container();
    } else if (icon == PlayPauseOverlayIcon.loading) {
      return Container(
          width: double.maxFinite,
          height: double.maxFinite,
          child: Center(
            child: CircularProgressIndicator(),
          ));
    } else
      return Stack(
        children: <Widget>[
          AnimatedSwitcher(
            duration: Duration(milliseconds: 50),
            reverseDuration: Duration(milliseconds: 200),
            child: Container(
              key: ValueKey("$icon"),
              color: Colors.black26,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != PlayPauseOverlayIcon.none)
                      GestureDetector(
                        onTap: this.onTap,
                        child: Icon(
                          icon == PlayPauseOverlayIcon.pause
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: iconColor,
                          size: 50.0,
                        ),
                      ),
                    if (child != null) child!
                  ],
                ),
              ),
            ),
          ),
        ],
      );
  }
}
