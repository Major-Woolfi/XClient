import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:xclient/common/common.dart';
import 'package:xclient/database/database.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'database.dart';

part 'generated/state.g.dart';
part 'state/proxies.dart';
part 'state/navigation.dart';
part 'state/system.dart';
part 'state/theme.dart';
part 'state/profile.dart';
part 'state/custom.dart';
part 'state/custom_import.dart';
