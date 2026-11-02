import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'model.dart';
import 'model_page.dart';
import 'package_session.dart';
import 'strings.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.strings, this.initialDirectory});

  final S strings;
  final String? initialDirectory;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _path;
  List<PackageSummary> _packages = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.initialDirectory ?? '');
    if ((widget.initialDirectory ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scan();
      });
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _scan() {
    setState(() {
      _error = null;
      _packages = scanLibrary(_path.text.trim());
    });
  }

  Future<void> _openSample() async {
    final temp = await Directory.systemTemp.createTemp('fbv-sample-');
    const files = [
      'manifest.json',
      'meta.sqlite',
      'brep.pack',
      'brep.index',
      'mesh/lod0.glb',
      'mesh/elements/1.glb',
      'mesh/elements/2.glb',
      'mesh/elements/3.glb',
    ];
    for (final relative in files) {
      final data = await rootBundle.load('assets/sample_model/$relative');
      final file = File(p.join(temp.path, relative));
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    if (!mounted) return;
    await _open(temp.path);
  }

  Future<void> _open(String path) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ModelPage(path: path, strings: widget.strings),
      ),
    );
    _scan();
  }

  Future<void> _delete(PackageSummary package) async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.delete),
        content: Text(strings.deleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    deletePackage(package.path);
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.library)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _path,
                    decoration: InputDecoration(
                      hintText: strings.pathHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _scan, child: Text(strings.scan)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(onPressed: _openSample, child: Text(strings.openSample)),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: _packages.isEmpty
                ? Center(child: Text(strings.emptyLibrary))
                : ListView.builder(
                    itemCount: _packages.length,
                    itemBuilder: (context, index) {
                      final package = _packages[index];
                      final kb = (package.bytes / 1024).toStringAsFixed(0);
                      return ListTile(
                        minTileHeight: 64,
                        title: Text(package.name),
                        subtitle: Text('${package.schema} · ${package.elementCount} · $kb KB'),
                        onTap: () => _open(package.path),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: strings.delete,
                          onPressed: () => _delete(package),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
