
import React, { useEffect } from 'react';
import PropTypes from 'prop-types';

import './Player.scss';
import 'shaka-player/dist/controls.css';

import createUiConfig from './utils/createUiConfig';
import createPlayerConfig from './utils/createPlayerConfig';
import { CastProxy } from './CastProxy';

const ShakaPlayer = ({
  servers,
  advanced,
  certificate,
  src,
  startTimeInSeconds,
  castConfig,
  children,
  onTimeUpdate,
  onError = () => {},
}) => {
  const MULTIPLIER_DELAY = 1500;
  const multipliers = {};

  const videoContainer = React.useRef();
  const videoElement = React.useRef();

  useEffect(() => {
    const player = new shaka.Player(videoElement.current);

    // Important for FairPlay, safari support
    shaka.polyfill.installAll();

    if (certificate) {
      player.getNetworkingEngine().clearAllRequestFilters();
      player.getNetworkingEngine().registerRequestFilter((type, request) => {
        if (type !== shaka.net.NetworkingEngine.RequestType.LICENSE) {
          return;
        }

        const decoded = new TextDecoder('utf-8').decode(request.body).substring(4);

        request.allowCrossSiteCredentials = false;
        request.headers['Content-Type'] = 'application/octet-stream';
        request.body = shaka.util.Uint8ArrayUtils.fromBase64(decoded);
      });

      player.configure('drm.advanced.com\\.apple\\.fps\\.1_0.serverCertificate', certificate);
    }

    if (servers['com.microsoft.playready']) {
      player.getNetworkingEngine().registerRequestFilter((type, request) => {
        if (type === shaka.net.NetworkingEngine.RequestType.LICENSE) {
          request.uris = [servers['com.microsoft.playready']];
        }
      });
      delete servers['com.microsoft.playready'];
    }

    const castProxy = new CastProxy({ video: videoElement.current, player, ...castConfig });
    const ui = new shaka.ui.Overlay(player, videoContainer.current, videoElement.current, castProxy);

    const playerConfig = createPlayerConfig({ servers, advanced });
    const uiConfig = createUiConfig({ children });

    player.configure(playerConfig);
    ui.configure(uiConfig);

    player.addEventListener('error', handleError);

    window.player = player;
    window.player.castProxy = castProxy;
    window.player.controls = ui.getControls();

    player.load(src, startTimeInSeconds).then(() => {
      videoElement.current.play();
      videoContainer.current.focus();

      videoElement.current.addEventListener('timeupdate', onTimeUpdate);
      videoElement.current.addEventListener('volumechange', onVolumeChange);

      videoElement.current.muted = localStorage.getItem('pctv.shaka.muted') === 'true';
      const persistentVolume = localStorage.getItem('pctv.shaka.volume');

      if (persistentVolume) {
        videoElement.current.volume = parseInt(persistentVolume, 10) / 100;
      }
    });

    return () => {
      player.destroy();
    };
  }, []);

  const handleKeyBoardEvents = (event) => {
    const key = event.key.toLowerCase();

    const multiplierTimeoutHandler = () => {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = null;
      window.player.controls.setControlsActive(false);
    };

    if (!multipliers[key]) {
      window.player.controls.setControlsActive(true);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), 1];
    } else {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), multipliers[key][1] + 1];
    }
    if (window.player.controls) {
      const media = window.player.controls.getVideo();
      switch (key) {
        case ' ':
          media.paused ? media.play() : media.pause();
          break;
        case 'arrowleft':
          media.currentTime -= 5 * multipliers[key][1];
          break;
        case 'arrowright':
          media.currentTime += 5 * multipliers[key][1];
          break;
        case 'f':
          window.player.controls.toggleFullScreen();
          break;
        default:
          break;
      }
    }
  };

  const handleError = (error) => {
    onError(error);

    if (error.detail.code === 4004) {
      if (window.player) {
        setTimeout(window.player.retryStreaming, 2000);
      }
    }
  };

  const onVolumeChange = () => {
    localStorage.setItem('pctv.shaka.volume', parseInt(videoElement.current.volume * 100, 10));
    localStorage.setItem('pctv.shaka.muted', videoElement.current.muted);
  };

  return (
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      data-shaka-player-container="true"
      className="shakaplayer--video-container"
      ref={videoContainer}
      onKeyUp={handleKeyBoardEvents}
      tabIndex="-1"
    >
      {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
      <video
        width="100%"
        data-t="player-element"
        data-shaka-player="true"
        className="shakaplayer--video-element"
        playsInline
        autoPlay
        ref={videoElement}
      />
    </div>
  );
};

ShakaPlayer.propTypes = {
  servers: PropTypes.object,
  advanced: PropTypes.object,
  certificate: PropTypes.any,
  src: PropTypes.string,
  startTimeInSeconds: PropTypes.number,
  castConfig: PropTypes.object,
  children: PropTypes.any,
  onTimeUpdate: PropTypes.func,
  onError: PropTypes.func,
};

export default ShakaPlayer;
[14:59, 09-06-2021] Dennis Van Maren Kpn: /* eslint-disable */
/* https://github.com/google/shaka-player/issues/2163 */
/* poster="//shaka-player-demo.appspot.com/assets/poster.jpg" */

import React, { useState, useRef, useEffect, FC, KeyboardEvent } from 'react';
import platform from 'platform';

import './Player.scss';

import { useSnackBarContext } from '../../contexts/SnackBarContext';
import { useHaloContext } from '../../contexts/HaloContext';
import { useStorageState } from '../../hooks/useStorageState';

import OverlayItems from './UI/OverlayItems';
import StartOverButton from './UI/StartOverButton';
import FullscreenButton from './UI/FullscreenButton';
import Tooltip from './UI/Tooltip';
import { CastProxy } from './CastProxy';
import LiveIndicatorButton from './UI/LiveIndicatorButton';
import PresentationTimeKpn from './UI/PresentationTimeKpn';
import { streamType } from '../../utils/program';
import { isEmptyObject } from '../../utils/player';
import { isDesktopSafariBrowser, isSafariBrowser } from '../../utils/browser';
import analytics from '../../api/services/analytics';
import createPlayerConfig from './utils/createPlayerConfig';
import { ContentItemDetailType } from '../../types/ContentItemType';
import { ItvVideoUrlSourceType } from '../../types/Itv/ItvVideoUrlType';
import { ShakaError, ShakaRequestType, ShakeResponseType } from '../../types/ShakaType';

declare const shaka: any;

type PlayerType = {
  item: ContentItemDetailType;
  videoURL: ItvVideoUrlSourceType;
  secureCDM: boolean;
  seekLimitRange: { start: number; end: number };
  onLiveSeekableRegionChange: (withinSeekableRange: boolean, withinLiveBuffer: boolean, time: number) => boolean;
  playerHooks: (hooks: any, samePlayerInstance: boolean) => any;
  startOverHandler: (event: Event, hooks: any) => void;
  liveIndicatorHandler?: () => void;
  escapeButtonHandler: () => void;
  handleError: (error: ShakaError) => void;
  avsid: string;
  pin: string;
  poster: string;
  deviceId: string;
  startTime: number;
  isTrailer?: boolean;
};

