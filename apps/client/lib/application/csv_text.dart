import 'dart:convert';

import 'package:gbk_codec/gbk_codec.dart';

String decodeBillCsvBytes(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return gbk.decode(bytes);
  }
}
