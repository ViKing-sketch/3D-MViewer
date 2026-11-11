import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'csv_export.dart';
import 'filament_channel.dart';
import 'geometry_method.dart';
import 'package_import.dart';
import 'filament_viewport.dart';
import 'model.dart';
import 'package_session.dart';
import 'remarks.dart';
import 'remarks_section.dart';
import 'strings.dart';
import 'visibility.dart';
import 'walk_pose.dart';

class ModelPage extends StatefulWidget {
  const ModelPage({super.key, required this.path, required this.strings});

  final String path;
  final S strings;

  @override
  State<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends State<ModelPage>
    with SingleTickerProviderStateMixin {
  PackageSession? _session;
  RemarkStore? _remarks;
  List<SpatialNode> _spatial = const [];
  List<SystemInfo> _systems = const [];
  List<ElementInfo> _elements = const [];
  List<ElementBox> _boxes = const [];
  List<SpecRow> _specs = const [];
  String? _error;
  int? _selectedId;
  String _query = '';
  Set<int>? _searchIds;
  SceneFilter _filter = const SceneFilter();
  final Set<int> _hidden = {};
  final Set<int> _isolated = {};
  bool _xray = false;
  SectionView _section = const SectionView();
  double? _sectionBoxSpan;
  double? _sectionAt;
  int _renderRevision = 0;
  bool _opening = false;
  bool _closing = false;
  bool _left = false;
  bool _cancel = false;
  int _extractDone = 0;
  int _extractTotal = 0;
  int _frameToken = 0;
  String _propQuery = '';
  final Set<String> _collapsedGroups = {};
  Set<int> _standIns = {};
  void Function()? _cancelExtract;
  final _viewport = GlobalKey<FilamentViewportState>();
  final _sheet = DraggableScrollableController();
  int _fitToken = 0;
  bool _walking = false;
  GeometryDecision? _geometry;
  int _walkToken = 0;
  WalkPose? _walkPose;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTab);
    final type = FileSystemEntity.typeSync(widget.path);
    if (type == FileSystemEntityType.file) {
      _opening = true;
      unawaited(_openZip());
    } else {
      _openSync();
    }
  }

  void _openSync() {
    try {
      final session = PackageSession.openPath(widget.path);
      _session = session;
      _spatial = session.spatial();
      _systems = session.systems();
      _elements = session.elements();
      _boxes = session.elementBoxes();
      _specs = session.specifications();
      _remarks = RemarkStore(widget.path)..load();
      _prepareGeometry(session);
    } catch (error) {
      _error = error.toString();
    }
  }

  Future<void> _openZip() async {
    var lastPaint = 0;
    try {
      final session = await PackageSession.openPathAsync(
        widget.path,
        isCancelled: () => _cancel,
        onProgress: (done, total) {
          if (!mounted || _cancel) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (done != total && now - lastPaint < 120) return;
          lastPaint = now;
          setState(() {
            _extractDone = done;
            _extractTotal = total;
          });
        },
        onCancel: (cancel) {
          _cancelExtract = cancel;
          if (_cancel) cancel();
        },
      );
      await Future<void>.delayed(Duration.zero);
      if (_cancel || _left || !mounted) {
        session.close();
        return;
      }
      setState(() {
        _session = session;
        _spatial = session.spatial();
        _systems = session.systems();
        _elements = session.elements();
        _boxes = session.elementBoxes();
        _specs = session.specifications();
        _remarks = RemarkStore(widget.path)..load();
        _opening = false;
        _prepareGeometry(session);
      });
    } catch (error) {
      if (_cancel || _left || !mounted) return;
      setState(() {
        _error = error.toString();
        _opening = false;
      });
    }
  }

  /// System back and the app bar both come here. Cancel is recorded before any
  /// await so unzip, sqlite open and mesh upload all observe it. The platform
  /// view is removed in the same turn the release message is sent, otherwise
  /// the SurfaceView covers the overlay and dispose drops the channel.
  Future<void> _leave() async {
    if (_left || _closing) return;
    _cancel = true;
    _closing = true;
    _cancelExtract?.call();
    final releasing = _viewport.currentState?.release() ?? Future<void>.value();
    if (mounted) setState(() {});
    try {
      await releasing;
    } catch (_) {}
    _session?.close();
    _session = null;
    _left = true;
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  void _onTab() {
    if (_tabs.indexIsChanging) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel = true;
    _cancelExtract?.call();
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _sheet.dispose();
    _session?.close();
    super.dispose();
  }

  bool _visible(ElementInfo element) {
    if (!_filter.matches(element)) return false;
    final hits = _searchIds;
    if (hits != null && !hits.contains(element.id)) return false;
    return true;
  }

  void _onSearch(String value) {
    final session = _session;
    final trimmed = value.trim();
    final Set<int>? hits = trimmed.isEmpty || session == null
        ? null
        : session.searchIds(trimmed).toSet();
    setState(() {
      final changed = !_sameSearch(_searchIds, hits);
      _query = value;
      _searchIds = hits;
      if (hits != null) {
        _isolated.removeWhere(
          (id) => !hits.contains(id) || !_idMatchesFilter(id),
        );
        final selected = _selectedId;
        if (selected != null &&
            (!hits.contains(selected) || !_idMatchesFilter(selected))) {
          _selectedId = null;
          _xray = false;
        }
        if (hits.length == 1 && _idMatchesFilter(hits.first)) {
          _selectedId = hits.first;
          if (changed) {
            _walking = false;
            _frameToken++;
          }
        } else if (changed) {
          _walking = false;
          _fitToken++;
        }
      } else if (changed) {
        _walking = false;
        _fitToken++;
      }
      _renderRevision++;
    });
  }

  bool _sameSearch(Set<int>? a, Set<int>? b) {
    if (a == null || b == null) return a == null && b == null;
    return _sameIds(a, b);
  }

  bool _idMatchesFilter(int id) {
    for (final element in _elements) {
      if (element.id == id) return _filter.matches(element);
    }
    return false;
  }

  void _choose(int? id) {
    setState(() {
      _selectedId = id;
      if (id == null) {
        _xray = false;
      } else if (_standIns.contains(id)) {
        _xray = true;
      }
      _renderRevision++;
    });
  }

  void _onStandIns(Set<int> ids) {
    if (!mounted || _sameIds(_standIns, ids)) return;
    setState(() => _standIns = ids);
  }

  void _jumpTo(int id) {
    setState(() {
      _selectedId = id;
      _xray = true;
      _walking = false;
      _renderRevision++;
      _frameToken++;
    });
    if (_tabs.index != 0) _tabs.animateTo(0);
  }

  bool _sameIds(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final id in a) {
      if (!b.contains(id)) return false;
    }
    return true;
  }

  void _hideSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _hidden.add(id);
      _renderRevision++;
    });
  }

  void _showAll() {
    setState(() {
      _hidden.clear();
      _isolated.clear();
      _filter = const SceneFilter();
      _query = '';
      _searchIds = null;
      _xray = false;
      _section = const SectionView();
      _walking = false;
      _renderRevision++;
      _fitToken++;
    });
  }

  void _applyFilter(SceneFilter next, {VoidCallback? refresh}) {
    if (next == _filter) return;
    setState(() {
      _filter = next;
      final kept = isolateWithin(_isolated, _elements, next);
      final hits = _searchIds;
      _isolated
        ..clear()
        ..addAll(hits == null ? kept : kept.where((id) => hits.contains(id)));
      if (_selectedId != null && !_selectedMatches(next)) {
        _selectedId = null;
        _xray = false;
      }
      _renderRevision++;
      if (_walking) {
        final pose = _currentWalkPose();
        if (_walkPose == null || pose.storeyId != _walkPose!.storeyId) {
          _walkPose = pose;
          _walkToken++;
        }
      } else {
        _fitToken++;
      }
    });
    refresh?.call();
  }

  bool _selectedMatches(SceneFilter filter) {
    final id = _selectedId;
    if (id == null) return true;
    for (final element in _elements) {
      if (element.id == id) return filter.matches(element);
    }
    return false;
  }

  void _isolateSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      if (_isolated.length == 1 && _isolated.contains(id)) {
        _isolated.clear();
      } else {
        _isolated
          ..clear()
          ..add(id);
      }
      _walking = false;
      _renderRevision++;
      _fitToken++;
    });
  }

  void _toggleXray() {
    setState(() {
      _xray = !_xray;
      _renderRevision++;
    });
  }

  Future<void> _openFilter() async {
    final strings = widget.strings;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, refresh) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        strings.filterTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _filterControls(strings, refresh: () => refresh(() {})),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleSection() {
    setState(() => _section = _section.copyWith(enabled: !_section.enabled));
  }

  void _setSection(SectionView next) {
    setState(() => _section = next);
  }

  ElementInfo? get _selected {
    for (final element in _elements) {
      if (element.id == _selectedId) return element;
    }
    return null;
  }

  void _stopWalk() {
    if (!_walking) return;
    setState(() => _walking = false);
  }

  Future<RemarkViewpoint> _captureViewpoint(ElementInfo element) async {
    final camera = await _viewport.currentState?.commands?.cameraPose();
    final origin = localOriginOf(_session?.manifest ?? const {});
    if (camera != null) {
      return viewpointFromFilament(
        eye: camera.eye,
        target: camera.target,
        storeyId: _filter.storeyId,
        ifcClass: _filter.ifcClass,
        material: _filter.material,
        systemId: _filter.systemId,
        section: _section,
        hidden: _hidden.toList(),
        isolated: _isolated.toList(),
      );
    }
    ElementBox? box;
    for (final item in _boxes) {
      if (item.id == element.id && !item.degenerate) box = item;
    }
    return fallbackViewpoint(
      walk: _walking ? _walkPose : null,
      box: box,
      origin: origin,
      storeyId: _filter.storeyId,
      ifcClass: _filter.ifcClass,
      material: _filter.material,
      systemId: _filter.systemId,
      section: _section,
      hidden: _hidden.toList(),
      isolated: _isolated.toList(),
    );
  }

  void _openRemark(Remark remark) {
    final view = remark.viewpoint;
    if (view == null) return;
    setState(() {
      _filter = SceneFilter(
        storeyId: view.storeyId,
        ifcClass: view.ifcClass,
        material: view.material,
        systemId: view.systemId,
      );
      _section = view.section;
      _hidden
        ..clear()
        ..addAll(view.hidden);
      _isolated
        ..clear()
        ..addAll(view.isolated);
      _renderRevision++;
    });
    final pose = view.filament;
    _viewport.currentState?.commands?.setViewpoint(
      eye: pose.eye,
      target: pose.target,
    );
  }

  void _toggleWalk() {
    setState(() {
      if (_walking) {
        _walking = false;
        return;
      }
      _walkPose = _currentWalkPose();
      _walkToken++;
      _walking = true;
    });
  }

  SpatialNode? _walkStorey() {
    final selected = _selected;
    return walkStorey(
      spatial: _spatial,
      filterStoreyId: _filter.storeyId,
      selectedStoreyId: selected?.storeyId,
    );
  }

  WalkPose _currentWalkPose() {
    final storey = _walkStorey();
    if (storey == null) {
      return walkOnStorey(
        storeyId: 0,
        elevation: 0,
        boxes: _boxes,
        anyStorey: true,
      );
    }
    return walkOnStorey(
      storeyId: storey.id,
      elevation: storey.hasElevation ? storey.elevation : 0,
      boxes: _boxes,
    );
  }

  WalkCommand get _walkCommand {
    final pose = _walkPose;
    if (!_walking || pose == null) {
      return WalkCommand(enabled: false, token: _walkToken);
    }
    final eye = filamentWalk(
      pose,
      localOriginOf(_session?.manifest ?? const {}),
    );
    return WalkCommand(
      enabled: true,
      token: _walkToken,
      eyeX: eye.eyeX,
      eyeY: eye.eyeY,
      eyeZ: eye.eyeZ,
      lookX: eye.lookX,
      lookY: eye.lookY,
      lookZ: eye.lookZ,
    );
  }

  void _prepareGeometry(PackageSession session) {
    final blocked = meshBeforeOcct(
      formatVersion: session.formatVersion,
      rows: session.exactGeometry(),
      root: session.rootPath,
      abiSupported: androidArm64(),
    );
    if (blocked != null) {
      _geometry = blocked;
      debugPrint(blocked.logLine);
      return;
    }
    final file = firstExactFile(session.rootPath, session.exactGeometry());
    if (file == null) {
      _geometry = const GeometryDecision(
        method: GeometryMethod.mesh,
        reason: 'read',
      );
      debugPrint(_geometry!.logLine);
      return;
    }
    unawaited(_readExact(session, file));
  }

  Future<void> _readExact(PackageSession session, File file) async {
    final decision = await readExactOrMesh(file);
    if (!mounted || _session != session) return;
    setState(() => _geometry = decision);
  }

  Widget _geometryBanner(S strings) {
    final decision = _geometry;
    if (decision == null) return const SizedBox.shrink();
    return GeometryMethodBanner(
      decision: decision,
      label: strings.geometryMethod(decision.method.name, decision.reason),
    );
  }

  Widget _walkBanner(S strings) {
    final pose = _walkPose;
    final storey = _walkStorey();
    if (!_walking || pose == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            strings.walkHint(
              storey?.name.isNotEmpty == true ? storey!.name : strings.walk,
              clear: pose.clearOfSolids,
            ),
            key: const ValueKey('walk-hint'),
            maxLines: 3,
          ),
        ),
      ),
    );
  }

  Widget _modelTools(S strings) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toolButton(
                key: const ValueKey('section-toggle'),
                tooltip: strings.section,
                icon: Icons.content_cut,
                selected: _section.enabled,
                onPressed: _toggleSection,
              ),
              _toolButton(
                tooltip: strings.xray,
                icon: Icons.blur_on,
                selected: _xray,
                onPressed: _selectedId == null ? null : _toggleXray,
              ),
              _toolButton(
                tooltip: strings.isolate,
                icon: Icons.filter_center_focus,
                selected: _isolated.isNotEmpty,
                onPressed: _selectedId == null ? null : _isolateSelected,
              ),
              _toolButton(
                key: const ValueKey('filter-toggle'),
                tooltip: strings.filter,
                icon: Icons.filter_alt,
                selected: _filter.active,
                onPressed: () => unawaited(_openFilter()),
              ),
              _toolButton(
                key: const ValueKey('walk-toggle'),
                tooltip: _walking ? strings.walkStop : strings.walk,
                icon: Icons.directions_walk,
                selected: _walking,
                onPressed: _toggleWalk,
              ),
              _toolButton(
                tooltip: strings.cameraHome,
                icon: Icons.restart_alt,
                onPressed: () {
                  _stopWalk();
                  _viewport.currentState?.setCamera('iso');
                },
              ),
              PopupMenuButton<String>(
                tooltip: strings.actions,
                padding: EdgeInsets.zero,
                iconSize: 20,
                onSelected: _onToolAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'walk',
                    child: Text(_walking ? strings.walkStop : strings.walk),
                  ),
                  PopupMenuItem(value: 'fit', child: Text(strings.fitAll)),
                  PopupMenuItem(
                    value: 'fit-selected',
                    child: Text(strings.fitSelected),
                  ),
                  PopupMenuItem(value: 'hide', child: Text(strings.hide)),
                  PopupMenuItem(value: 'show', child: Text(strings.showAll)),
                  PopupMenuItem(value: 'front', child: Text(strings.viewFront)),
                  PopupMenuItem(value: 'back', child: Text(strings.viewBack)),
                  PopupMenuItem(value: 'left', child: Text(strings.viewLeft)),
                  PopupMenuItem(value: 'right', child: Text(strings.viewRight)),
                  PopupMenuItem(value: 'top', child: Text(strings.viewTop)),
                  PopupMenuItem(
                    value: 'bottom',
                    child: Text(strings.viewBottom),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onToolAction(String value) {
    final view = _viewport.currentState;
    if (value == 'walk') {
      _toggleWalk();
    } else if (value == 'fit') {
      _stopWalk();
      view?.fitAll();
    } else if (value == 'fit-selected') {
      _stopWalk();
      view?.fitSelected();
    } else if (value == 'hide') {
      _hideSelected();
    } else if (value == 'show') {
      _showAll();
    } else {
      _stopWalk();
      view?.setCamera(value);
    }
  }

  Widget _toolButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: key,
      tooltip: tooltip,
      isSelected: selected,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primary : null,
        foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    );
  }

  bool get _phoneLandscape {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.width < 1100;
  }

  Widget _title(S strings) {
    final name = _session?.summary.name ?? strings.appTitle;
    final label = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!_phoneLandscape || _session == null || _opening) return label;
    final labels = [strings.view3d, strings.tree, strings.specification];
    return Row(
      children: [
        Flexible(child: label),
        for (var i = 0; i < labels.length; i++)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _tabs.index == i
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(36, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _tabs.animateTo(i),
            child: Text(labels[i]),
          ),
      ],
    );
  }

  /// The 3D page stays mounted. A [TabBarView] would dispose the platform view,
  /// and the next visit would plan the whole scene again instead of streaming
  /// one element into it.
  Widget _pages() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _tabs.index != 0,
          child: TickerMode(
            enabled: _tabs.index == 0,
            child: _viewTab(context),
          ),
        ),
        if (_tabs.index == 1) _treeTab(context),
        if (_tabs.index == 2) _specTab(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final phoneLandscape = _phoneLandscape;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => unawaited(_leave())),
          automaticallyImplyLeading: false,
          toolbarHeight: phoneLandscape ? 48 : null,
          titleSpacing: phoneLandscape ? 0 : null,
          title: _title(strings),
          actions: const [AppearanceMenu()],
          bottom: _session == null || _opening || phoneLandscape
              ? null
              : TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: strings.view3d),
                    Tab(text: strings.tree),
                    Tab(text: strings.specification),
                  ],
                ),
        ),
        body: Stack(
          children: [
            if (!_closing)
              Positioned.fill(
                child: _error != null
                    ? Center(child: Text(_error!))
                    : _opening || _session == null
                    ? _extracting(strings)
                    : _pages(),
              ),
            if (_closing)
              const Positioned.fill(
                child: ModalBarrier(
                  dismissible: false,
                  color: Color(0x66000000),
                ),
              ),
            if (_closing)
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(strings.closingModel),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _extracting(S strings) {
    final total = _extractTotal;
    final percent = total <= 0
        ? 0
        : (100 * _extractDone / total).round().clamp(0, 100);
    final value = total <= 0 ? null : (_extractDone / total).clamp(0.0, 1.0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.extracting(percent)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value),
          ],
        ),
      ),
    );
  }

  Widget _viewTab(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final landscape = !wide && constraints.maxWidth > constraints.maxHeight;
        final selected = _selected;
        final viewport = _sectionFrame(_viewportOf(selected));
        if (wide) {
          return _wideWorkspace(context, viewport, selected);
        }
        if (landscape) {
          return _landscapeView(context, viewport, selected);
        }
        return _portraitView(context, viewport, selected);
      },
    );
  }

  Widget _wideWorkspace(
    BuildContext context,
    Widget viewport,
    ElementInfo? selected,
  ) {
    final strings = widget.strings;
    return Column(
      children: [
        _elementSearch(strings),
        _filterControls(strings),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 320, child: _tree(context)),
              Expanded(child: _tooledViewport(viewport, strings)),
              SizedBox(width: 340, child: _properties(context, selected)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _portraitView(
    BuildContext context,
    Widget viewport,
    ElementInfo? selected,
  ) {
    final strings = widget.strings;
    // The sheet paints over the full render view. Its size must not reach
    // the Filament viewport: resizing that surface is what flashed at the
    // bottom after the finger went up.
    return Stack(
      children: [
        Positioned.fill(child: viewport),
        Positioned(left: 0, right: 0, top: 4, child: _modelTools(strings)),
        if (_walking)
          Positioned(left: 8, right: 8, top: 46, child: _walkBanner(strings)),
        Positioned(
          left: 8,
          right: 8,
          top: _walking ? 96 : 46,
          child: _geometryBanner(strings),
        ),
        DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: 0.22,
          minChildSize: 0.12,
          maxChildSize: 0.88,
          snap: true,
          snapSizes: const [0.22, 0.55, 0.88],
          builder: (context, controller) {
            return Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _properties(context, selected, controller: controller),
            );
          },
        ),
      ],
    );
  }

  Widget _landscapeView(
    BuildContext context,
    Widget viewport,
    ElementInfo? selected,
  ) {
    final strings = widget.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.42)
            .clamp(220.0, 360.0)
            .toDouble();
        return Row(
          children: [
            Expanded(child: _tooledViewport(viewport, strings)),
            SizedBox(width: side, child: _properties(context, selected)),
          ],
        );
      },
    );
  }

  Widget _tooledViewport(Widget viewport, S strings) {
    return Stack(
      children: [
        Positioned.fill(child: viewport),
        Positioned(left: 0, right: 0, top: 4, child: _modelTools(strings)),
        if (_walking)
          Positioned(left: 8, right: 8, top: 46, child: _walkBanner(strings)),
        Positioned(
          left: 8,
          right: 8,
          top: _walking ? 96 : 46,
          child: _geometryBanner(strings),
        ),
      ],
    );
  }

  Widget _treeTab(BuildContext context) {
    final strings = widget.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three chip rows plus the search field leave no tree on a short
        // landscape phone. The same controls open from the filter button.
        final chips = constraints.maxHeight >= 640;
        return Column(
          children: [
            _elementSearch(strings),
            if (chips) _filterControls(strings) else _filterButton(strings),
            Expanded(child: _tree(context)),
          ],
        );
      },
    );
  }

  Widget _filterButton(S strings) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('filter-open'),
        onPressed: () => unawaited(_openFilter()),
        icon: const Icon(Icons.filter_alt),
        label: Text(_filter.active ? strings.filterTitle : strings.filter),
      ),
    );
  }

  Widget _elementSearch(S strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: _RememberedField(
        value: _query,
        hint: strings.searchHint,
        onChanged: _onSearch,
      ),
    );
  }

  Widget _filterControls(S strings, {VoidCallback? refresh}) {
    final storeys = storeysOf(_spatial);
    final classes = {..._elements.map((e) => e.ifcClass)}.toList()..sort();
    final materials = materialsOf(_elements);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (storeys.isNotEmpty)
          _chipStrip([
            _filterChip(
              key: const ValueKey('storey-all'),
              label: strings.allStoreys,
              selected: _filter.storeyId == null,
              onSelected: () => _applyFilter(
                _filter.copyWith(clearStorey: true),
                refresh: refresh,
              ),
            ),
            for (final storey in storeys)
              _filterChip(
                key: ValueKey('storey-${storey.id}'),
                label: storey.name.isEmpty ? storey.kind : storey.name,
                selected: _filter.storeyId == storey.id,
                onSelected: () => _applyFilter(
                  _filter.copyWith(storeyId: storey.id),
                  refresh: refresh,
                ),
              ),
          ]),
        _chipStrip([
          _filterChip(
            key: const ValueKey('class-all'),
            label: strings.allClasses,
            selected: _filter.ifcClass == null,
            onSelected: () => _applyFilter(
              _filter.copyWith(clearClass: true),
              refresh: refresh,
            ),
          ),
          for (final name in classes)
            _filterChip(
              key: ValueKey('class-$name'),
              label: name,
              selected: _filter.ifcClass == name,
              onSelected: () => _applyFilter(
                _filter.copyWith(ifcClass: name),
                refresh: refresh,
              ),
            ),
        ]),
        if (materials.isNotEmpty)
          _chipStrip([
            _filterChip(
              key: const ValueKey('material-all'),
              label: strings.allMaterials,
              selected: _filter.material == null,
              onSelected: () => _applyFilter(
                _filter.copyWith(clearMaterial: true),
                refresh: refresh,
              ),
            ),
            for (final name in materials)
              _filterChip(
                key: ValueKey(
                  name.isEmpty ? 'material-empty' : 'material-$name',
                ),
                label: name.isEmpty ? strings.noMaterial : name,
                selected: _filter.material == name,
                onSelected: () => _applyFilter(
                  _filter.copyWith(material: name),
                  refresh: refresh,
                ),
              ),
          ]),
        if (_systems.isNotEmpty)
          _chipStrip([
            _filterChip(
              key: const ValueKey('system-all'),
              label: strings.allSystems,
              selected: _filter.systemId == null,
              onSelected: () => _applyFilter(
                _filter.copyWith(clearSystem: true),
                refresh: refresh,
              ),
            ),
            for (final system in _systems)
              _filterChip(
                key: ValueKey('system-${system.id}'),
                label: system.name.isEmpty ? system.ifcClass : system.name,
                selected: _filter.systemId == system.id,
                onSelected: () => _applyFilter(
                  _filter.copyWith(systemId: system.id),
                  refresh: refresh,
                ),
              ),
          ]),
      ],
    );
  }

  Widget _chipStrip(List<Widget> chips) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: chips,
      ),
    );
  }

  Widget _filterChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: key,
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => onSelected(),
      ),
    );
  }

  Widget _sectionFrame(Widget viewport) {
    if (!_section.enabled) return viewport;
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait =
            constraints.maxHeight > constraints.maxWidth &&
            constraints.maxWidth < 1100;
        final sideRail =
            !portrait &&
            constraints.maxWidth > constraints.maxHeight &&
            constraints.maxHeight < 560;
        return Stack(
          children: [
            Positioned.fill(child: viewport),
            if (sideRail)
              Positioned(
                top: 48,
                right: 8,
                width: 208,
                child: _sectionPanel(widget.strings, stacked: true),
              )
            else
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: ListenableBuilder(
                  listenable: _sheet,
                  builder: (context, child) {
                    // Keep the section controls above the overlay. This does
                    // not change the render surface under the sheet.
                    final fraction = portrait && _sheet.isAttached
                        ? _sheet.size.clamp(0.0, 0.72)
                        : 0.0;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: fraction * constraints.maxHeight,
                      ),
                      child: child,
                    );
                  },
                  child: _sectionPanel(widget.strings),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _sectionPanel(S strings, {bool stacked = false}) {
    final scheme = Theme.of(context).colorScheme;
    final at = _sectionAt;
    final offsetLabel = at == null
        ? strings.sectionOffset
        : strings.sectionOffsetAt(_axisLabel(strings, _section.axis), at);
    final axisChips = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final axis in const ['x', 'y', 'z', 'view'])
          ChoiceChip(
            label: Text(_axisLabel(strings, axis), maxLines: 1),
            selected: _section.axis == axis,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => _setSection(_section.copyWith(axis: axis)),
          ),
      ],
    );
    final flipButton = IconButton(
      key: const ValueKey('section-flip'),
      tooltip: strings.sectionFlip,
      visualDensity: VisualDensity.compact,
      isSelected: _section.flip,
      color: _section.flip ? scheme.primary : null,
      onPressed: () => _setSection(_section.copyWith(flip: !_section.flip)),
      icon: const Icon(Icons.swap_horiz),
    );
    final moreButton = Builder(
      builder: (buttonContext) {
        return TextButton(
          key: const ValueKey('section-more'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => _showSectionMore(buttonContext),
          child: Text(strings.sectionMore),
        );
      },
    );
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stacked)
              axisChips
            else
              Row(
                children: [
                  Expanded(child: axisChips),
                  flipButton,
                  moreButton,
                ],
              ),
            if (stacked)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [flipButton, moreButton],
              ),
            _sectionSlider(
              offsetLabel,
              _section.offset,
              -1,
              1,
              const ValueKey('section-offset'),
              (value) => _setSection(_section.copyWith(offset: value)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSectionMore(BuildContext buttonContext) async {
    final strings = widget.strings;
    final button = buttonContext.findRenderObject() as RenderBox?;
    if (button == null || !button.attached || !mounted) return;
    final origin = button.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(320.0, screen.width - 16);
    final left = origin.dx
        .clamp(8.0, math.max(8.0, screen.width - width - 8))
        .toDouble();
    final bottom = math.max(8.0, screen.height - origin.dy + 8);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: strings.sectionMore,
      barrierColor: const Color(0x33000000),
      transitionDuration: const Duration(milliseconds: 1),
      pageBuilder: (dialogContext, _, _) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Stack(
              children: [
                Positioned(
                  left: left,
                  width: width,
                  bottom: bottom,
                  child: _sectionMoreCard(strings, setLocal),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionMoreCard(S strings, void Function(VoidCallback) setLocal) {
    final scheme = Theme.of(context).colorScheme;
    final boxSpan = _sectionBoxSpan;
    final keep = (1 - _section.inset).clamp(0.02, 1).toDouble();
    final boxLabel = boxSpan == null
        ? strings.sectionInset
        : strings.sectionBoxMetres(keep * boxSpan);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionSlider(
              strings.sectionNear,
              _section.near,
              0,
              1,
              const ValueKey('section-near'),
              (value) {
                _setSection(_section.copyWith(near: value));
                setLocal(() {});
              },
            ),
            Row(
              children: [
                Text(strings.sectionBox),
                const Spacer(),
                Switch(
                  value: _section.box,
                  onChanged: (value) {
                    _setSection(
                      _section.copyWith(
                        box: value,
                        inset: value ? _section.inset : 0,
                      ),
                    );
                    setLocal(() {});
                  },
                ),
              ],
            ),
            if (_section.box)
              _sectionSlider(
                boxLabel,
                keep,
                0.02,
                1,
                const ValueKey('section-inset'),
                (value) {
                  _setSection(_section.copyWith(inset: 1 - value));
                  setLocal(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  String _axisLabel(S strings, String axis) {
    return switch (axis) {
      'view' => strings.sectionView,
      'y' => 'Y',
      'z' => 'Z',
      _ => 'X',
    };
  }

  Widget _sectionSlider(
    String label,
    double value,
    double min,
    double max,
    Key key,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.28),
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
          ),
          child: Slider(
            key: key,
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _viewportOf(ElementInfo? selected) {
    return FilamentViewport(
      key: _viewport,
      strings: widget.strings,
      rootPath: _session?.rootPath,
      elementCount: _elements.length,
      selectedName: selected?.name,
      selectedId: _selectedId,
      hiddenIds: viewerHidden(
        elements: _elements,
        filter: _filter,
        hidden: _hidden,
        searchIds: _searchIds,
      ),
      isolatedIds: _isolated,
      xray: _xray,
      section: _section,
      renderRevision: _renderRevision,
      frameToken: _frameToken,
      fitToken: _fitToken,
      walk: _walkCommand,
      onPick: _choose,
      onStandIns: _onStandIns,
      onSectionSpan: (_, box, at) {
        if (!mounted) return;
        setState(() {
          _sectionBoxSpan = box;
          _sectionAt = at;
        });
      },
    );
  }

  Widget _tree(BuildContext context) {
    final roots = _spatial.where((node) => node.parentId == 0).toList();
    return ListView(
      children: [
        ..._standInTiles(context),
        for (final node in roots) _spatialTile(node),
        for (final element in _elements.where(
          (e) => e.parentId == 0 && _visible(e),
        ))
          _elementTile(element),
      ],
    );
  }

  List<Widget> _standInTiles(BuildContext context) {
    if (_standIns.isEmpty) return const [];
    final strings = widget.strings;
    final known = {for (final element in _elements) element.id: element};
    final ids = [
      for (final id in _standIns)
        if (_standInListed(id, known[id])) id,
    ]..sort();
    if (ids.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          strings.standIns,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(strings.standInHint),
      ),
      for (final id in ids)
        ListTile(
          minTileHeight: 48,
          leading: const Icon(Icons.crop_square, color: Color(0xFFF2741F)),
          title: Text(_elementLabel(known[id], id)),
          subtitle: Text(known[id]?.ifcClass ?? ''),
          onTap: () => _jumpTo(id),
        ),
    ];
  }

  bool _standInListed(int id, ElementInfo? element) {
    if (element != null) return _visible(element);
    if (_filter.active) return false;
    final hits = _searchIds;
    return hits == null || hits.contains(id);
  }

  String _elementLabel(ElementInfo? element, int id) {
    if (element == null) return '$id';
    if (element.name.isNotEmpty) return element.name;
    if (element.ifcClass.isNotEmpty) return element.ifcClass;
    return '$id';
  }

  Widget _spatialTile(SpatialNode node) {
    final children = _spatial.where((item) => item.parentId == node.id);
    final elements = _elements.where(
      (item) => item.parentId == node.id && _visible(item),
    );
    return ExpansionTile(
      initiallyExpanded: _elements.length <= 200,
      title: Text(node.name.isEmpty ? node.kind : node.name),
      subtitle: Text(node.kind),
      children: [
        for (final child in children) _spatialTile(child),
        for (final element in elements) _elementTile(element),
      ],
    );
  }

  Widget _elementTile(ElementInfo element) {
    final selected = element.id == _selectedId;
    return ListTile(
      minTileHeight: 48,
      selected: selected,
      title: Text(element.name.isEmpty ? element.ifcClass : element.name),
      subtitle: Text(element.ifcClass),
      onTap: () => _choose(element.id),
    );
  }

  Widget _properties(
    BuildContext context,
    ElementInfo? element, {
    ScrollController? controller,
  }) {
    final strings = widget.strings;
    if (element == null || _session == null) {
      return CustomScrollView(
        controller: controller,
        slivers: [
          if (controller != null) _sheetHandle(),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(strings.noSelection)),
          ),
        ],
      );
    }
    final props = _session!.props(element.id);
    final quantities = _session!.quantities(element.id);
    final classes = _session!.classes(element.id);
    final query = _propQuery.trim().toLowerCase();
    bool hit(String name, String group, String value) {
      if (query.isEmpty) return true;
      return name.toLowerCase().contains(query) ||
          group.toLowerCase().contains(query) ||
          value.toLowerCase().contains(query);
    }

    final groups = <String, List<Widget>>{};
    for (final prop in props) {
      final value = _displayValue(prop.valueText);
      final group = prop.pset.isEmpty ? strings.properties : prop.pset;
      if (!hit(prop.name, group, value)) continue;
      groups.putIfAbsent(group, () => []).add(_valueRow(prop.name, value));
    }
    final quantityRows = <Widget>[
      for (final quantity in quantities)
        if (hit(quantity.name, quantity.qset, _displayQuantity(quantity)))
          _valueRow(quantity.name, _displayQuantity(quantity)),
    ];
    final classRows = <Widget>[
      for (final item in classes)
        if (hit(item.code, item.system, item.title))
          _valueRow(item.code, item.title, detail: item.system),
    ];
    return SelectionArea(
      child: CustomScrollView(
        controller: controller,
        slivers: [
          if (controller != null) _sheetHandle(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.properties,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    element.name.isEmpty ? element.ifcClass : element.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (element.name.isNotEmpty && element.ifcClass.isNotEmpty)
                    Text(element.ifcClass),
                  const SizedBox(height: 8),
                  _RememberedField(
                    value: _propQuery,
                    hint: strings.propertySearch,
                    dense: true,
                    onChanged: (value) => setState(() => _propQuery = value),
                  ),
                  const SizedBox(height: 8),
                  Text(element.guid),
                  if (element.tag.isNotEmpty) Text(element.tag),
                  if (element.typeName.isNotEmpty) Text(element.typeName),
                  if (element.material.isNotEmpty) Text(element.material),
                ],
              ),
            ),
          ),
          for (final entry in groups.entries) ..._group(entry.key, entry.value),
          if (quantityRows.isNotEmpty)
            ..._group(strings.quantities, quantityRows),
          if (classRows.isNotEmpty)
            ..._group(strings.classification, classRows),
          if (_remarks != null)
            SliverToBoxAdapter(
              child: RemarksSection(
                strings: strings,
                store: _remarks!,
                element: element,
                guidToElement: {
                  for (final item in _elements)
                    if (item.guid.isNotEmpty) item.guid: item.id,
                },
                onChanged: () => setState(() {}),
                captureViewpoint: () => _captureViewpoint(element),
                onOpen: _openRemark,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _sheetHandle() {
    return SliverToBoxAdapter(
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  List<Widget> _group(String title, List<Widget> rows) {
    final expanded = !_collapsedGroups.contains(title);
    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _GroupHeader(
          title: title,
          expanded: expanded,
          onTap: () {
            setState(() {
              if (expanded) {
                _collapsedGroups.add(title);
              } else {
                _collapsedGroups.remove(title);
              }
            });
          },
        ),
      ),
      if (expanded) SliverList(delegate: SliverChildListDelegate(rows)),
    ];
  }

  Widget _valueRow(String name, String value, {String? detail}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name),
          if (detail != null && detail.isNotEmpty)
            Text(detail, style: theme.textTheme.bodySmall),
          Text(value),
        ],
      ),
    );
  }

  String _displayValue(String value) {
    if (value == 'true') return widget.strings.yes;
    if (value == 'false') return widget.strings.no;
    return value;
  }

  String _displayQuantity(QuantityInfo quantity) {
    if (quantity.kind == 'Length' || quantity.unit == 'm') {
      return widget.strings.lengthMm(quantity.value);
    }
    if (quantity.unit == 'm2') return '${quantity.value} м²';
    if (quantity.unit == 'm3') return '${quantity.value} м³';
    return '${quantity.value} ${quantity.unit}';
  }

  Widget _specTab(BuildContext context) {
    final strings = widget.strings;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _exportCsv,
              icon: const Icon(Icons.download_outlined),
              label: Text(strings.exportCsv),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final row in _specs)
                ListTile(
                  minTileHeight: 48,
                  title: Text('${row.ifcClass}  ${row.typeName}'.trim()),
                  subtitle: Text('${row.storeyName}  ${row.material}'.trim()),
                  trailing: Text(
                    row.quantityKind.isEmpty
                        ? '${row.elementCount}'
                        : '${row.quantityKind}: ${row.quantitySum}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportCsv() async {
    final csv = specCsv(_specs);
    final name = csvFileName(_session?.summary.name ?? '');
    if (Platform.isAndroid) {
      try {
        final saved = await PackageImport.saveCsv(name: name, text: csv);
        if (!mounted || saved == null || saved.isEmpty) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(saved)));
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    final directory = await showDialog<String>(
      context: context,
      builder: (context) => _CsvFolderDialog(strings: widget.strings),
    );
    if (!mounted || directory == null || directory.trim().isEmpty) return;
    try {
      final file = writeSpecCsv(
        directory: directory.trim(),
        modelName: _session?.summary.name ?? '',
        csv: csv,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(file.path)));
    } on CsvSaveException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _GroupHeader extends SliverPersistentHeaderDelegate {
  _GroupHeader({
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_GroupHeader oldDelegate) {
    return oldDelegate.title != title || oldDelegate.expanded != expanded;
  }
}

/// Keeps typed text when the field is recreated, including across rotation.
/// The parent string is the source of truth. Two fields cannot share one
/// controller, because the wide layout mounts the tree search and the 3D page
/// at the same time.
class _RememberedField extends StatefulWidget {
  const _RememberedField({
    required this.value,
    required this.hint,
    required this.onChanged,
    this.dense = false,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool dense;

  @override
  State<_RememberedField> createState() => _RememberedFieldState();
}

class _RememberedFieldState extends State<_RememberedField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_RememberedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        isDense: widget.dense,
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _CsvFolderDialog extends StatefulWidget {
  const _CsvFolderDialog({required this.strings});

  final S strings;

  @override
  State<_CsvFolderDialog> createState() => _CsvFolderDialogState();
}

class _CsvFolderDialogState extends State<_CsvFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(String? value) {
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.exportCsv),
      content: TextField(
        key: const ValueKey('csv-folder'),
        controller: _controller,
        decoration: InputDecoration(hintText: widget.strings.csvFolder),
        onSubmitted: _close,
      ),
      actions: [
        TextButton(
          onPressed: () => _close(null),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: () => _close(_controller.text),
          child: Text(widget.strings.csvSave),
        ),
      ],
    );
  }
}
