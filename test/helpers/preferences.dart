import 'package:xclient/common/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Поддерживает [preferences] свежим внутрипамятьным хранилищем, содержащим [values].
Future<void> mockPreferences([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return preferences.rebind();
}
