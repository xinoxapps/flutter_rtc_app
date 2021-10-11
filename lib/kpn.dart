import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class KPNStreaming {
  Future<StreamManifest> fetchManifest([String channelName = 'SBS6']) async {
    try {
      var asset = await _KPNStreamingMobile().fetchChannel(channelName);
      StreamManifest result = await _KPNStreamingMobile().fetchManifest(
        KPNStreamArguments("mikevdlans", "1234aA1234&=", "mikevdlans", 1234,
            assetId: asset['assetId'] ?? 0, contentId: asset['contentId'] ?? 0),
      );
      print("success");
      return result;
    } catch (exc, trace) {
      print("$trace");
      throw exc;
    }
  }
}

class _KPNStreamingMobile {
  final String HOST =
      'https://varnish-dev.apps.avs-kpn-ztv-dev.interactievetv.nl/101/1.2.0/R/nld/';

  Future<Map<String, int>> fetchChannel(String channelName) async {
    channelName = channelName.toLowerCase();
    var url = HOST +
        "pctv/tenant_sme/TRAY/LIVECHANNELS?orderBy=orderId&sortOrder=asc";
    Map<String, String> headers = {'Content-Type': 'application/json'};
    var response = await http.get(Uri.parse(url), headers: headers);
    final jsonBody = jsonDecode(response.body);
    if (jsonBody["resultCode"] == "KO") {
      // 403-10146_64
      print("error1");
      throw StreamException(
          code: jsonBody['errorDescription'], message: jsonBody['message']);
    }

    var resultOfContainers = <Map<dynamic, dynamic>>[];
    var containers = jsonBody["resultObj"]["containers"];

    containers.forEach((container) {
      String containerName =
          ((container['metadata']['channelName'] ?? "") as String)
              .toLowerCase();
      if (channelName == containerName) {
        resultOfContainers.add(container);
      }
    });

    print(resultOfContainers);

    if (resultOfContainers.isEmpty) {
      print("error2");
      throw StreamException(code: 'not-found', message: 'channel-not-found');
    }

    var wvAssets = resultOfContainers.first['assets']
        .where((element) =>
            ((element['videoType'] ?? "") as String) == 'SD_DASH_WV')
        .toList();

    if (wvAssets.isEmpty) {
      print("error3");
      throw StreamException(code: 'not-found', message: 'sbs6-asset-not-found');
    }

    return <String, int>{
      'contentId':
          ((resultOfContainers.first['metadata']['channelId'] ?? 10) as num)
              .toInt(),
      'assetId': ((wvAssets.first['assetId'] ?? 10) as num).toInt()
    };
  }

  Future<StreamManifest> fetchManifest(KPNStreamArguments arguments,
      {bool canRetry = true}) async {
    var sessionId = "${arguments.username}:${arguments.password}".hashCode;
    var sessionResponse = await _userSession(arguments);
    print("0got new session: ${sessionResponse.statusCode}");
    String? xsrfToken = sessionResponse.headers["x-xsrf-token"];
    Map<String, String> cookies = _splitCookies(sessionResponse);
    KPNSession localSession =
        KPNSession(xsrfToken, cookies, DateTime.now(), sessionId);

    var metaDataResponse;
    try {
      metaDataResponse = await _fetchMetadata(localSession, arguments);
    } on StreamException catch (exc) {
      print("1 $exc");
      throw exc;
    } catch (exc) {
      print("2 $exc");
      throw StreamException(code: '500', message: 'Failed to fetchMetadata');
    }

    print("manifest: " + metaDataResponse.body);
    final jsonBody = jsonDecode(metaDataResponse.body);
    if (jsonBody["resultCode"] == "KO") {
      // 403-10146_64
      if (jsonBody['errorDescription'] == '403-10100') {
        if (canRetry) {
          return await fetchManifest(arguments, canRetry: false);
        }
      }
      print("4 ${jsonBody['errorDescription']}");
      throw StreamException(
          code: jsonBody['errorDescription'], message: jsonBody['message']);
    }

    StreamMetaData metadata = StreamMetaData.fromJson(arguments.type, jsonBody);

    // store certificate in session or reuse it from the session
    if (metadata.certificateURL == null &&
        metadata.licenseAcquisitionURL == null) {
      print("get certificate from session");
      metadata = metadata.copyWith(
          certificateURL: localSession.certificateURL,
          licenseAcquisitionURL: localSession.licenseAcquisitionURL);
    } else {
      print("store certificate in session");
      localSession = localSession.copyWith(
          certificateURL: metadata.certificateURL,
          licenseAcquisitionURL: metadata.licenseAcquisitionURL);
    }
    return _validateSessionManifest(localSession, arguments, metadata);
  }

