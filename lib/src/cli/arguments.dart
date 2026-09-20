(List<String>, Map<String, String>) parseOptions(
  List<String> args,
  Set<String> allowed,
) {
  final positionals = <String>[], options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final argument = args[i];
    if (!argument.startsWith('--')) {
      positionals.add(argument);
      continue;
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || options.containsKey(key)) {
      throw FormatException('Unknown or repeated option --$key.');
    }
    if (++i == args.length || args[i].startsWith('--')) {
      throw FormatException('Missing value for --$key.');
    }
    options[key] = args[i];
  }
  return (positionals, options);
}

String requiredOption(Map<String, String> options, String key) =>
    options[key] ?? (throw FormatException('Missing --$key.'));
