import 'dart:io';

import 'package:path/path.dart' as p;

const sourceRoots = ['lib'];

List<FileSystemEntity> sourceEntities() => [
  for (final root in sourceRoots) ...Directory(root).listSync(recursive: true),
];

String portablePath(String path) => p.split(path).join('/');
