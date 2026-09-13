import 'dart:convert';
import 'dart:io';

import 'package:bjdata/bjdata.dart';

Future<void> main(List<String> arguments) async {
  final config = BjdataConfig(
    version: _draft(arguments),
    soa: switch (arguments) {
      _ when arguments.contains('--no-soa') => BjdataSoaLayout.off,
      _ when arguments.contains('--column-major') => BjdataSoaLayout.columnMajor,
      _ => BjdataSoaLayout.rowMajor,
    },
    multiDimensional: !arguments.contains('--no-nd'),
  );
  final positional = arguments.where((a) => !a.startsWith('-')).toList();
  final command = positional.isNotEmpty ? positional[0] : null;
  final inputPath = positional.length > 1 ? positional[1] : null;
  final outputPath = positional.length > 2 ? positional[2] : null;

  final _ = switch (command) {
    'block' => await block(inputPath, outputPath, config),
    'encode' => await encode(inputPath, outputPath, config),
    'decode' => await decode(inputPath, outputPath),
    _ => usage(arguments.contains('-h') || arguments.contains('--help')),
  };
}

/// The revision named by `--draft=N`, or the newest one if it was not given.
BjdataVersion _draft(List<String> arguments) {
  const prefix = '--draft=';
  final argument = arguments.lastWhere((a) => a.startsWith(prefix), orElse: () => '');
  if (argument.isEmpty) return BjdataVersion.values.last;

  final draft = argument.substring(prefix.length);
  return BjdataVersion.values.firstWhere(
    (version) => version.name == 'draft$draft',
    orElse: () {
      stderr.writeln("Unknown draft '$draft', expected one of ${_draftNumbers.join(', ')}");
      exit(1);
    },
  );
}

/// The draft numbers of every [BjdataVersion], as `--draft=N` takes them.
Iterable<String> get _draftNumbers => BjdataVersion.values.map((version) => version.name.replaceFirst('draft', ''));

Future<List<int>> _readInput(String? inputPath) async {
  if (inputPath != null) {
    return await File(inputPath).readAsBytes();
  } else {
    stderr.writeln("Waiting for input from stdin...");
    stderr.writeln("(Press Ctrl-D (Unix) or Ctrl-Z + Enter (Windows) to end input)");
    final result = await stdin.expand((x) => x).toList();
    stderr.writeln();
    return result;
  }
}

Future<void> _writeOutput(String? outputPath, List<int> content) async {
  if (outputPath != null) {
    await File(outputPath).writeAsBytes(content);
    stderr.writeln("Wrote ${content.length} bytes to '$outputPath'");
  } else {
    stdout.add(content);
  }
}

void usage(bool requested) {
  final out = requested ? stdout : stderr;
  out.writeln("A command-line utility for BJData encoding and decoding.");
  out.writeln();
  out.writeln('Usage: bjdata <block|encode|decode> [input] [output] [options]');
  out.writeln(
    '- Input and output are optional file paths\n'
    '- If omitted, stdin/stdout are used\n'
    '- Uniform tables of records are packed as row-major Structure-of-Arrays\n'
    '  containers by default',
  );
  out.writeln();
  out.writeln('Commands:');
  out.writeln('  block   Convert JSON to BJData block notation');
  out.writeln('  encode  Convert JSON to BJData binary');
  out.writeln('  decode  Convert BJData binary to JSON');
  out.writeln();
  out.writeln('Options:');
  out.writeln('  --draft=N        Write draft N output (${_draftNumbers.join('/')}), the newest by default;\n'
      '                   draft 3 has no packed tables');
  out.writeln('  --no-soa         Write tables as plain arrays of objects');
  out.writeln('  --column-major   Pack tables by field rather than by record');
  out.writeln('  --no-nd          Do not pack nested tables into one N-dimensional container');
  out.writeln();
  if (!requested) exit(1);
}

Future<void> block(String? inputPath, String? outputPath, BjdataConfig config) async {
  final input = await _readInput(inputPath);
  final data = json.decode(utf8.decode(input));
  final block = bjdataBlockNotation(data, indent: '    ', config: config);
  await _writeOutput(outputPath, utf8.encode(block));
}

Future<void> encode(String? inputPath, String? outputPath, BjdataConfig config) async {
  final input = await _readInput(inputPath);
  final data = jsonDecode(utf8.decode(input));
  final bjdata = bjdataEncode(data, config: config);
  await _writeOutput(outputPath, bjdata);
}

Future<void> decode(String? inputPath, String? outputPath) async {
  final input = await _readInput(inputPath);
  final data = bjdataDecode(input);
  final json = '${const JsonEncoder.withIndent('  ').convert(data)}\n';
  await _writeOutput(outputPath, utf8.encode(json));
}
