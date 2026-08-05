import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/data/sync_api.dart';

void main() {
  test('release signed uploads reject public HTTP before sending', () async {
    final adapter = _RecordingAdapter();
    final uploadDio = Dio()..httpClientAdapter = adapter;
    final api = SyncApi(
      dio: Dio(),
      uploadDio: uploadDio,
      isRelease: true,
      isWeb: false,
    );

    await expectLater(
      api.putSignedUrl(
        uploadUrl: 'http://storage.example/upload?signature=test',
        bytes: const [1, 2, 3],
      ),
      throwsFormatException,
    );
    expect(adapter.requests, isEmpty);
  });

  test('release signed uploads allow private HTTP addresses', () async {
    final adapter = _RecordingAdapter();
    final uploadDio = Dio()..httpClientAdapter = adapter;
    final api = SyncApi(
      dio: Dio(),
      uploadDio: uploadDio,
      isRelease: true,
      isWeb: false,
    );

    await api.putSignedUrl(
      uploadUrl: 'http://192.168.1.24:8080/upload?signature=test',
      bytes: const [1, 2, 3],
    );

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.host, '192.168.1.24');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}
