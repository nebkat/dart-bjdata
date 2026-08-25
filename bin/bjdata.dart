import 'dart:convert';
import 'dart:io';

import 'package:bjdata/bjdata.dart';

Future<void> main(List<String> arguments) async {
  final soa = switch (arguments) {
    _ when arguments.contains('--no-soa') => BjdataSoaLayout.off,
    _ when arguments.contains('--column-major') => BjdataSoaLayout.columnMajor,
    _ => BjdataSoaLayout.rowMajor,
  };
  final positional = arguments.where((a) => !a.startsWith('-')).toList();
  final command = positional.isNotEmpty ? positional[0] : null;
  final inputPath = positional.length > 1 ? positional[1] : null;
  final outputPath = positional.length > 2 ? positional[2] : null;

  final _ = switch (command) {
    'block' => await block(inputPath, outputPath, soa),
    'encode' => await encode(inputPath, outputPath, soa),
    'decode' => await decode(inputPath, outputPath),
    _ => usage(arguments.contains('-h') || arguments.contains('--help')),
  };
}

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
  out.writeln('Usage: bjdata <block|encode|decode> [input] [output] [--no-soa|--column-major]');
  out.writeln(
    '- Input and output are optional file paths\n'
    '- If omitted, stdin/stdout are used\n'
    '- Uniform tables of records are packed as row-major Structure-of-Arrays\n'
    '  containers; --column-major packs them by field instead, and --no-soa\n'
    '  writes plain arrays of objects',
  );
  out.writeln();
  out.writeln('Commands:');
  out.writeln('  block   Convert JSON to BJData block notation');
  out.writeln('  encode  Convert JSON to BJData binary');
  out.writeln('  decode  Convert BJData binary to JSON');
  out.writeln();
  if (!requested) exit(1);
}

Future<void> block(String? inputPath, String? outputPath, BjdataSoaLayout soa) async {
  final input = await _readInput(inputPath);
  final data = json.decode(utf8.decode(input));
  final block = bjdataBlockNotation(data, indent: '    ', soa: soa);
  await _writeOutput(outputPath, utf8.encode(block));
}

Future<void> encode(String? inputPath, String? outputPath, BjdataSoaLayout soa) async {
  final input = await _readInput(inputPath);
  final data = jsonDecode(utf8.decode(input));
  final bjdata = bjdataEncode(data, soa: soa);
  await _writeOutput(outputPath, bjdata);
}

Future<void> decode(String? inputPath, String? outputPath) async {
  final input = await _readInput(inputPath);
  final data = bjdataDecode(input);
  final json = '${const JsonEncoder.withIndent('  ').convert(data)}\n';
  await _writeOutput(outputPath, utf8.encode(json));
}