const Player: FC<PlayerType> = (props) => {
  const [showCaptions, setShowCaptions] = useStorageState('showCaptions', false);
  const [selectedResolution, setSelectedResolution] = useStorageState('selectedResolution', 0);
  const [player, setPlayer] = useState({} as any);
  const [overlayFactory, setOverlayFactory] = useState({} as any);
  const [startOverButtonFactory, setStartOverButtonFactory] = useState({} as any);
  const [hooks, setHooks] = useState({} as any);
  const _seekLimitRange = useRef(props.seekLimitRange);
  const _paused = useRef(false);
  const [loading, setLoading] = useState(false);
  const TIMESHIFT_BUFFER_DEPTH = 4 * 60; // 5 - 1 minutes

  const { showTempMessage } = useSnackBarContext();
  const { translate } = useHaloContext();

  const videoElement = React.useRef<HTMLVideoElement>();
  const videoContainer = React.useRef();

  const multipliers = {} as any;
  const MULTIPLIER_DELAY = 1500;

  function onKeyboardEvent(event: KeyboardEvent) {
    const key = event.key.toLowerCase();
    const multiplierTimeoutHandler = () => {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = null;
      hooks.controls.setControlsActive(false);
    };

    if (!multipliers[key]) {
      hooks.controls.setControlsActive(true);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), 1];
    } else {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), multipliers[key][1] + 1];
    }
    if (hooks.controls) {
      const media = hooks.controls.getVideo();
      switch (key) {
        case ' ':
          media.paused ? media.play() : media.pause();
          break;
        case 'arrowleft':
          media.currentTime -= 5 * multipliers[key][1];
          break;
        case 'arrowright':
          media.currentTime += 5 * multipliers[key][1];
          break;
        case 'arrowup':
          media.volume = Math.min(1, media.volume + 0.1);
          break;
        case 'arrowdown':
          media.volume = Math.max(0, media.volume - 0.1);
          break;
        case 'escape':
          if ('escapeButtonHandler' in props) {
            props.escapeButtonHandler();
          }
          break;
        case 'f':
          hooks.controls.toggleFullScreen();
          break;
        default:
          break;
      }
    }
  }

  function onErrorEvent(event: any) {
    // Extract the shaka.util.Error object from the event.
    if ('detail' in event) {
      onError(event.detail);
    }
  }

  function onError(error: ShakaError) {
    console.error('Error code', error.code, 'object', error);
    switch (error.code) {
      case 6007: // LICENSE_REQUEST_FAILED
      case 1001: // BAD_HTTP_STATUS
      case 1002: // HTTP_ERROR
        if (hooks && hooks.refetchMedia) {
          hooks.refetchMedia(error);
        } else {
          props.handleError(error);
        }
        break;
      case 4001: // DASH_INVALID_XML
      case 4002: // DASH_NO_SEGMENT_INFO
      case 4003: // DASH_EMPTY_ADAPTATION_SET
      case 4004: // DASH_EMPTY_PERIOD
        if (hooks && hooks.player) {
          setTimeout(hooks.player.retryStreaming, 2000);
        } else {
          props.handleError(error);
        }
        break;
      default:
        props.handleError(error);
    }
  }

  function onAutoplayError(error: Error) {
    if (isDesktopSafariBrowser()) {
      showTempMessage({
        message: translate('player.autoplay_error_message'),
        link: { url: translate('player.autoplay_error_link_url'), text: translate('player.autoplay_error_link_text') },
        type: 'WARNING',
        timeout: 10000,
      });
    } else {
      console.warn(`autoplay rejection: ${error}`);
    }
  }

  function seekableRangeCheck() {
    if (hooks && hooks.player && hooks.player.getLoadMode() !== shaka.Player.LoadMode.SRC_EQUALS) {
      const trueSeekRange = hooks.player.seekRange(true);
      if (trueSeekRange && props.onLiveSeekableRegionChange) {
        const val = videoElement.current.currentTime;
        // ignore play event when live and currentTime = 0
        if (val > 0) {
          const withinSeekableRange = val >= trueSeekRange.start;
          const withinLiveBuffer = val >= trueSeekRange.end - TIMESHIFT_BUFFER_DEPTH;
          // case for when the user paused
          if (props.onLiveSeekableRegionChange && (!withinSeekableRange || !withinLiveBuffer)) {
            props.onLiveSeekableRegionChange(withinSeekableRange, withinLiveBuffer, val);
          }
        }
      }
    }
  }

  function loadVideo() {
    const videoUrl = props.videoURL;
    const servers = {} as any;
    const advanced = {} as any;
    const playerPromise = [];

    if (!loading && player && !isEmptyObject(player) && videoUrl && videoUrl.sources) {
      setLoading(true);
      playerPromise.push(player.unload());
      const { contentProtection } = videoUrl.sources;
      player.getNetworkingEngine().clearAllRequestFilters();
      player.getNetworkingEngine().clearAllResponseFilters();
      player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
        // eslint-disable-next-line eqeqeq
        if (type === shaka.net.NetworkingEngine.RequestType.MANIFEST) {
          seekableRangeCheck();
        }
      });
      if (contentProtection && 'fairplay' in contentProtection) {
        player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
          // eslint-disable-next-line eqeqeq
          if (type != shaka.net.NetworkingEngine.RequestType.LICENSE) {
            return;
          }
          request.allowCrossSiteCredentials = false;
          request.headers['Content-Type'] = 'application/octet-stream';
          const decoded = new TextDecoder('utf-8').decode(request.body).substring(4);
          // backend expects unwrapped license requests
          request.body = shaka.util.Uint8ArrayUtils.fromBase64(decoded);
        });
        playerPromise.push(
          fetch(`${contentProtection.fairplay.certificateURL}`, {
            mode: 'cors', // no-cors, *cors, same-origin
            cache: 'no-cache', // *default, no-cache, reload, force-cache, only-if-cached
            credentials: 'omit', // include, *same-origin, omit
            headers: {
              'Content-Type': 'application/octet-stream',
              Referer: 'https://interactievetv.nl',
            },
          })
            .then((res) => res.arrayBuffer())
            .then((buffer) => {
              servers['com.apple.fps.1_0'] = contentProtection.fairplay.licenseAcquisitionURL;
              advanced['com.apple.fps.1_0'] = {
                serverCertificate: new Uint8Array(buffer),
              };
            })
        );
      }
      if (contentProtection && 'widevine' in contentProtection) {
        playerPromise.push(
          new Promise((resolve) => {
            if (props.secureCDM) {
              advanced['com.widevine.alpha'] = {
                videoRobustness: 'HW_SECURE_ALL',
                // 'persistentStateRequired': true,
              };
            }
            servers['com.widevine.alpha'] = contentProtection.widevine.licenseAcquisitionURL;
            resolve(null);
          })
        );
      }

      if (contentProtection && 'playready' in contentProtection) {
        // TODO: Setting a license aquisitionurl for playready though
        // servers['com.microsoft.playready'] before playback,
        // makes CLEAR content fail on edge chromium (07-2022)
        // so for playready license url is set last second with a request filter
        player.getNetworkingEngine().registerResponseFilter((type: number, response: ShakeResponseType) => {
          if (type === shaka.net.NetworkingEngine.RequestType.MANIFEST) {
            if (shaka.util.StringUtils.fromUTF8(response.data).indexOf('urn:mpeg:dash:mp4protection:2011') > -1) {
              servers['com.microsoft.playready'] = contentProtection.playready.licenseAcquisitionURL;
              player.configure(createPlayerConfig({ servers, advanced }));
            }
          }
        });
        player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
          // eslint-disable-next-line eqeqeq
          if (type != shaka.net.NetworkingEngine.RequestType.LICENSE) {
          } else {
            request.uris = [contentProtection.playready.licenseAcquisitionURL];
            return request;
          }
        });
        playerPromise.push(
          new Promise((resolve) => {
            resolve(null);
          })
        );
      }
      if (playerPromise && player && !isEmptyObject(player)) {
        Promise.all(playerPromise).then(() => {
          const playerConfig = createPlayerConfig({ servers, advanced });
          player.configure(playerConfig);
          // use hooks.controls.getPlayer to run .load through castProxy, to be able to block the load
          hooks.controls
            .getPlayer()
            .load(videoUrl.sources.src, props.startTime)
            .then(() => {
              if (player.getLoadMode() === shaka.Player.LoadMode.SRC_EQUALS) {
                const date = (videoElement.current as any).getStartDate();
                if (date && isNaN(date.getTime())) {
                  console.warn('EXT-X-PROGRAM-DATETIME required to get presentation start time as Date!');
                  console.warn('expecting fallback in getStartDateFallback()');
                  // Fallback is expected in videoElement.current.getStartDateFallback():Date
                }
              }
              if (_paused.current) {
                setLoading(false);
                console.warn(`Autoplay Rejection player was paused`);
              } else {
                videoElement.current
                  .play()
                  .catch((error: Error) => {
                    onAutoplayError(error);
                  })
                  .finally(() => {
                    setLoading(false);
                  });
              }
              videoElement.current.muted = localStorage.getItem('pctv.shaka.muted') === 'true';
              const persistentVolume = localStorage.getItem('pctv.shaka.volume');
              if (persistentVolume) {
                videoElement.current.volume = parseInt(persistentVolume, 10) / 100;
              }
              // videoElement.current.videoWidth = 640;
              // Return hooks object with:
              // - hooks.castProxy
              // - hooks.player

              if ('playerHooks' in props && typeof props.playerHooks === 'function') {
                setHooks(props.playerHooks(hooks, false));
              }
            })
            .catch((error: ShakaError) => {
              setLoading(false);
              // error with loading
              if (error.code !== 7000) onError(error);
              else console.warn(error.toString());
            });
        });
      }
    }
  }
  // if props.videoURL is set/updated, update getStartDateFallback
  useEffect(() => {
    if (props.item && videoElement.current) {
      (videoElement.current as any).getStartDateFallback = () => new Date(props.item.airingStartTime);
    }
  }, [props.videoURL]);
  useEffect(() => {
    const overlayFactory = new OverlayItems.Factory(props);
    setOverlayFactory(overlayFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'kpn_overlay',
      overlayFactory
    );
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'fullscreen_kpn',
      new FullscreenButton.Factory()
    );
    const startOverButtonFactory = new StartOverButton.Factory();
    setStartOverButtonFactory(startOverButtonFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'startover_kpn',
      startOverButtonFactory
    );
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'liveindicator_kpn',
      new LiveIndicatorButton.Factory({
        onClick: () => {
          if ('liveIndicatorHandler' in props) {
            props.liveIndicatorHandler();
            if (hooks && hooks.controls) {
              const video = hooks.controls.getVideo();
              if (video && video.paused) {
                video.play();
              }
            }
          }
        },
      })
    );
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'time_and_duration_kpn',
      new PresentationTimeKpn.Factory({
        onClick: () => {
          if ('liveIndicatorHandler' in props) {
            props.liveIndicatorHandler();
            if (hooks && hooks.controls) {
              const video = hooks.controls.getVideo();
              if (video && video.paused) {
                video.play();
              }
            }
          }
        },
      })
    );
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'tooltip',
      new Tooltip.Factory()
    );
    // Important for fairplay, safari support
    shaka.polyfill.installAll();
  }, []);

  // Hook the video.currentTime setter and getter, to prevent unwanted seeks
  // note that this is the only way to do this on the lowest api level -> .currentTime
  // also preventing for instance the safari touch bar seek
  useEffect(() => {
    let ownObjectProto = Object.getPrototypeOf(videoElement.current);
    while (!Object.getOwnPropertyDescriptor(ownObjectProto, 'currentTime')) {
      ownObjectProto = Object.getPrototypeOf(ownObjectProto);
    }
    const ownProperty = Object.getOwnPropertyDescriptor(ownObjectProto, 'currentTime');
    const ownCurrentTimeGet = ownProperty.get.bind(videoElement.current);
    Object.defineProperty(videoElement.current, 'currentTime', {
      configurable: true,
      enumerable: true,
      get: () => ownCurrentTimeGet(),
      set: (val) => {
        if (loading || (hooks && hooks.controls && hooks.controls.getIsLocked())) {
          // console.warn(`ignoring seekLimitRange, loading: ${loading}, player is locked: ${hooks.controls.getIsLocked()}`);
          ownProperty.set.bind(videoElement.current)(val);
          return;
        }
        if (_seekLimitRange.current.end && val > _seekLimitRange.current.end) {
          showTempMessage({ message: translate('player.forward_blocked_message'), type: 'WARNING' });
          ownProperty.set.bind(videoElement.current)(_seekLimitRange.current.end);
        } else if (_seekLimitRange.current.start && val < _seekLimitRange.current.start) {
          ownProperty.set.bind(videoElement.current)(_seekLimitRange.current.start);
          showTempMessage({ message: translate('player.backward_blocked_message'), type: 'WARNING' });
        } else {
          let retval = true;
          if (hooks.player.getLoadMode() !== shaka.Player.LoadMode.SRC_EQUALS) {
            const trueSeekRange = player.seekRange(true);
            if (trueSeekRange && props.onLiveSeekableRegionChange) {
              // onLiveSeekableRegionChange(withinSeekableRange, withinLiveBuffer, time)
              retval = props.onLiveSeekableRegionChange(
                val >= trueSeekRange.start,
                val >= trueSeekRange.end - TIMESHIFT_BUFFER_DEPTH,
                val
              );
            }
          }
          retval && ownProperty.set.bind(videoElement.current)(val);
        }
      },
    });
    return () => {
      Object.defineProperty(videoElement.current, 'currentTime', {
        configurable: true,
        enumerable: true,
        get: ownProperty.get,
        set: ownProperty.set,
      });
    };
  }, [loading === false]);

  useEffect(() => {
    // construct the player
    const player = new shaka.Player(videoElement.current);

    // register error callbacks
    player.addEventListener('error', onErrorEvent);

    player.setTextTrackVisibility(showCaptions);

    // configure the shaka-ui module
    // https://github.com/google/shaka-player/blob/4a7aee1dafcff2697789b326e6d103273d4c58aa/ui/ui.js
    // https://shaka-player-demo.appspot.com/docs/api/ui_controls.js.html
    const overflowMenuButtons = ['captions', 'quality', 'picture_in_picture'];
    const uiConfig = {
      addSeekBar: true,
      addBigPlayButton: true,
      clearBufferOnQualityChange: true,
      showUnbufferedStart: false,
      seekBarColors: {
        base: 'rgba(255, 255, 255, 0.2)',
        buffered: 'var(--hazy-grey)',
        played: 'var(--color-secondary)',
      },
      volumeBarColors: {
        base: 'rgba(255, 255, 255, 0.2)',
        level: 'var(--color-secondary)',
      },
      trackLabelFormat: shaka.ui.TrackLabelFormat.LANGUAGE,
      fadeDelay: 0,
      enableKeyboardPlaybackControls: false, // disable default keyboard implementation
      doubleClickForFullscreen: true,
      enableFullscreenOnRotation: true,
      controlPanelElements: [
        'kpn_overlay',
        // 'play_pause',
        'spacer',
        // 'rewind',
        // 'fast_forward',
        'time_and_duration_kpn',
        'liveindicator_kpn',
        'mute',
        'volume',
        'fullscreen_kpn',
        'tooltip',
        'overflow_menu',
        'startover_kpn',
      ],
      overflowMenuButtons,
    };

    /**
     *   86B8248D	    [DEV] KPN iTV Receiver
     *   B4C900B1	    [UAT] KPN iTV Receiver
     *   7C96B8AD	    KPN iTV Receiver
     *   F8DDE3B4	    Telfort iTV Receiver
     *   C84C2534	    XS4ALL iTV Receiver
     */
    let receiverAppId = '86B8248D'; // KPN[DEV] only used on dev
    if (process.env.APP_ENV === 'production' || process.env.APP_ENV === 'acceptance') {
      switch (process.env.BRAND) {
        case 'XS4ALL':
          receiverAppId = 'C84C2534';
          break;
        case 'TELFORT':
          receiverAppId = 'F8DDE3B4';
          break;
        case 'KPN':
          receiverAppId = '7C96B8AD';
          break;
        default:
          receiverAppId = '86B8248D';
          break;
      }
    }

    const castProxy = (hooks.castProxy = new CastProxy({
      video: videoElement.current,
      player,
      receiverAppId,
      contentUrl: props.avsid,
      pin: props.pin,
      deviceId: props.deviceId,
      isTrailer: props.isTrailer,
    }));

    const ui = new shaka.ui.Overlay(player, videoContainer.current, videoElement.current, castProxy);
    ui.configure(uiConfig);
    const controls = (hooks.controls = ui.getControls());
    (window as any).controls = controls;

    // persist volume level between sessions
    // persist muted between sessions
    const volumeChange = () => {
      localStorage.setItem('pctv.shaka.volume', (videoElement.current.volume * 100).toString());
      localStorage.setItem('pctv.shaka.muted', videoElement.current.muted.toString());
    };
    controls.getVideo().addEventListener('volumechange', volumeChange);
    const playChange = () => {
      _paused.current = false;
      seekableRangeCheck();
    };

    controls.getVideo().addEventListener('play', playChange);

    const pausedChange = () => {
      _paused.current = true;
    };

    controls.getVideo().addEventListener('pause', pausedChange);

    // user changed resolution setting
    let subMenuOpened = false;
    const handleVariantChangedEvent = () => {
      const { height } = player.getVariantTracks().find((track: any) => track.active);
      analytics.changeResolution(height);
      setSelectedResolution(height);
    };
    player.addEventListener('variantchanged', handleVariantChangedEvent);

    const handleAbrEvent = () => {
      if (subMenuOpened && player.getConfiguration().abr.enabled) {
        analytics.changeResolution('auto');
        setSelectedResolution(0);
        subMenuOpened = false;
      }
    };
    player.addEventListener('abrstatuschanged', handleAbrEvent);

    const handleTracksChanged = () => {
      if (selectedResolution > 0) {
        const tracks = player.getVariantTracks();
        if (tracks.length > 0) {
          const track = tracks.find((track: any) => track.height == selectedResolution);
          if (track) {
            player.configure({ abr: { enabled: false } });
            player.selectVariantTrack(track);
          } else {
            player.configure({ abr: { enabled: true } });
          }
        }
      }
    };
    player.addEventListener('trackschanged', handleTracksChanged);

    const handleSubMenuOpen = () => {
      subMenuOpened = true;
    };
    hooks.controls.addEventListener('submenuopen', handleSubMenuOpen);

    // user changes subtitle setting
    const handleCaptionSelectionUpdate = () => {
      setShowCaptions(player.isTextTrackVisible());
      if (showCaptions !== player.isTextTrackVisible()) {
        analytics.changeSubtitleSetting(player.isTextTrackVisible());
      }
    };
    player.addEventListener('texttrackvisibility', handleCaptionSelectionUpdate);

    // user enabled PiP
    videoElement.current.addEventListener('enterpictureinpicture', () => analytics.changePipMode('Enabled'));
    videoElement.current.addEventListener('leavepictureinpicture', () => analytics.changePipMode('Disabled'));

    // failover mode, retryStreaming() when browser comes back online
    const retryStreaming = () => {
      player.retryStreaming();
    };
    window.addEventListener('online', retryStreaming);

    const handleLargeGaps = (event: any) => {
      _seekLimitRange.current.end += event.gapSize + 0.1;
    };
    player.addEventListener('largegap', handleLargeGaps);

    // player constructed, call setPlayer, to start loadVideo hook
    setPlayer(((window as any)._player = hooks.player = player));

    return () => {
      if (videoElement.current.error) {
        console.error('The video was cleaned up, but there was a video.mediaError: ', videoElement.current.error);
      }

      // remove all eventlisteners registered in this hook
      player.removeEventListener('error', onErrorEvent);
      player.removeEventListener('largegap', handleLargeGaps);
      window.removeEventListener('online', retryStreaming);
      controls.getVideo().removeEventListener('volumechange', volumeChange);
      controls.getVideo().removeEventListener('play', playChange);
      controls.getVideo().removeEventListener('pause', pausedChange);
      player.removeEventListener('variantchanged', handleVariantChangedEvent);
      player.removeEventListener('abrstatuschanged', handleAbrEvent);
      player.removeEventListener('texttrackvisibility', handleCaptionSelectionUpdate);
      player.removeEventListener('trackschanged', handleTracksChanged);
      hooks.controls.removeEventListener('submenuopen', handleSubMenuOpen);
      videoElement.current.removeEventListener('enterpictureinpicture', () => analytics.changePipMode('Enabled'));
      videoElement.current.removeEventListener('leavepictureinpicture', () => analytics.changePipMode('Disabled'));

      // end pip picture in picture session
      if ((document as any).pictureInPictureElement) {
        (document as any).exitPictureInPicture();
      }

      // destroy player and controls (ui)
      controls.destroy();
      analytics.stopVideo(streamType(props.item));
      return player.destroy();
    };
  }, []);
  useEffect(loadVideo, [player, props.videoURL]);
  useEffect(() => {
    _seekLimitRange.current = props.seekLimitRange;
  }, [props.seekLimitRange]);
  useEffect(() => {
    if (overlayFactory && !isEmptyObject(overlayFactory)) {
      overlayFactory.update(props.children);
    }
  }, [overlayFactory, props.children]);
  useEffect(() => {
    if (startOverButtonFactory && !isEmptyObject(startOverButtonFactory)) {
      startOverButtonFactory.update({
        onClick:
          props.startOverHandler &&
          ((event: Event) => {
            props.startOverHandler(event, hooks);
          }),
      });
    }
  }, [startOverButtonFactory, props.startOverHandler]);

  return (
    <div
      data-t="player-container"
      onKeyUp={onKeyboardEvent}
      tabIndex={-1}
      className="shakaplayer--video-container"
      ref={videoContainer}
    >
      <video
        data-t="player-element"
        className="shakaplayer--video-element"
        poster={props.poster}
        autoPlay={!_paused.current}
        ref={videoElement}
        onSeeking={(event: React.SyntheticEvent<HTMLVideoElement, Event>) => {
          // seek fix for touch-bar and non-inline videoElement
          if (hooks.player.getLoadMode() === shaka.Player.LoadMode.SRC_EQUALS) {
            const video = event.target as HTMLVideoElement;
            const val = video.currentTime;
            if (_seekLimitRange.current.end && val > _seekLimitRange.current.end) {
              video.currentTime = _seekLimitRange.current.end;
              showTempMessage({ message: translate('player.forward_blocked_message'), type: 'WARNING' });
            } else if (_seekLimitRange.current.start && val < _seekLimitRange.current.start) {
              video.currentTime = _seekLimitRange.current.start;
              showTempMessage({ message: translate('player.backward_blocked_message'), type: 'WARNING' });
            }
          }
        }}
      />
    </div>
  );
};
export default Player;


