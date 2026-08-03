import 'package:dio/dio.dart';
import 'dio_platform_native.dart'
    if (dart.library.js_interop) 'dio_platform_web.dart' as platform;

void configureDioForPlatform(Dio dio) => platform.configureDio(dio);