  Future<StreamManifest> _validateSessionManifest(KPNSession session,
      KPNStreamArguments arguments, StreamMetaData metadata) async {
    final maxRetries = 3;
    var retries = maxRetries;
    var responseManifest1 = await _fetchManifest(session, metadata);
    print("_analyzeManifest ${maxRetries - retries}");
    StreamManifest manifest1 =
        await _analyzeManifest(arguments.type, responseManifest1, metadata);

    // it seems that the playlist becomes visible after ±3 seconds when creating a new session.
    return manifest1;
  }

  Future<http.Response> _userSession(KPNStreamArguments arguments) {
    String url =
        '$HOST${arguments.type.deviceTypeParameter()}/tenant_sme/USER/SESSIONS';

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'AVSSite': 'http://www.ztv.nl'
    };

    String body = """
    {
	"credentialsStdAuth": {
    "platformType": "OTT",
		"deviceRegistrationData": {
			"deviceId": "${arguments.deviceId}",
			"accountDeviceIdType": "DEVICEID",
			"deviceType": "OTTSTB"
		}
	}
}
    """;

    return http.post(Uri.parse(url), headers: headers, body: body);
  }

  Map<String, String> _splitCookies(http.Response response) {
    String? cookieHeader;
    response.headers.forEach((key, value) {
      if (key.toLowerCase() == 'set-cookie') {
        cookieHeader = value;
      }
    });
    List<String> lines = cookieHeader?.split(",") ?? [];
    /*
    if (kIsWeb) {
      lines = web.document.cookie?.split(",") ?? [];
    }
    */
    Map<String, String> cookies = new Map<String, String>();
    for (String line in lines) {
      String firstPart = line.split(';').first;
      // Sometimes dates end up here after splitting on the comma
      if (!firstPart.contains('=')) {
        continue;
      }

      List<String> cookieParts = firstPart.split('=');
      // Should be a key/value pair
      if (cookieParts.length != 2) {
        continue;
      }
      cookies[cookieParts.first] = cookieParts.last;
    }
    return cookies;
  }

  Future<http.Response> _fetchMetadata(
      KPNSession session, KPNStreamArguments arguments) async {
    // unix timestamp
    var contentType = "LIVE";
    var assetId = arguments.assetId;
    var contentId = arguments.contentId;

    String url =
        '$HOST${arguments.type.deviceTypeParameter()}/tenant_sme/CONTENT/VIDEOURL/$contentType/$contentId/$assetId?deviceId=${arguments.deviceId}&profile=${arguments.type.profileTypeParameter()}';

    Map<String, String> headers = {
      'pcpin': '${arguments.pin}',
    };
    if (session.xsrfToken != null) {
      headers['X-Xsrf-Token'] = session.xsrfToken!;
    }
    print("session.cookieAsString: ${session.cookieAsString}");
    if (kIsWeb) {
      //web.document.cookie = session.cookieAsString;
    } else {
      headers['cookie'] = session.cookieAsString;
    }
    return http.get(Uri.parse(url), headers: headers);
  }

  Future<http.Response> _fetchSubscription(
      KPNSession session, KPNStreamArguments arguments) {
    // unix timestamp

    String url =
        '$HOST${arguments.type.deviceTypeParameter()}/tenant_sme/TRAY/LIVECHANNELS?from=0&to=1000&dfilter_channels=subscription';
    Map<String, String> headers = {'pcpin': '${arguments.pin}'};
    if (session.xsrfToken != null) {
      headers['X-Xsrf-Token'] = session.xsrfToken!;
    }
    if (kIsWeb) {
      //   web.document.cookie = session.cookieAsString;
    } else {
      headers['cookie'] = session.cookieAsString;
    }
    return http.get(Uri.parse(url), headers: headers);
  }

  Future<http.Response> _fetchManifest(
      KPNSession session, StreamMetaData metadata) {
    Map<String, String> headers = {'cookie': session.cookieAsString};
    if (session.xsrfToken != null) {
      headers['X-Xsrf-Token'] = session.xsrfToken!;
    }
    final fixedSourceURL = Uri.parse(metadata.srcURL
        .toString()
        .replaceAll("max_bitrate=10000000", "max_bitrate=1200000"));
    return http.get(fixedSourceURL, headers: headers);
  }

  Future<StreamManifest> _analyzeManifest(ManifestStreamType type,
      http.Response response, StreamMetaData metadata) async {
    print("Playlist body was okay");
    return Future.value(StreamManifest(type, response.body, metadata));
  }
}

