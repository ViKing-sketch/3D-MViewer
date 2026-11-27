import 'dart:async';
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
import 'server_link.dart';
import 'strings.dart';
import 'sync.dart';

enum _Gate { wizard, library, connect, settings }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.strings,
    this.initialDirectory,
    this.tokenStore,
    this.initialConnectLink,
  });

  final S strings;
  final String? initialDirectory;
  final TokenStore? tokenStore;
  final String? initialConnectLink;

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _path;
  final _address = TextEditingController();
  final _tokenField = TextEditingController();
  late final TokenStore _tokens = widget.tokenStore ?? KeystoreTokenStore();
  List<PackageSummary> _packages = const [];
  Set<String> _serverPackages = const {};
  String? _banner;
  SyncNoticeKind? _noticeKind;
  String _draft = '';
  String _setup = '';
  String? _incoming;
  SyncServer? _listener;
  String? _listenUrl;
  _Gate _gate = _Gate.wizard;
  bool _booting = false;
  bool _autoPull = false;
  bool _pulling = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDirectory ?? '';
    _path = TextEditingController(text: _draft);
    final link = widget.initialConnectLink;
    if (link != null && link.isNotEmpty) _incoming = link;
    if (_draft.isNotEmpty) _applyFolder(_draft);
    if (Platform.isAndroid) {
      ConnectChannel.bind((value) {
        if (!mounted) return;
        _incoming = value;
        unawaited(_consumeIncoming());
      });
    }
    final androidLibrary =
        Platform.isAndroid &&
        (widget.initialDirectory == null || widget.initialDirectory!.isEmpty);
    if (androidLibrary) {
      _booting = true;
      unawaited(_bootAndroid());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_afterReady());
      });
    }
  }

  Future<void> _bootAndroid() async {
    final dir = await PackageImport.libraryDirectory();
    final link = await ConnectChannel.take();
    if (!mounted) return;
    setState(() {
      if (dir != null && dir.isNotEmpty) {
        _draft = dir;
        _path.text = dir;
        _applyFolder(dir);
      }
      if (link != null && link.isNotEmpty) _incoming = link;
      _booting = false;
    });
    await _afterReady();
  }

  void _applyFolder(String folder) {
    if (folder.isEmpty) return;
    final settings = SyncSettings.load(folder);
    _setup = settings.setup;
    _serverPackages = settings.serverPackages.toSet();
    if (_incoming != null && _incoming!.isNotEmpty) return;
    if (settings.setup == 'local' || settings.setup == 'server') {
      _gate = _Gate.library;
    }
    _autoPull = settings.setup == 'server' && settings.serverUrl.isNotEmpty;
  }

  Future<void> _afterReady() async {
    if (!mounted) return;
    if (_gate == _Gate.library && _folder.isNotEmpty) scan();
    if (_incoming != null && _incoming!.isNotEmpty) {
      await _consumeIncoming();
      return;
    }
    if (_autoPull) {
      _autoPull = false;
      await _pull();
    }
  }

  @override
  void dispose() {
    _path.dispose();
    _address.dispose();
    _tokenField.dispose();
    _listener?.close();
    super.dispose();
  }

  void scan() {
    final folder = _folder;
    final settings = folder.isEmpty
        ? const SyncSettings()
        : SyncSettings.load(folder);
    setState(() {
      _packages = folder.isEmpty ? const [] : scanLibrary(folder);
      _serverPackages = settings.serverPackages.toSet();
      if (settings.setup == 'local' || settings.setup == 'server') {
        _setup = settings.setup;
      }
    });
  }

  String get _folder =>
      _draft.trim().isEmpty ? _path.text.trim() : _draft.trim();

  Future<void> _pull({bool announceSuccess = false}) async {
    final folder = _folder;
    if (folder.isEmpty || _pulling) return;
    final settings = SyncSettings.load(folder);
    final url = settings.serverUrl.trim();
    if (url.isEmpty) return;
    _pulling = true;
    final token = await _tokens.read();
    if (!mounted) {
      _pulling = false;
      return;
    }
    try {
      final result = await pullLibrary(folder, Uri.parse(url), token: token);
      if (!mounted) return;
      SyncSettings(
        serverUrl: settings.serverUrl,
        setup: 'server',
        serverPackages: result.packages,
      ).save(folder);
      setState(() {
        _packages = scanLibrary(folder);
        _serverPackages = result.packages.toSet();
        _setup = 'server';
        _noticeKind = null;
        _banner = announceSuccess ? widget.strings.serverReachable : null;
      });
    } catch (error) {
      if (!mounted) return;
      final notice = syncNotice(error, widget.strings);
      setState(() {
        _packages = scanLibrary(folder);
        _noticeKind = notice.kind;
        _banner = notice.message;
      });
    } finally {
      _pulling = false;
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
        _noticeKind = null;
        _banner = widget.strings.syncListening(server.base.toString());
      });
    } catch (error) {
      if (!mounted) return;
      final notice = syncNotice(error, widget.strings);
      setState(() {
        _noticeKind = notice.kind;
        _banner = notice.message;
      });
    }
  }

  Future<void> _accept(ServerLink link) async {
    final folder = _folder;
    if (folder.isEmpty) {
      setState(() {
        _noticeKind = null;
        _banner = widget.strings.connectNeedFolder;
      });
      return;
    }
    try {
      if (link.token.isEmpty) {
        await _tokens.clear();
      } else {
        await _tokens.write(link.token);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _noticeKind = null;
        _banner = widget.strings.tokenStoreFailed;
      });
      return;
    }
    if (!mounted) return;
    final previous = SyncSettings.load(folder);
    SyncSettings(
      serverUrl: link.address.toString(),
      setup: 'server',
      serverPackages: previous.serverPackages,
    ).save(folder);
    setState(() {
      _setup = 'server';
      _gate = _Gate.library;
      _noticeKind = null;
      _banner = null;
    });
    await _pull();
  }

  Future<void> _consumeIncoming() async {
    final raw = _incoming;
    if (raw == null || raw.isEmpty || _folder.isEmpty) return;
    _incoming = null;
    final parsed = ServerLink.parse(raw);
    if (parsed == null) {
      if (!mounted) return;
      setState(() {
        _gate = _Gate.connect;
        _noticeKind = null;
        _banner = widget.strings.connectInvalid;
      });
      return;
    }
    await _accept(parsed);
  }

  Future<void> _applyManual() async {
    final raw = _address.text.trim();
    final parsed = ServerLink.parse(raw);
    if (parsed != null) {
      await _accept(parsed);
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() {
        _noticeKind = null;
        _banner = widget.strings.connectInvalid;
      });
      return;
    }
    await _accept(ServerLink(uri, _tokenField.text.trim()));
  }

  Future<void> _scanQr() async {
    if (!Platform.isAndroid) {
      setState(() {
        _noticeKind = null;
        _banner = widget.strings.cameraPhoneOnly;
      });
      return;
    }
    final raw = await QrScanner.scan(title: widget.strings.scanQr);
    if (!mounted || raw == null || raw.isEmpty) return;
    _incoming = raw;
    await _consumeIncoming();
  }

  void _chooseLocal() {
    final folder = _folder;
    if (folder.isNotEmpty) {
      const SyncSettings(setup: 'local').save(folder);
    }
    _setup = 'local';
    _gate = _Gate.library;
    _banner = null;
    _noticeKind = null;
    _autoPull = false;
    scan();
  }

  Future<void> _forget() async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.serverForget),
        content: Text(strings.serverForgetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.serverForget),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _tokens.clear();
    } catch (_) {}
    await _listener?.close();
    final folder = _folder;
    if (folder.isNotEmpty) const SyncSettings().save(folder);
    if (!mounted) return;
    setState(() {
      _listener = null;
      _listenUrl = null;
      _setup = '';
      _serverPackages = const {};
      _gate = _Gate.wizard;
      _banner = null;
      _noticeKind = null;
      _autoPull = false;
    });
  }

  void _back() {
    setState(() {
      _banner = null;
      _noticeKind = null;
      _gate = _setup == 'server' ? _Gate.library : _Gate.wizard;
    });
  }

  Future<void> _occtProbe() async {
    setState(() => _banner = widget.strings.occtProbeRunning);
    try {
      final text = await OcctProbeChannel.run();
      if (!mounted) return;
      setState(() => _banner = null);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.strings.occtProbe),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(text)),
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
      setState(() {
        _noticeKind = null;
        _banner = error.toString();
      });
    }
  }

  Future<void> _import() async {
    try {
      final path = await PackageImport.pick();
      if (!mounted || path == null || path.isEmpty) return;
      await _open(path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _noticeKind = null;
        _banner = error.toString();
      });
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

  String _title(S strings) {
    return switch (_gate) {
      _Gate.wizard => strings.setupTitle,
      _Gate.connect => strings.connectTitle,
      _Gate.settings => strings.settingsTitle,
      _Gate.library => strings.library,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _gate == _Gate.library || _gate == _Gate.wizard
            ? null
            : BackButton(onPressed: _back),
        title: Text(_title(strings)),
        actions: [
          if (_gate == _Gate.library)
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
          if (_gate == _Gate.library && _setup == 'server')
            IconButton(
              tooltip: strings.settingsTitle,
              onPressed: () => setState(() {
                _banner = null;
                _noticeKind = null;
                _gate = _Gate.settings;
              }),
              icon: const Icon(Icons.settings_outlined),
            ),
          const AppearanceMenu(),
        ],
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : switch (_gate) {
              _Gate.wizard => _wizard(strings),
              _Gate.connect => _connect(strings),
              _Gate.settings => _settings(strings),
              _Gate.library => _library(strings),
            },
    );
  }

  Widget _wizard(S strings) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(strings.setupOnce),
        const SizedBox(height: 24),
        FilledButton(onPressed: _chooseLocal, child: Text(strings.setupLocal)),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => setState(() {
            _banner = null;
            _noticeKind = null;
            _gate = _Gate.connect;
          }),
          child: Text(strings.setupServer),
        ),
      ],
    );
  }

  Widget _connect(S strings) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(strings.connectHint),
        const SizedBox(height: 24),
        FilledButton(onPressed: _scanQr, child: Text(strings.scanQr)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _advanced = !_advanced),
          child: Text(strings.connectAdvanced),
        ),
        if (_advanced) ...[
          TextField(
            key: const Key('server-address'),
            controller: _address,
            decoration: InputDecoration(
              labelText: strings.connectAddress,
              hintText: 'http://192.168.0.10:8080',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('server-token'),
            controller: _tokenField,
            decoration: InputDecoration(
              labelText: strings.connectToken,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _applyManual,
            child: Text(strings.connectApply),
          ),
        ],
        _bannerBar(strings),
      ],
    );
  }

  Widget _settings(S strings) {
    final folder = _folder;
    final settings = folder.isEmpty
        ? const SyncSettings()
        : SyncSettings.load(folder);
    final address = settings.serverUrl.isEmpty
        ? strings.serverNone
        : settings.serverUrl;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.settingsServer,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(address),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _pulling ? null : () => _pull(announceSuccess: true),
          child: Text(strings.serverCheck),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () => setState(() {
            _banner = null;
            _noticeKind = null;
            _gate = _Gate.connect;
          }),
          child: Text(strings.serverChange),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _forget, child: Text(strings.serverForget)),
        const SizedBox(height: 24),
        TextButton(onPressed: _listenSync, child: Text(strings.syncListen)),
        if (_listenUrl != null) Text(_listenUrl!),
        _bannerBar(strings),
      ],
    );
  }

  Widget _library(S strings) {
    return Column(
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
        _bannerBar(strings),
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
                    final fromServer = _serverPackages.contains(
                      p.basename(package.path),
                    );
                    return ListTile(
                      minTileHeight: 72,
                      leading: package.plan.isEmpty
                          ? const Icon(Icons.view_in_ar_outlined)
                          : PackagePlan(boxes: package.plan),
                      title: Row(
                        children: [
                          Expanded(child: Text(package.name)),
                          if (fromServer)
                            const Icon(
                              Icons.cloud_outlined,
                              semanticLabel: 'server-model',
                            ),
                        ],
                      ),
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
    );
  }

  Widget _bannerBar(S strings) {
    final text = _banner;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (_noticeKind == SyncNoticeKind.unavailable ||
              _noticeKind == SyncNoticeKind.interrupted)
            TextButton(
              onPressed: _pulling ? null : () => _pull(),
              child: Text(strings.syncRetry),
            ),
          if (_noticeKind == SyncNoticeKind.revoked)
            TextButton(
              onPressed: () => setState(() => _gate = _Gate.connect),
              child: Text(strings.syncRescan),
            ),
        ],
      ),
    );
  }
}
