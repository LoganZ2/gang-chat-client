bool shouldUseV2(List<String> args) {
  return args.any((arg) {
    final normalized = arg.trim().toLowerCase();
    return normalized == 'v2' || normalized == '--v2';
  });
}