const createPlayerConfig = ({ servers, advanced }) => ({
  drm: {
    servers,
    advanced,
    fairPlayTransform: true,
    retryParameters: {
      timeout: 0, // timeout in ms, after which we abort; 0 means never
      maxAttempts: 4, // the maximum number of requests before we fail
      baseDelay: 1500, // the base delay in ms between retries
      backoffFactor: 2, // the multiplicative backoff factor between retries
      fuzzFactor: 0.5, // the fuzz factor to apply to each retry delay
    },
  },
  manifest: {
    dash: {
      ignoreMinBufferTime: true,
    },
    retryParameters: {
      timeout: 0, // timeout in ms, after which we abort; 0 means never
      maxAttempts: 6, // the maximum number of requests before we fail
      baseDelay: 2000, // the base delay in ms between retries
      backoffFactor: 2, // the multiplicative backoff factor between retries
      fuzzFactor: 0.5, // the fuzz factor to apply to each retry delay
    },
  },
  streaming: {
    rebufferingGoal: 2,
    bufferingGoal: 90,
    bufferBehind: 90,
    retryParameters: {
      timeout: 0, // timeout in ms, after which we abort; 0 means never
      maxAttempts: 2, // the maximum number of requests before we fail
      baseDelay: 2000, // the base delay in ms between retries
      backoffFactor: 2, // the multiplicative backoff factor between retries
      fuzzFactor: 0.5, // the fuzz factor to apply to each retry delay
    },
    jumpLargeGaps: true,
    smallGapLimit: 0.6,
  },
  abr: {
    enabled: true,
    defaultBandwidthEstimate: 500000,
    switchInterval: 10,
  },
});

