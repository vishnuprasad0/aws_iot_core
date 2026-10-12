import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/credentials.dart';
import '../domain/url_signer.dart';

/// Builds SigV4 query-signed WebSocket URLs for AWS IoT Core.
///
/// The session token is not part of the signed request; it is appended
/// after `X-Amz-Signature`, which is the form AWS IoT expects for temporary
/// credentials.
class AwsIotUrlSigner implements UrlSigner {
  /// Creates a signer for the AWS IoT data [endpoint] in [region].
  ///
  /// [endpoint] is the host only, for example
  /// `xxxxxxxx-ats.iot.us-east-1.amazonaws.com`. [expires] adds
  /// `X-Amz-Expires`; AWS IoT does not require it, so it is omitted by
  /// default.
  const AwsIotUrlSigner({
    required this.endpoint,
    required this.region,
    this.path = '/mqtt',
    this.service = 'iotdevicegateway',
    this.expires,
  });

  /// AWS IoT data endpoint host.
  final String endpoint;

  /// AWS region of the endpoint.
  final String region;

  /// WebSocket path; AWS IoT uses `/mqtt`.
  final String path;

  /// Signing service name; AWS IoT uses `iotdevicegateway`.
  final String service;

  /// Optional validity period added as `X-Amz-Expires`.
  final Duration? expires;

  static const _algorithm = 'AWS4-HMAC-SHA256';

  @override
  Uri sign(AwsIotCredentials credentials, DateTime time) {
    final amzDate = _amzDate(time.toUtc());
    final dateStamp = amzDate.substring(0, 8);
    final host = endpoint.toLowerCase();
    final scope = '$dateStamp/$region/$service/aws4_request';
    final validity = expires;

    final params = <String, String>{
      'X-Amz-Algorithm': _algorithm,
      'X-Amz-Credential': '${credentials.accessKeyId}/$scope',
      'X-Amz-Date': amzDate,
      if (validity != null) 'X-Amz-Expires': '${validity.inSeconds}',
      'X-Amz-SignedHeaders': 'host',
    };
    final canonicalQuery = canonicalQueryString(params);

    final canonicalRequest = [
      'GET',
      path,
      canonicalQuery,
      'host:$host\n',
      'host',
      sha256.convert(const <int>[]).toString(),
    ].join('\n');

    final stringToSign = [
      _algorithm,
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _signingKey(
      credentials.secretAccessKey,
      dateStamp,
      region,
      service,
    );
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final url = StringBuffer('wss://$host$path?$canonicalQuery')
      ..write('&X-Amz-Signature=$signature');
    final token = credentials.sessionToken;
    if (token != null && token.isNotEmpty) {
      url.write('&X-Amz-Security-Token=${uriEncode(token)}');
    }
    return Uri.parse(url.toString());
  }

  static final Set<int> _unreserved = {
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
        .codeUnits,
  };

  /// SigV4 canonical query string: keys sorted, keys and values encoded.
  static String canonicalQueryString(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys
        .map((k) => '${uriEncode(k)}=${uriEncode(params[k]!)}')
        .join('&');
  }

  /// RFC 3986 percent-encoding as SigV4 requires: only unreserved characters
  /// are left as they are.
  static String uriEncode(String value) {
    final out = StringBuffer();
    for (final byte in utf8.encode(value)) {
      if (_unreserved.contains(byte)) {
        out.writeCharCode(byte);
      } else {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  static String _amzDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }

  static List<int> _signingKey(
    String secret,
    String dateStamp,
    String region,
    String service,
  ) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secret'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, service);
    return hmac(kService, 'aws4_request');
  }
}
