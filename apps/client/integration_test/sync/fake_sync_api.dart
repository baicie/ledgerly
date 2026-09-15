// A `SyncApi` subclass that delegates push / pull / bootstrap to a
// shared [FakeSyncServer] without touching the network.
//
// All other methods inherited from [SyncApi] still try to use the
// underlying Dio instance. SyncService only exercises push, pull, and
// bootstrap, so the unused Dio never issues a real request during the
// scenarios in `multi_device_sync_test.dart`. Tests that need a Dio
// mock for the rest of the API surface should construct their own
// adapter; this fake is intentionally narrow.

import 'package:dio/dio.dart';
import 'package:ledgerly_client/data/sync_api.dart';

import 'fake_sync_server.dart';

class FakeSyncApi extends SyncApi {
  FakeSyncApi({
    required FakeSyncServer server,
    required String deviceId,
    Dio? placeholderDio,
  })  : _server = server,
        _deviceId = deviceId,
        super(dio: placeholderDio ?? Dio());

  final FakeSyncServer _server;
  final String _deviceId;

  @override
  Future<Map<String, dynamic>> push({
    required String bookId,
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    assert(
      bookId == _server.bookId,
      'FakeSyncApi routed a push to the wrong bookId: '
      '$bookId != ${_server.bookId}',
    );
    return _server.push(deviceId: deviceId, mutations: mutations);
  }

  @override
  Future<Map<String, dynamic>> pull({
    required String bookId,
    required int cursor,
  }) async {
    assert(bookId == _server.bookId);
    return _server.pull(deviceId: _deviceId, cursor: cursor);
  }

  @override
  Future<Map<String, dynamic>> bootstrap({required String bookId}) async {
    assert(bookId == _server.bookId);
    return _server.bootstrap();
  }
}
