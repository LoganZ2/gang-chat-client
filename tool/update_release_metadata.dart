import 'dart:io';

void main(List<String> args) {
  final version = _requiredArg(args, '--version');
  final releasedAtValue = _requiredArg(args, '--released-at');

  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    _fail('version must be major.minor.patch: $version');
  }
  final releasedAt = DateTime.tryParse(releasedAtValue);
  if (releasedAt == null ||
      !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(releasedAtValue)) {
    _fail(
      'released-at must be an ISO 8601 timestamp with a timezone: '
      '$releasedAtValue',
    );
  }
  final releaseTimestamp = releasedAt.toUtc().toIso8601String();
  final releaseDate = _officialDate(releasedAt);

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
    RegExp(r"(const\s+gangChatClientReleaseTimestamp\s*=\s*')[^']+(';)"),
    releaseTimestamp,
    'gangChatClientReleaseTimestamp',
  );
  file.writeAsStringSync(source);

  stdout.writeln(
    'Updated release metadata: $version, released at $releaseTimestamp '
    '(UTC+08:00 date $releaseDate)',
  );
}

String _officialDate(DateTime value) {
  final official = value.toUtc().add(const Duration(hours: 8));
  final year = official.year.toString().padLeft(4, '0');
  final month = official.month.toString().padLeft(2, '0');
  final day = official.day.toString().padLeft(2, '0');
  return '$year/$month/$day';
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