//////////////////////
export const DRM_NONE = 'default';

const drmTypes = {
  default: { videoType: 'DASH_WV', profile: 'G' },
  widevine: { videoType: 'DASH_WV', profile: 'G' },
  playready: { videoType: 'DASH_PR', profile: 'M' },
  fairplay: { videoType: 'DASH_PR', profile: 'A' },
};

export const getDrmType = async () => {
  // If it is apple then it is fairplay
  try {
    new window.WebKitMediaKeys('com.apple.fps');
    return { type: 'fairplay', ...drmTypes['fairplay'] };
  } catch (e) {
    // do nothing
  }

  const basicVideoCapabilities = [
    { contentType: 'video/mp4; codecs="avc1.42E01E"' },
    { contentType: 'video/webm; codecs="vp8"' },
  ];

  const basicConfig = {
    videoCapabilities: basicVideoCapabilities,
  };

  const offlineConfig = {
    videoCapabilities: basicVideoCapabilities,
    persistentState: 'required',
    sessionTypes: ['persistent-license'],
  };

  // Try the offline config first, then fall back to the basic config.
  const configs = [offlineConfig, basicConfig];

  let result;
  /*
  // Check for playready
  try {
    await navigator.requestMediaKeySystemAccess('com.microsoft.playready', configs).then(() => {
      result = 'playready';
    });
  } catch (e) {
    // do nothing
  }

  if (result) {
    return { type: result, ...drmTypes[result] };
  }
  */

  // Check for working Widevine L1 backend
  try {
    const videoCapabilities = [{ contentType: 'video/mp4; codecs="avc1.42E01E"', robustness: 'HW_SECURE_ALL' }];
    const audioCapabilities = [
      {
        robustness: 'SW_SECURE_CRYPTO',
        contentType: 'audio/mp4;codecs="mp4a.40.2"',
      },
    ];
    const mediaKeySystemAccess = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', [
      {
        initDataTypes: ['cenc'],
        persistentState: 'optional',
        distinctiveIdentifier: 'optional',
        sessionTypes: ['temporary'],
        videoCapabilities,
        audioCapabilities,
      },
    ]);
    // try creating the CDM (this fails on some phones, where there is phony L1)
    await mediaKeySystemAccess.createMediaKeys();
    result = 'widevine';
  } catch (e) {
    // do nothing
  }

  if (result) {
    return { type: result, HW_SECURE_ALL: true, ...drmTypes[result] };
  }
  // Check for regular Widevine L3 backend (don't care if it's working)
  try {
    await navigator.requestMediaKeySystemAccess('com.widevine.alpha', configs);
    result = 'widevine';
  } catch (e) {
    // do nothing
  }

  if (result) {
    return { type: result, ...drmTypes[result] };
  }

  return { type: DRM_NONE, ...drmTypes[DRM_NONE] };
};