class KPNStreamArguments {
  final String username;
  final String password;
  final String deviceId;
  final int pin;
  final int contentId;
  final int assetId;

  KPNStreamArguments(this.username, this.password, this.deviceId, this.pin,
      {required this.contentId, required this.assetId});

  ManifestStreamType get type {
    if (kIsWeb) {
      return ManifestStreamType.widevine;
    } else if (Platform.isAndroid) {
      return ManifestStreamType.widevine;
    } else if (Platform.isIOS) {
      return ManifestStreamType.fairplay;
    } else {
      return ManifestStreamType.widevine;
    }
  }
}

extension HTTPArguments on ManifestStreamType {
  String profileTypeParameter() {
    switch (this) {
      case ManifestStreamType.widevine:
        return "G04";
      case ManifestStreamType.fairplay:
        return "A04";
      default:
        throw Exception("KPNStreamType has no parameter set");
    }
  }

  String deviceTypeParameter() {
    switch (this) {
      case ManifestStreamType.widevine:
        return "android";
      case ManifestStreamType.fairplay:
        return "android";
      default:
        throw Exception("KPNStreamType has no parameter set");
    }
  }

  String get protocol {
    switch (this) {
      case ManifestStreamType.widevine:
        return "widevine";
      case ManifestStreamType.fairplay:
        return "fairplay";
      default:
        throw Exception("KPNStreamType has no parameter set");
    }
  }
}

class KPNSession {
  final String? xsrfToken;
  final Map<String, String> cookies;
  final DateTime created;
  final int sessionId;

  final Uri? certificateURL;
  final Uri? licenseAcquisitionURL;

  const KPNSession(this.xsrfToken, this.cookies, this.created, this.sessionId,
      {this.certificateURL, this.licenseAcquisitionURL});

  KPNSession copyWith({certificateURL, licenseAcquisitionURL}) {
    return KPNSession(xsrfToken, cookies, created, sessionId,
        certificateURL: certificateURL ?? this.certificateURL,
        licenseAcquisitionURL:
            licenseAcquisitionURL ?? this.licenseAcquisitionURL);
  }

  String get cookieAsString {
    List<String> list = [];
    cookies.forEach((key, value) {
      list.add(key + '=' + Uri.encodeComponent(value));
    });
    return list.join(';');
  }

  int get difference => DateTime.now().difference(created).inMinutes;
  bool get expired => difference > 60;
}

class KPNPlayable implements Playable {
  final ManifestStreamType protection;
  final String? playlist;
  final Uri src;
  final Uri? certificateURL;
  final Uri? licenseAcquisitionURL;
  final String? contentId;

  const KPNPlayable(
      {this.protection = ManifestStreamType.widevine,
      this.playlist,
      required this.src,
      this.certificateURL,
      this.licenseAcquisitionURL,
      this.contentId});

  factory KPNPlayable.fromManifest(
      StreamManifest manifest, StreamMetaData metadata) {
    return KPNPlayable(
        protection: manifest.type,
        playlist: manifest.content,
        src: metadata.srcURL,
        certificateURL: metadata.certificateURL,
        licenseAcquisitionURL: metadata.licenseAcquisitionURL,
        contentId: metadata.contentId);
  }

  @override
  Map<String, String?> toMap() {
    return {
      "type": type.toString().split('.').last,
      "protection": protection.toString().split('.').last,
      "playlist": playlist,
      "src": src.toString(),
      "certificateURL":
          certificateURL == null ? null : certificateURL.toString(),
      "licenseAcquisitionURL": licenseAcquisitionURL == null
          ? null
          : licenseAcquisitionURL.toString(),
      "contentId": contentId,
    };
  }

  @override
  PlayableType get type => PlayableType.kpn;
}

class StreamException implements Exception {
  StreamException({
    required this.code,
    this.message,
    this.details,
    this.stacktrace,
  }) : assert(code != null);

  int get statusCode =>
      int.tryParse(code.indexOf("-") != -1 ? code.split("-")[0] : code) ?? 0;

  /// An error code.
  final String code;

  /// A human-readable error message, possibly null.
  final String? message;

  /// Error details, possibly null.
  final dynamic details;

  /// Native stacktrace for the error, possibly null.
  /// The stacktrace info on dart platform can be found within the try-catch block for example:
  /// try {
  ///   ...
  /// } catch (e, stacktrace) {
  ///   print(stacktrace);
  /// }
  final dynamic stacktrace;

