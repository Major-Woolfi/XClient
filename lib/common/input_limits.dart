import 'package:flutter/services.dart';

abstract final class TextInputLimits {
  static const name = 64;
  static const groupName = 64;
  static const proxyName = 255;
  static const url = 2048;
  static const uri = url;
  static const iconUrl = url;
  static const dnsServer = url;
  static const hostValue = url;
  static const userName = 128;
  static const password = 512;
  static const userAgent = 512;
  static const fileName = 255;
  static const port = 5;
  static const portRange = 11;
  static const number = 10;
  static const interval = number;

  /// mihomo умножает эти часы на Duration, который переполняется примерно после
  /// 2,5 миллионов и паникует его тикер обновления.
  static const geoUpdateInterval = 6;
  static const rule = 1024;
  static const filter = 1024;
  static const status = 128;
  static const dnsListen = 255;
  static const domain = 512;
  static const geoSite = 128;
  static const geoIpCode = 16;
  static const cidr = 64;

  static List<TextInputFormatter> limit(int maxLength) {
    return [LengthLimitingTextInputFormatter(maxLength)];
  }

  /// Строка правила соединяет свои поля запятыми, поэтому никакое правило не может назвать политику,
  /// содержащую её.
  static List<TextInputFormatter> policyName(int maxLength) {
    return [
      FilteringTextInputFormatter.deny(','),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  static List<TextInputFormatter> digitsOnly(int maxLength) {
    return [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }
}
