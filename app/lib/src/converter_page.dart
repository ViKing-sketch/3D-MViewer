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
    });
    try {
      final process = await Process.start(_program.text.trim(), [
        ...converterArguments(entry.path, output),
      ]);
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode;
      final log = '${await stdoutText}${await stderrText}';
      if (!mounted) return;
      setState(() {
        _log = log;
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
                child: Text(strings.converterRunning),
              ),
            ),
            const LinearProgressIndicator(),
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