///////////
/* eslint-disable */
/* https://github.com/google/shaka-player/issues/2163 */
/* poster="//shaka-player-demo.appspot.com/assets/poster.jpg" */

import React, { useState, useRef, useEffect, FC, KeyboardEvent } from 'react';

import './Player.scss';

import { useCastContext } from '../../contexts/CastContext';
import { useHaloContext } from '../../contexts/HaloContext';
import { useUserContext } from '../../contexts/UserContext';
import { useSnackBarContext } from '../../contexts/SnackBarContext';
import { useStorageState } from '../../hooks/useStorageState';

import { CastProxy } from './CastProxy';
import OverlayItems from './UI/OverlayItems';
import StartOverButton from './UI/StartOverButton';
import CarouselButton from './UI/CarouselButton';
import CaptionsButton from './UI/CaptionsButton';
import SettingsButton from './UI/SettingsButton';
import FullscreenButton from './UI/FullscreenButton';
import PresentationTimeKpn from './UI/PresentationTimeKpn';
import LiveIndicatorButton from './UI/LiveIndicatorButton';
import SeekBarMarkers from './UI/SeekBarMarkers';
import Tooltip from './UI/Tooltip';

import analytics from '../../api/services/analytics';
import { streamType } from '../../utils/program';
import { isEmptyObject, hasCaptions } from '../../utils/player';
import { isDesktopSafariBrowser, isFirefoxBrowser, isSafariBrowser } from '../../utils/browser';
import createPlayerConfig from './utils/createPlayerConfig';

import { ContentItemDetailType } from '../../types/ContentItemType';
import { ItvVideoUrlSourceType } from '../../types/Itv/ItvVideoUrlType';
import { ShakaError, ShakaRequestType, ShakeResponseType } from '../../types/ShakaType';
import { StreamQualityOptionType } from '../../types/HaloType';

import MenuPopupItem from '../MenuPopup/MenuPopupItem';
import CheckIcon from '../Icons/Check';

declare const shaka: any;

type PlayerType = {
  item: ContentItemDetailType;
  videoURL: ItvVideoUrlSourceType;
  secureCDM: boolean;
  seekLimitRange: { start: number; end: number };
  onLiveSeekableRegionChange: (withinSeekableRange: boolean, withinLiveBuffer: boolean, time: number) => boolean;
  playerHooks: (hooks: any, samePlayerInstance: boolean) => any;
  startOverHandler: (event: Event, hooks: any) => void;
  carouselState?: boolean;
  carouselHandler?: () => void;
  liveIndicatorHandler?: () => void;
  escapeButtonHandler: () => void;
  handleError: (error: ShakaError) => void;
  avsid: string;
  pin: string;
  poster: string;
  deviceId: string;
  startTime: number;
  isTrailer?: boolean;
  isProgramRecording?: boolean;
};

