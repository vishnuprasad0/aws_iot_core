export 'platform_transport_stub.dart'
    if (dart.library.io) 'platform_transport_io.dart'
    if (dart.library.js_interop) 'platform_transport_web.dart';
