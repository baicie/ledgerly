class ApiEndpoint {
  const ApiEndpoint._(this.uri);

  static const _configured = String.fromEnvironment(
    'LEDGERLY_API_BASE_URL',
  );

  static String get environmentDefault => _configured;

  final Uri uri;

  String get baseUrl => uri.origin;

  factory ApiEndpoint.resolve({
    required String configured,
    required bool isRelease,
    required bool isWeb,
  }) {
    final value = configured.trim();
    if (value.isEmpty) {
      throw const FormatException('The API endpoint must not be empty.');
    }

    final candidate = Uri.tryParse(value);
    if (candidate == null ||
        !candidate.hasScheme ||
        !candidate.hasAuthority ||
        !const {'http', 'https'}.contains(candidate.scheme.toLowerCase())) {
      throw const FormatException('The API endpoint must be an HTTP(S) URL.');
    }
    if (candidate.userInfo.isNotEmpty ||
        candidate.hasQuery ||
        candidate.hasFragment ||
        (candidate.path.isNotEmpty && candidate.path != '/')) {
      throw const FormatException(
        'The API endpoint must be an origin without credentials, path, query, or fragment.',
      );
    }

    final isLoopback = _isLocalOnlyHost(candidate.host);
    if (isRelease && (candidate.scheme != 'https' || isLoopback)) {
      throw const FormatException(
        'Release builds require a non-loopback HTTPS API endpoint.',
      );
    }
    if (isRelease && isWeb && candidate.hasPort && candidate.port != 443) {
      throw const FormatException(
        'Release Web builds require the default HTTPS port for cookie isolation.',
      );
    }

    return ApiEndpoint._(Uri.parse(candidate.origin));
  }

  static bool _isLocalOnlyHost(String value) {
    var host = value.toLowerCase();
    if (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host == 'localhost' || host.endsWith('.localhost')) {
      return true;
    }

    final ipv4 = _parseIpv4Literal(host);
    if (ipv4 != null) {
      return ipv4 == 0 || ipv4 >> 24 == 127;
    }

    final ipv6 = _parseIpv6Words(host);
    if (ipv6 == null) return false;
    final unspecified = ipv6.every((word) => word == 0);
    final loopback = ipv6.take(7).every((word) => word == 0) && ipv6[7] == 1;
    if (unspecified || loopback) return true;

    final mappedIpv4 = ipv6.take(5).every((word) => word == 0) &&
        (ipv6[5] == 0 || ipv6[5] == 0xffff);
    if (!mappedIpv4) return false;
    final embedded = (ipv6[6] << 16) | ipv6[7];
    return embedded == 0 || embedded >> 24 == 127;
  }

  // URL parsers accept one-to-four-part decimal, octal, and hexadecimal IPv4.
  static int? _parseIpv4Literal(String host) {
    final parts = host.split('.');
    if (parts.isEmpty ||
        parts.length > 4 ||
        parts.any((part) => part.isEmpty)) {
      return null;
    }
    final numbers = <int>[];
    for (final part in parts) {
      int? parsed;
      if (part.length > 2 && part.toLowerCase().startsWith('0x')) {
        parsed = int.tryParse(part.substring(2), radix: 16);
      } else if (part.length > 1 && part.startsWith('0')) {
        parsed = int.tryParse(part.substring(1), radix: 8);
      } else {
        parsed = int.tryParse(part);
      }
      if (parsed == null || parsed < 0) return null;
      numbers.add(parsed);
    }

    for (final number in numbers.take(numbers.length - 1)) {
      if (number > 255) return null;
    }
    final lastLimit = 1 << (8 * (5 - numbers.length));
    if (numbers.last >= lastLimit) return null;

    var address = numbers.last;
    for (var index = 0; index < numbers.length - 1; index++) {
      address += numbers[index] << (8 * (3 - index));
    }
    return address;
  }

  static List<int>? _parseIpv6Words(String host) {
    if (!host.contains(':')) return null;
    var normalized = host;
    final dottedStart = normalized.lastIndexOf(':') + 1;
    final dottedTail = normalized.substring(dottedStart);
    if (dottedTail.contains('.')) {
      final octets = dottedTail.split('.').map(int.tryParse).toList();
      if (octets.length != 4 ||
          octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
        return null;
      }
      final high = (octets[0]! << 8) | octets[1]!;
      final low = (octets[2]! << 8) | octets[3]!;
      normalized =
          '${normalized.substring(0, dottedStart)}${high.toRadixString(16)}:${low.toRadixString(16)}';
    }

    final halves = normalized.split('::');
    if (halves.length > 2) return null;
    List<String> words(String half) =>
        half.isEmpty ? const [] : half.split(':');
    final left = words(halves.first);
    final right = halves.length == 2 ? words(halves.last) : <String>[];
    final missing = 8 - left.length - right.length;
    if (missing < 0 || (halves.length == 1 && missing != 0)) return null;

    final values = <int>[];
    for (final word in [
      ...left,
      if (halves.length == 2) ...List.filled(missing, '0'),
      ...right,
    ]) {
      final parsed = int.tryParse(word, radix: 16);
      if (parsed == null || parsed < 0 || parsed > 0xffff) return null;
      values.add(parsed);
    }
    return values.length == 8 ? values : null;
  }
}
