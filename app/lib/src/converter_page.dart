import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'converter_catalog.dart';
import 'model.dart';
import 'strings.dart';

class ConverterPage extends StatefulWidget {
  const ConverterPage({
    super.key,
    required this.strings,
    this.initialDirectory,
    this.initialProgram = 'fbvconv',
  });

  final S strings;
  final String? initialDirectory;
  final String initialProgram;

  @override
  State<ConverterPage> createState() => ConverterPageState();
}

class ConverterPageState extends State<ConverterPage> {
  late final TextEditingController _folder;
  late final TextEditingController _program;
  List<CatalogEntry> _entries = const [];
  String? _running;
  String _log = '';
  StageProgress? _progress;
  final Map<String, int> _codes = {};

  @override
  void initState() {
    super.initState();
    _folder = TextEditingController(text: widget.initialDirectory ?? '');
    _program = TextEditingController(text: widget.initialProgram);
    if ((widget.initialDirectory ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scan();
      });
    }
  }

  @override
  void dispose() {
    _folder.dispose();
    _program.dispose();
    super.dispose();
  }

  void scan() {
    setState(() => _entries = listConverterFolder(_folder.text.trim()));
  }

  Future<String> _collect(
    Stream<List<int>> stream,
    void Function(String line) onLine,
  ) {
    final completer = Completer<String>();
    final buffer = StringBuffer();
    var pending = '';
    stream
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            pending += chunk;
            while (true) {
              final nl = pending.indexOf('\n');
              if (nl < 0) break;
              final line = pending.substring(0, nl);
              pending = pending.substring(nl + 1);
              buffer.writeln(line);
              onLine(line);
            }
          },
          onDone: () {
            if (pending.isNotEmpty) {
              buffer.write(pending);
              onLine(pending);
            }
            completer.complete(buffer.toString());
          },
          onError: completer.completeError,
        );
    return completer.future;
  }

  Future<void> convert(CatalogEntry entry) async {
    if (_running != null || entry.kind != CatalogKind.ifc) return;
    final output = outputDirectoryFor(entry.path);
    if (Directory(output).existsSync() || File(output).existsSync()) {
      setState(() => _log = widget.strings.converterExists);
      return;
    }
    setState(() {
      _running = entry.path;
      _log = '';
      _progress = null;
    });
    try {
      final process = await Process.start(_program.text.trim(), [
        ...converterArguments(entry.path, output),
      ]);
      StageProgress? latest;
      void note(String line) {
        final mark = parseStageProgress(line);
        if (mark == null || !mounted) return;
        latest = mark;
        setState(() => _progress = mark);
      }

      final stdoutText = _collect(process.stdout, note);
      final stderrText = _collect(process.stderr, note);
      final code = await process.exitCode;
      final log = '${await stdoutText}${await stderrText}';
      if (!mounted) return;
      setState(() {
        _log = log;
        _progress = latest;
        _codes[entry.path] = code;
        _running = null;
      });
      scan();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _log = error.toString();
        _codes[entry.path] = -1;
        _running = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.converter)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              key: const Key('converter-folder'),
              controller: _folder,
              decoration: InputDecoration(
                hintText: strings.converterFolder,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => scan(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              key: const Key('converter-program'),
              controller: _program,
              decoration: InputDecoration(
                hintText: strings.converterProgram,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(onPressed: scan, child: Text(strings.scan)),
            ),
          ),
          if (_running != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _progress == null
                      ? strings.converterRunning
                      : '${strings.converterRunning} ${_progress!.done}/${_progress!.total}',
                ),
              ),
            ),
            LinearProgressIndicator(
              value: _progress == null ? null : _progress!.fraction,
            ),
          ],
          Expanded(
            child: _entries.isEmpty
                ? Center(child: Text(strings.converterEmpty))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final date = libraryDateLabel(entry.modifiedUtc);
                      final kind = entry.kind == CatalogKind.ifc
                          ? strings.kindIfc
                          : strings.kindPackage;
                      final code = _codes[entry.path];
                      final status = _running == entry.path
                          ? strings.converterRunning
                          : code == null
                          ? strings.converterIdle
                          : strings.converterDone(code);
                      return ListTile(
                        title: Text(entry.name),
                        subtitle: Text(
                          '$kind · ${entry.bytes} B · $date · $status',
                        ),
                        trailing: entry.kind == CatalogKind.ifc
                            ? FilledButton(
                                onPressed: _running == null
                                    ? () => convert(entry)
                                    : null,
                                child: Text(strings.convert),
                              )
                            : null,
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(strings.converterLog),
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [SelectableText(_log.isEmpty ? '—' : _log)],
            ),
          ),
        ],
      ),
    );
  }
}
