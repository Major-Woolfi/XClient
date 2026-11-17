/// Аргументы для `stat` в зависимости от платформы.
List<String> statArguments(String corePath, {required bool isMacOS}) {
  return isMacOS
      ? ['-f', '%Su:%Sg %Sp', corePath]
      : ['-c', '%U:%G %A', corePath];
}

/// Проверяет, что вывод `stat` показывает, что файл принадлежит указанному
/// владельцу, имеет бит setuid и не имеет бита выполнения для others.
bool isPrivilegedStatOutput(String output, {required String ownerPrefix}) {
  final trimmed = output.trim();
  if (!trimmed.startsWith(ownerPrefix)) {
    return false;
  }
  final mode = trimmed.split(RegExp(r'\s+')).last;
  return mode.length >= 10 &&
      mode[3] == 's' &&
      mode[9] != 'x' &&
      mode[9] != 't';
}

/// Shell-команда chown/chmod для macOS.
String macOSElevationShell(String corePath) {
  final path = _shellEscape(corePath);
  return 'chown root:admin $path && chmod 4750 $path';
}

/// Shell-команда chown/chmod для Linux.
String linuxElevationShell(String corePath) {
  final path = _shellEscape(corePath);
  return 'group=\$(id -g "\${PKEXEC_UID:-\$SUDO_UID}") && '
      'chown "root:\$group" $path && '
      'chmod 4750 $path';
}

/// Аргументы для `chmod +a` (ACL) на macOS.
List<String> aclArguments(String homeDirPath, String userName) {
  const inheritedAclPermissions =
      'list,search,add_file,add_subdirectory,delete,delete_child,'
      'file_inherit,directory_inherit';
  return [
    '-R',
    '+a',
    'user:$userName allow $inheritedAclPermissions',
    homeDirPath,
  ];
}

/// Экранирует строку для безопасной вставки в shell-команду.
String _shellEscape(String value) {
  return "'${value.replaceAll("'", "'\\''")}'";
}