  @override
  String toString() =>
      'StreamException($code, $message, $details, $stacktrace)';
}

enum PlayableType { kpn, netflix, amazonPrime }

enum ManifestStreamType { widevine, fairplay }

abstract class Playable {
  final PlayableType type;

  Playable(this.type);

  Map<String, dynamic> toMap();
}

class StreamManifest {
  final ManifestStreamType type;
  final String content;
  final StreamMetaData metadata;

  StreamManifest(this.type, this.content, this.metadata);
}

enum StreamMetaMime {
  mp4,
  m4v,
  m4a,
  webm,
  weba,
  mkv,
  ts,
  ogv,
  ogg,
  mpg,
  mpeg,
  m3u8,
  mp3,
  aac,
  flac,
  wav
}

extension StreamMetaMimeExt on StreamMetaMime {
  String? get name {
    switch (this) {
      case StreamMetaMime.m4a:
      case StreamMetaMime.m4v:
      case StreamMetaMime.mp4:
        return 'video/mp4';
      case StreamMetaMime.m3u8:
        return 'application/x-mpegurl';
      default:
        return null;
    }
  }
}

class StreamMetaData {
  final ManifestStreamType type;
  final Uri srcURL;
  final Uri? certificateURL;
  final Uri? licenseAcquisitionURL; // Only set for Fairplay, not Widevine
  final String? contentId; // O
  final StreamMetaMime mimeType;
  final Uri? imageURL;

  StreamMetaData(
      {this.type = ManifestStreamType.widevine,
      required this.srcURL,
      this.certificateURL,
      this.licenseAcquisitionURL,
      this.mimeType = StreamMetaMime.mp4,
      this.imageURL,
      required this.contentId});

  StreamMetaData copyWith(
      {String? imageURL,
      Uri? certificateURL,
      Uri? licenseAcquisitionURL,
      StreamMetaMime? mimeType}) {
    return StreamMetaData(
        type: type,
        srcURL: srcURL,
        certificateURL: certificateURL ?? this.certificateURL,
        licenseAcquisitionURL:
            licenseAcquisitionURL ?? this.licenseAcquisitionURL,
        contentId: contentId,
        mimeType: mimeType ?? this.mimeType,
        imageURL: imageURL != null ? Uri.parse(imageURL) : null);
  }

  StreamMetaData withImage(String url) {
    return StreamMetaData(
        type: type,
        srcURL: srcURL,
        certificateURL: certificateURL,
        licenseAcquisitionURL: licenseAcquisitionURL,
        contentId: contentId,
        mimeType: mimeType,
        imageURL: url != null ? Uri.parse(url) : null);
  }

  factory StreamMetaData.fromJson(
      ManifestStreamType type, Map<String, dynamic> jsonBody) {
    var resultObj = jsonBody["resultObj"];
    var sources = resultObj["src"]["sources"];
    var srcURL = Uri.parse(Uri.parse(sources["src"])
        .toString()
        .replaceAll("max_bitrate=10000000", "max_bitrate=1200000"));

    print("StreamMetaData sources: ${jsonEncode(sources)}");
    var certificateURL;
    var licenseAcquisitionURL;
    var contentId;
    var mimeType = StreamMetaMime.mp4;
    if (sources["contentProtection"] != null) {
      mimeType = StreamMetaMime.m3u8;
      var contentProtection = sources["contentProtection"];
      if (type == ManifestStreamType.fairplay) {
        final fairPlay = contentProtection["fairplay"];
        certificateURL = Uri.parse(fairPlay["certificateURL"]);
        licenseAcquisitionURL = Uri.parse(fairPlay["licenseAcquisitionURL"]);
        contentId = contentProtection["contentId"];
      } else {
        final widevine = contentProtection["widevine"];
        licenseAcquisitionURL = Uri.parse(widevine["licenseAcquisitionURL"]);
      }
    }
    if (sources["mimeType"] != null) {
      mimeType = StreamMetaMime.values.firstWhere(
          (element) =>
              element.toString().toLowerCase().contains(sources["mimeType"]),
          orElse: () => StreamMetaMime.mp4);
    }

    return StreamMetaData(
        type: type,
        srcURL: srcURL,
        mimeType: mimeType,
        certificateURL: certificateURL,
        licenseAcquisitionURL: licenseAcquisitionURL,
        contentId: contentId?.toString());
  }
  String toString() {
    return '{type: $type srcURL: $srcURL certificateURL: $certificateURL licenseAcquisitionURL: $licenseAcquisitionURL contentId: $contentId}';
  }
}