const Player: FC<PlayerType> = (props) => {
  const [showCaptions, setShowCaptions] = useStorageState('showCaptions', false);
  const [player, setPlayer] = useState({} as any);
  const [overlayFactory, setOverlayFactory] = useState({} as any);
  const [startOverButtonFactory, setStartOverButtonFactory] = useState({} as any);
  const [carouselButtonFactory, setCarouselButtonFactory] = useState({} as any);
  const [settingsButtonFactory, setSettingsButtonFactory] = useState({} as any);
  const [captionsButtonFactory, setCaptionsButtonFactory] = useState({} as any);
  const [seekBarMarkersFactory, setSeekBarMarkersFactory] = useState({} as any);
  const [hooks, setHooks] = useState({} as any);
  const _seekLimitRange = useRef(props.seekLimitRange);
  const _paused = useRef(false);
  const [loading, setLoading] = useState(false);
  const TIMESHIFT_BUFFER_DEPTH = 4 * 60; // 5 - 1 minutes

  const { receiverAppId } = useCastContext();
  const { showTempMessage } = useSnackBarContext();
  const { translate } = useHaloContext();
  const { profileLevel, setProfileLevel } = useUserContext();

  const videoElement = React.useRef<HTMLVideoElement>();
  const videoContainer = React.useRef();

  const multipliers = {} as any;
  const MULTIPLIER_DELAY = 1500;

  function onKeyboardEvent(event: KeyboardEvent) {
    const key = event.key.toLowerCase();
    const multiplierTimeoutHandler = () => {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = null;
      hooks.controls.setControlsActive(false);
    };

    if (!multipliers[key]) {
      hooks.controls.setControlsActive(true);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), 1];
    } else {
      clearTimeout(multipliers[key][0]);
      multipliers[key] = [setTimeout(multiplierTimeoutHandler, MULTIPLIER_DELAY), multipliers[key][1] + 1];
    }
    if (hooks.controls) {
      const media = hooks.controls.getVideo();
      switch (key) {
        case ' ':
          media.paused ? media.play() : media.pause();
          break;
        case 'arrowleft':
          media.currentTime -= 5 * multipliers[key][1];
          break;
        case 'arrowright':
          media.currentTime += 5 * multipliers[key][1];
          break;
        case 'arrowup':
          media.volume = Math.min(1, media.volume + 0.1);
          break;
        case 'arrowdown':
          media.volume = Math.max(0, media.volume - 0.1);
          break;
        case 'escape':
          if ('escapeButtonHandler' in props) {
            props.escapeButtonHandler();
          }
          break;
        case 'f':
          hooks.controls.toggleFullScreen();
          break;
        default:
          break;
      }
    }
  }

  function onErrorEvent(event: any) {
    // Extract the shaka.util.Error object from the event.
    if ('detail' in event) {
      onError(event.detail);
    }
  }

  function onError(error: ShakaError) {
    console.error('Error code', error.code, 'object', error);
    switch (error.code) {
      case 6007: // LICENSE_REQUEST_FAILED
      case 1001: // BAD_HTTP_STATUS
      case 1002: // HTTP_ERROR
        if (hooks && hooks.refetchMedia) {
          hooks.refetchMedia(error);
        } else {
          props.handleError(error);
        }
        break;
      case 4001: // DASH_INVALID_XML
      case 4002: // DASH_NO_SEGMENT_INFO
      case 4003: // DASH_EMPTY_ADAPTATION_SET
      case 4004: // DASH_EMPTY_PERIOD
        if (hooks && hooks.player) {
          setTimeout(hooks.player.retryStreaming, 2000);
        } else {
          props.handleError(error);
        }
        break;
      default:
        props.handleError(error);
    }
  }

  function onAutoplayError(error: Error) {
    if (isDesktopSafariBrowser()) {
      showTempMessage({
        message: translate('player.autoplay_error_message'),
        link: { url: translate('player.autoplay_error_link_url'), text: translate('player.autoplay_error_link_text') },
        type: 'WARNING',
        timeout: 10000,
      });
    } else {
      console.warn(`autoplay rejection: ${error}`);
    }
  }

  function seekableRangeCheck() {
    if (hooks && hooks.player && hooks.player.getLoadMode() !== shaka.Player.LoadMode.SRC_EQUALS) {
      const trueSeekRange = hooks.player.seekRange(true);
      if (trueSeekRange && props.onLiveSeekableRegionChange) {
        const val = videoElement.current.currentTime;
        // ignore play event when live and currentTime = 0
        if (val > 0) {
          const withinSeekableRange = val >= trueSeekRange.start;
          const withinLiveBuffer = val >= trueSeekRange.end - TIMESHIFT_BUFFER_DEPTH;
          // case for when the user paused
          if (props.onLiveSeekableRegionChange && (!withinSeekableRange || !withinLiveBuffer)) {
            props.onLiveSeekableRegionChange(withinSeekableRange, withinLiveBuffer, val);
          }
        }
      }
    }
  }

  function loadVideo() {
    const videoUrl = props.videoURL;
    const servers = {} as any;
    const advanced = {} as any;
    const playerPromise = [];
    if (!loading && player && !isEmptyObject(player) && videoUrl && videoUrl.sources) {
      setLoading(true);
      playerPromise.push(player.unload());
      const { contentProtection } = videoUrl.sources;
      player.getNetworkingEngine().clearAllRequestFilters();
      player.getNetworkingEngine().clearAllResponseFilters();
      player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
        // eslint-disable-next-line eqeqeq
        if (type === shaka.net.NetworkingEngine.RequestType.MANIFEST) {
          seekableRangeCheck();
        }
      });
      if (contentProtection && 'fairplay' in contentProtection) {
        player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
          // eslint-disable-next-line eqeqeq
          if (type != shaka.net.NetworkingEngine.RequestType.LICENSE) {
            return;
          }
          request.allowCrossSiteCredentials = false;
          request.headers['Content-Type'] = 'application/octet-stream';
          const decoded = new TextDecoder('utf-8').decode(request.body).substring(4);
          // backend expects unwrapped license requests
          request.body = shaka.util.Uint8ArrayUtils.fromBase64(decoded);
        });
        playerPromise.push(
          fetch(`${contentProtection.fairplay.certificateURL}`, {
            mode: 'cors', // no-cors, *cors, same-origin
            cache: 'no-cache', // *default, no-cache, reload, force-cache, only-if-cached
            credentials: 'omit', // include, *same-origin, omit
            headers: {
              'Content-Type': 'application/octet-stream',
              Referer: 'https://interactievetv.nl',
            },
          })
            .then((res) => res.arrayBuffer())
            .then((buffer) => {
              servers['com.apple.fps.1_0'] = contentProtection.fairplay.licenseAcquisitionURL;
              advanced['com.apple.fps.1_0'] = {
                serverCertificate: new Uint8Array(buffer),
              };
            })
        );
      }
      if (contentProtection && 'widevine' in contentProtection) {
        playerPromise.push(
          new Promise((resolve) => {
            if (props.secureCDM) {
              advanced['com.widevine.alpha'] = {
                videoRobustness: 'HW_SECURE_ALL',
                // 'persistentStateRequired': true,
              };
            }
            servers['com.widevine.alpha'] = contentProtection.widevine.licenseAcquisitionURL;
            resolve(null);
          })
        );
      }

      if (contentProtection && 'playready' in contentProtection) {
        // TODO: Setting a license aquisitionurl for playready though
        // servers['com.microsoft.playready'] before playback,
        // makes CLEAR content fail on edge chromium (07-2022)
        // so for playready license url is set last second with a request filter
        player.getNetworkingEngine().registerResponseFilter((type: number, response: ShakeResponseType) => {
          if (type === shaka.net.NetworkingEngine.RequestType.MANIFEST) {
            if (shaka.util.StringUtils.fromUTF8(response.data).indexOf('urn:mpeg:dash:mp4protection:2011') > -1) {
              servers['com.microsoft.playready'] = contentProtection.playready.licenseAcquisitionURL;
              player.configure(createPlayerConfig({ servers, advanced }));
            }
          }
        });
        player.getNetworkingEngine().registerRequestFilter((type: number, request: ShakaRequestType) => {
          // eslint-disable-next-line eqeqeq
          if (type != shaka.net.NetworkingEngine.RequestType.LICENSE) {
          } else {
            request.uris = [contentProtection.playready.licenseAcquisitionURL];
            return request;
          }
        });
        playerPromise.push(
          new Promise((resolve) => {
            resolve(null);
          })
        );
      }
      if (playerPromise && player && !isEmptyObject(player)) {
        Promise.all(playerPromise).then(() => {
          const playerConfig = createPlayerConfig({ servers, advanced });
          player.configure(playerConfig);
          // update cast contentUrl for reloads
          // also replace /PROGRAM to /LIVETV to force chromecast-ng to cast at live edge
          if ('liveIndicatorHandler' in props && props.startTime === null) {
            hooks.controls.getCastProxy().contentUrl = props.avsid.replace('/PROGRAM', '/LIVETV');
          }
          // use hooks.controls.getPlayer to run .load through castProxy, to be able to block the load
          hooks.controls
            .getPlayer()
            .load(videoUrl.sources.src, props.startTime)
            .then(() => {
              if (player.getLoadMode() === shaka.Player.LoadMode.SRC_EQUALS) {
                const date = (videoElement.current as any).getStartDate();
                if (date && isNaN(date.getTime())) {
                  console.warn('EXT-X-PROGRAM-DATETIME required to get presentation start time as Date!');
                  console.warn('expecting fallback in getStartDateFallback()');
                  // Fallback is expected in videoElement.current.getStartDateFallback():Date
                }
              }
              if (_paused.current) {
                setLoading(false);
                console.warn(`Autoplay Rejection player was paused`);
              } else {
                videoElement.current
                  .play()
                  .catch((error: Error) => {
                    onAutoplayError(error);
                  })
                  .finally(() => {
                    setLoading(false);
                  });
              }
              videoElement.current.muted = localStorage.getItem('pctv.shaka.muted') === 'true';
              const persistentVolume = localStorage.getItem('pctv.shaka.volume');
              if (persistentVolume) {
                videoElement.current.volume = parseInt(persistentVolume, 10) / 100;
              }
              // videoElement.current.videoWidth = 640;
              // Return hooks object with:
              // - hooks.castProxy
              // - hooks.player

              if ('playerHooks' in props && typeof props.playerHooks === 'function') {
                setHooks(props.playerHooks(hooks, false));
              }
            })
            .catch((error: ShakaError) => {
              setLoading(false);
              // error with loading
              if (error.code !== 7000) onError(error);
              else console.warn(error.toString());
            });
        });
      }
    }
  }

  const profileLevelOptions = (): JSX.Element[] => {
    const haloProfileOptions = translate('player.player_streamQuality_options_web') as StreamQualityOptionType[];
    if (haloProfileOptions && haloProfileOptions.length > 0) {
      haloProfileOptions.sort((a, b) => a.order - b.order);
      const settingsOptions = haloProfileOptions.map((option) => {
        const onClick = () => {
          setProfileLevel(option.value);
          analytics.changeResolution(option.gaTag);
        };
        return (
          <MenuPopupItem onClick={onClick} key={option.order} active={profileLevel === option.value}>
            {option.title['nl-NL']}
            <CheckIcon />
          </MenuPopupItem>
        );
      });
      return settingsOptions;
    }
    return null;
  };

  // if props.videoURL is set/updated, update getStartDateFallback
  useEffect(() => {
    if (props.item && videoElement.current) {
      (videoElement.current as any).getStartDateFallback = () => new Date(props.item.airingStartTime);
    }
  }, [props.videoURL]);

  useEffect(() => {
    const overlayFactory = new OverlayItems.Factory(props);
    setOverlayFactory(overlayFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'overlay',
      overlayFactory
    );

    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'time_and_duration',
      new PresentationTimeKpn.Factory({
        onClick: () => {
          if ('liveIndicatorHandler' in props) {
            props.liveIndicatorHandler();
            if (hooks && hooks.controls) {
              const video = hooks.controls.getVideo();
              if (video && video.paused) {
                video.play();
              }
            }
          }
        },
      })
    );

    const startOverButtonFactory = new StartOverButton.Factory();
    setStartOverButtonFactory(startOverButtonFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'startover',
      startOverButtonFactory
    );

    const seekBarMarkersFactory = new SeekBarMarkers.Factory();
    setSeekBarMarkersFactory(seekBarMarkersFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'seek_bar_markers',
      seekBarMarkersFactory
    );

    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'liveindicator',
      new LiveIndicatorButton.Factory({
        onClick: () => {
          if ('liveIndicatorHandler' in props) {
            props.liveIndicatorHandler();
            if (hooks && hooks.controls) {
              const video = hooks.controls.getVideo();
              if (video && video.paused) {
                video.play();
              }
            }
          }
        },
      })
    );

    const carouselButtonFactory = new CarouselButton.Factory(props.item.contentType === 'PROGRAM');
    setCarouselButtonFactory(carouselButtonFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'carousel',
      carouselButtonFactory
    );

    const handleOnClickCaptionsButton = () => {
      if (hasCaptions(hooks)) {
        const { player } = hooks;
        player.setTextTrackVisibility(!player.isTextTrackVisible());
        setShowCaptions(player.isTextTrackVisible());
        analytics.changeSubtitleSetting(player.isTextTrackVisible());
      }
    };
    const captionsButtonFactory = new CaptionsButton.Factory(handleOnClickCaptionsButton);
    setCaptionsButtonFactory(captionsButtonFactory);
    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'captions',
      captionsButtonFactory
    );

    if (profileLevelOptions()) {
      const settingsButtonFactory = new SettingsButton.Factory(profileLevelOptions());
      setSettingsButtonFactory(settingsButtonFactory);
      shaka.ui.Controls.registerElement(
        /* This name will serve as a reference to the button in the UI configuration object */ 'settings',
        settingsButtonFactory
      );
    }

    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'fullscreen',
      new FullscreenButton.Factory()
    );

    shaka.ui.Controls.registerElement(
      /* This name will serve as a reference to the button in the UI configuration object */ 'seekbar_tooltip',
      new Tooltip.Factory()
    );

    // Important for fairplay, safari support
    shaka.polyfill.installAll();
  }, []);

  // Hook the video.currentTime setter and getter, to prevent unwanted seeks
  // note that this is the only way to do this on the lowest api level -> .currentTime
  // also preventing for instance the safari touch bar seek
  useEffect(() => {
    let ownObjectProto = Object.getPrototypeOf(videoElement.current);
    while (!Object.getOwnPropertyDescriptor(ownObjectProto, 'currentTime')) {
      ownObjectProto = Object.getPrototypeOf(ownObjectProto);
    }
    const ownProperty = Object.getOwnPropertyDescriptor(ownObjectProto, 'currentTime');
    const ownCurrentTimeGet = ownProperty.get.bind(videoElement.current);
    Object.defineProperty(videoElement.current, 'currentTime', {
      configurable: true,
      enumerable: true,
      get: () => ownCurrentTimeGet(),
      set: (val) => {
        if (loading || (hooks && hooks.controls && hooks.controls.getIsLocked())) {
          ownProperty.set.bind(videoElement.current)(val);
          return;
        }
        if (_seekLimitRange.current.end && val > _seekLimitRange.current.end) {
          showTempMessage({ message: translate('player.forward_blocked_message'), type: 'WARNING' });
          ownProperty.set.bind(videoElement.current)(_seekLimitRange.current.end);
        } else if (_seekLimitRange.current.start && val < _seekLimitRange.current.start) {
          ownProperty.set.bind(videoElement.current)(_seekLimitRange.current.start);
          showTempMessage({ message: translate('player.backward_blocked_message'), type: 'WARNING' });
        } else {
          let retval = true;
          if (hooks.player.getLoadMode() !== shaka.Player.LoadMode.SRC_EQUALS) {
            const trueSeekRange = player.seekRange(true);
            if (trueSeekRange && props.onLiveSeekableRegionChange) {
              // onLiveSeekableRegionChange(withinSeekableRange, withinLiveBuffer, time)
              retval = props.onLiveSeekableRegionChange(
                val >= trueSeekRange.start,
                val >= trueSeekRange.end - TIMESHIFT_BUFFER_DEPTH,
                val
              );
            }
          }
          retval && ownProperty.set.bind(videoElement.current)(val);
        }
      },
    });
    return () => {
      Object.defineProperty(videoElement.current, 'currentTime', {
        configurable: true,
        enumerable: true,
        get: ownProperty.get,
        set: ownProperty.set,
      });
    };
  }, [loading === false]);

  useEffect(() => {
    // construct the player
    const player = new shaka.Player(videoElement.current);

    // register error callbacks
    player.addEventListener('error', onErrorEvent);

    player.setTextTrackVisibility(showCaptions);

    // configure the shaka-ui module
    // https://github.com/google/shaka-player/blob/4a7aee1dafcff2697789b326e6d103273d4c58aa/ui/ui.js
    // https://shaka-player-demo.appspot.com/docs/api/ui_controls.js.html
    let controlPanelElements = [
      'overlay',
      'time_and_duration',
      'seekbar_tooltip',
      'startover',
      'mute',
      'volume',
      'spacer',
      'liveindicator',
      'carousel',
      'captions',
      'settings',
      'picture_in_picture',
      'fullscreen',
    ];
    if (isSafariBrowser()) {
      controlPanelElements = controlPanelElements.filter((element) => element !== 'captions');
    }
    if (isFirefoxBrowser()) {
      controlPanelElements = controlPanelElements.filter((element) => element !== 'picture_in_picture');
    }
    if (props.isProgramRecording) {
      controlPanelElements.push('seek_bar_markers');
    }

    const uiConfig = {
      addSeekBar: true,
      addBigPlayButton: true,
      clearBufferOnQualityChange: true,
      showUnbufferedStart: false,
      seekBarColors: {
        base: 'rgba(255, 255, 255, 0.2)',
        buffered: 'var(--hazy-grey)',
        played: 'var(--color-secondary)',
      },
      volumeBarColors: {
        base: 'rgba(255, 255, 255, 0.2)',
        level: 'var(--color-secondary)',
      },
      trackLabelFormat: shaka.ui.TrackLabelFormat.LANGUAGE,
      fadeDelay: 0,
      enableKeyboardPlaybackControls: false, // disable default keyboard implementation
      doubleClickForFullscreen: true,
      enableFullscreenOnRotation: true,
      controlPanelElements,
      // overflowMenuButtons: ['captions', 'cast', 'quality', 'language', 'picture_in_picture', 'loop', 'playback_rate', 'airplay'],
    };

    const castProxy = (hooks.castProxy = new CastProxy({
      video: videoElement.current,
      player,
      receiverAppId,
      contentUrl: props.avsid,
      pin: props.pin,
      deviceId: props.deviceId,
      isTrailer: props.isTrailer,
    }));

    const ui = new shaka.ui.Overlay(player, videoContainer.current, videoElement.current, castProxy);
    ui.configure(uiConfig);
    const controls = (hooks.controls = ui.getControls());
    (window as any).controls = controls;

    // persist volume level between sessions
    // persist muted between sessions
    const volumeChange = () => {
      localStorage.setItem('pctv.shaka.volume', (videoElement.current.volume * 100).toString());
      localStorage.setItem('pctv.shaka.muted', videoElement.current.muted.toString());
    };
    controls.getVideo().addEventListener('volumechange', volumeChange);
    const playChange = () => {
      _paused.current = false;
      seekableRangeCheck();
    };

    controls.getVideo().addEventListener('play', playChange);

    const pausedChange = () => {
      _paused.current = true;
    };

    controls.getVideo().addEventListener('pause', pausedChange);

    // user enabled PiP
    videoElement.current.addEventListener('enterpictureinpicture', () => analytics.changePipMode('Enabled'));
    videoElement.current.addEventListener('leavepictureinpicture', () => analytics.changePipMode('Disabled'));

    // failover mode, retryStreaming() when browser comes back online
    const retryStreaming = () => {
      player.retryStreaming();
    };
    window.addEventListener('online', retryStreaming);

    const handleLargeGaps = (event: any) => {
      _seekLimitRange.current.end += event.gapSize + 0.1;
    };
    player.addEventListener('largegap', handleLargeGaps);

    // player constructed, call setPlayer, to start loadVideo hook
    setPlayer(((window as any)._player = hooks.player = player));

    return () => {
      if (videoElement.current.error) {
        console.error('The video was cleaned up, but there was a video.mediaError: ', videoElement.current.error);
      }

      // remove all eventlisteners registered in this hook
      player.removeEventListener('error', onErrorEvent);
      player.removeEventListener('largegap', handleLargeGaps);
      window.removeEventListener('online', retryStreaming);
      controls.getVideo().removeEventListener('volumechange', volumeChange);
      controls.getVideo().removeEventListener('play', playChange);
      controls.getVideo().removeEventListener('pause', pausedChange);
      videoElement.current.removeEventListener('enterpictureinpicture', () => analytics.changePipMode('Enabled'));
      videoElement.current.removeEventListener('leavepictureinpicture', () => analytics.changePipMode('Disabled'));

      // end pip picture in picture session
      if ((document as any).pictureInPictureElement) {
        (document as any).exitPictureInPicture();
      }

      // destroy player and controls (ui)
      controls.destroy();
      analytics.stopVideo(streamType(props.item));
      return player.destroy();
    };
  }, []);
  useEffect(loadVideo, [player, props.videoURL]);
  useEffect(() => {
    _seekLimitRange.current = props.seekLimitRange;
  }, [props.seekLimitRange]);

  useEffect(() => {
    if (overlayFactory && !isEmptyObject(overlayFactory)) {
      overlayFactory.update(props.children);
    }
  }, [overlayFactory, props.children]);

  useEffect(() => {
    if (captionsButtonFactory && !isEmptyObject(captionsButtonFactory)) {
      captionsButtonFactory.update({
        isActive: showCaptions,
        isEnabled: hasCaptions(hooks),
      });
    }
  }, [captionsButtonFactory, showCaptions, hooks, loading]);

  useEffect(() => {
    if (startOverButtonFactory && !isEmptyObject(startOverButtonFactory)) {
      startOverButtonFactory.update({
        onClick:
          props.startOverHandler &&
          ((event: Event) => {
            props.startOverHandler(event, hooks);
          }),
      });
    }
  }, [startOverButtonFactory, props.startOverHandler]);

  useEffect(() => {
    if (seekBarMarkersFactory && !isEmptyObject(seekBarMarkersFactory) && loading) {
      const duration = props.item.contentType === 'PROGRAM' ? props.item.duration : props.item.liveProgramDuration;
      seekBarMarkersFactory.update({
        duration,
      });
    }
  }, [seekBarMarkersFactory, loading]);

  useEffect(() => {
    if (carouselButtonFactory && !isEmptyObject(carouselButtonFactory) && props.carouselHandler) {
      carouselButtonFactory.update({
        onClick:
          props.carouselHandler &&
          (() => {
            props.carouselHandler();
          }),
        isActive: props.carouselState,
      });
    }
  }, [carouselButtonFactory, props.carouselHandler]);

  useEffect(() => {
    if (settingsButtonFactory && !isEmptyObject(settingsButtonFactory)) {
      settingsButtonFactory.update({
        options: profileLevelOptions(),
      });
    }
  }, [settingsButtonFactory, profileLevel, document.fullscreenElement]);

  return (
    <div
      data-t="player-container"
      onKeyUp={onKeyboardEvent}
      tabIndex={-1}
      className="shakaplayer--video-container"
      ref={videoContainer}
    >
      <video
        data-t="player-element"
        className="shakaplayer--video-element"
        poster={props.poster}
        autoPlay={!_paused.current}
        ref={videoElement}
        onSeeking={(event: React.SyntheticEvent<HTMLVideoElement, Event>) => {
          // seek fix for touch-bar and non-inline videoElement
          if (hooks.player.getLoadMode() === shaka.Player.LoadMode.SRC_EQUALS) {
            const video = event.target as HTMLVideoElement;
            const val = video.currentTime;
            if (_seekLimitRange.current.end && val > _seekLimitRange.current.end) {
              video.currentTime = _seekLimitRange.current.end;
              showTempMessage({ message: translate('player.forward_blocked_message'), type: 'WARNING' });
            } else if (_seekLimitRange.current.start && val < _seekLimitRange.current.start) {
              video.currentTime = _seekLimitRange.current.start;
              showTempMessage({ message: translate('player.backward_blocked_message'), type: 'WARNING' });
            }
          }
        }}
      />
    </div>
  );
};
export default Player;