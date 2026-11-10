import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'appearance.dart';
import 'converter_page.dart';
import 'model.dart';
import 'model_page.dart';
import 'occt_probe.dart';
import 'package_import.dart';
import 'package_plan.dart';
import 'package_session.dart';
import 'strings.dart';
import 'sync.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.strings, this.initialDirectory});

  final S strings;
  final String? initialDirectory;

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _path;
  final _serverUrl = TextEditingController();
  List<PackageSummary> _packages = const [];
  String? _error;
  String _draft = '';
  SyncServer? _listener;
  String? _listenUrl;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDirectory ?? '';
    _path = TextEditingController(text: _draft);
    if (Platform.isAndroid && _draft.isEmpty) {
      PackageImport.libraryDirectory().then((dir) {
        if (!mounted || dir == null || dir.isEmpty) return;
        setState(() {
          _draft = dir;
          _path.text = dir;
        });
        scan();
      });
    } else if (_draft.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scan();
      });
    }
  }

  @override
  void dispose() {
    _path.dispose();
    _serverUrl.dispose();
    _listener?.close();
    super.dispose();
  }

  void scan() {
    final folder = _draft.trim().isEmpty ? _path.text.trim() : _draft.trim();
    final saved = folder.isEmpty ? '' : SyncSettings.load(folder).serverUrl;
    setState(() {
      _error = null;
      _packages = scanLibrary(folder);
      if (_serverUrl.text.isEmpty && saved.isNotEmpty) _serverUrl.text = saved;
    });
  }

  String get _folder =>
      _draft.trim().isEmpty ? _path.text.trim() : _draft.trim();

  Future<void> _pullSync() async {
    final folder = _folder;
    final url = _serverUrl.text.trim();
    if (folder.isEmpty || url.isEmpty) return;
    SyncSettings(serverUrl: url).save(folder);
    try {
      final result = await pullLibrary(folder, Uri.parse(url));
      if (!mounted) return;
      setState(() {
        _packages = scanLibrary(folder);
        _error = widget.strings.syncDone(result.copied, result.kept);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _listenSync() async {
    final folder = _folder;
    if (folder.isEmpty) return;
    await _listener?.close();
    try {
      final server = await SyncServer.start(folder);
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() {
        _listener = server;
        _listenUrl = server.base.toString();
        _error = widget.strings.syncListening(server.base.toString());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _occtProbe() async {
    setState(() => _error = widget.strings.occtProbeRunning);
    try {
      final text = await OcctProbeChannel.run();
      if (!mounted) return;
      setState(() => _error = null);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.occtProbe),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.strings.back),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _import() async {
    try {
      final path = await PackageImport.pick();
      if (!mounted || path == null || path.isEmpty) return;
      await _open(path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
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
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
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
    scan();
  }

  Future<void> _delete(PackageSummary package) async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.delete),
        content: Text(strings.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    deletePackage(package.path);
    scan();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.library),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ConverterPage(
                    strings: strings,
                    initialDirectory: _path.text.trim(),
                  ),
                ),
              );
            },
            child: Text(strings.converter),
          ),
          const AppearanceMenu(),
        ],
      ),
      body: Column(
        children: [
          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(strings.libraryStored),
              ),
            ),
          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: _occtProbe,
                  child: Text(strings.occtProbe),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (!Platform.isAndroid)
                  Expanded(
                    child: TextField(
                      controller: _path,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: strings.pathHint,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => _draft = value,
                      onSubmitted: (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        scan();
                      },
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ),
                if (!Platform.isAndroid) const SizedBox(width: 8),
                if (!Platform.isAndroid)
                  FilledButton(onPressed: scan, child: Text(strings.scan)),
                if (Platform.isAndroid)
                  FilledButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.folder_open),
                    label: Text(strings.importPackage),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _openSample,
                child: Text(strings.openSample),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('sync-url'),
                    controller: _serverUrl,
                    decoration: InputDecoration(
                      hintText: strings.syncUrl,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _pullSync, child: Text(strings.syncPull)),
                TextButton(
                  onPressed: _listenSync,
                  child: Text(strings.syncListen),
                ),
              ],
            ),
          ),
          if (_listenUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_listenUrl!),
              ),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: _packages.isEmpty
                ? Center(child: Text(strings.emptyLibrary))
                : ListView.builder(
                    itemCount: _packages.length,
                    itemBuilder: (context, index) {
                      final package = _packages[index];
                      final kb = (package.bytes / 1024).toStringAsFixed(0);
                      final date = libraryDateLabel(package.createdUtc);
                      final detail = date.isEmpty
                          ? '${package.schema} · ${package.elementCount} · $kb KB'
                          : '${package.schema} · ${package.elementCount} · $kb KB · $date';
                      return ListTile(
                        minTileHeight: 72,
                        leading: package.plan.isEmpty
                            ? const Icon(Icons.view_in_ar_outlined)
                            : PackagePlan(boxes: package.plan),
                        title: Text(package.name),
                        subtitle: Text(detail),
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
