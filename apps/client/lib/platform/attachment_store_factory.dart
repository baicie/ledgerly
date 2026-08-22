import 'attachment_store.dart';
import 'attachment_store_io.dart'
    if (dart.library.js_interop) 'attachment_store_web.dart' as impl;

AttachmentStore createPlatformAttachmentStore() =>
    impl.createPlatformAttachmentStore();
