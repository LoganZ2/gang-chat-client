import 'dart:io';

void main(List<String> args) {
  final version = _requiredArg(args, '--version');
  final releaseDate = _requiredArg(args, '--date');

  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    _fail('version must be major.minor.patch: $version');
  }
  if (!RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(releaseDate)) {
    _fail('date must be yyyy/MM/dd: $releaseDate');
  }

  final file = File('lib/src/app/settings_about.dart');
  if (!file.existsSync()) {
    _fail('settings_about.dart not found; run from repository root.');
  }

  var source = file.readAsStringSync();
  source = _replaceSingle(
    source,
    RegExp(r"(defaultValue:\s*')[^']+(')"),
    version,
    'gangChatClientVersion defaultValue',
  );
  source = _replaceSingle(
    source,
    RegExp(r"(const\s+gangChatClientReleaseDate\s*=\s*')[^']+(';)"),
    releaseDate,
    'gangChatClientReleaseDate',
  );
  source = _replaceSingle(
    source,
    RegExp(r"(const\s+gangChatClientLastUpdateDate\s*=\s*')[^']+(';)"),
    releaseDate,
    'gangChatClientLastUpdateDate',
  );
  file.writeAsStringSync(source);

  stdout.writeln(
    'Updated release metadata: $version, release/update date $releaseDate',
  );
}

String _requiredArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    _fail('missing required argument: $name');
  }
  return args[index + 1].trim();
}

String _replaceSingle(
  String source,
  RegExp pattern,
  String value,
  String description,
) {
  final matches = pattern.allMatches(source).toList(growable: false);
  if (matches.length != 1) {
    _fail('expected one match for $description, found ${matches.length}');
  }
  final match = matches.single;
  return source.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$value${match.group(2)}',
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
