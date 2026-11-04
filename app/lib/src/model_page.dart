import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'filament_viewport.dart';
import 'model.dart';
import 'package_session.dart';
import 'strings.dart';

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
  List<SpatialNode> _spatial = const [];
  List<ElementInfo> _elements = const [];
  List<SpecRow> _specs = const [];
  String? _error;
  int? _selectedId;
  String _query = '';
  String? _classFilter;
  final Set<int> _hidden = {};
  final Set<int> _isolated = {};
  bool _xray = false;
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
  final _portraitKey = GlobalKey();
  final _renderBarKey = GlobalKey();
  final _sheet = DraggableScrollableController();
  double _fitBottomInset = 0;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTab);
    _sheet.addListener(_syncFitInset);
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
      _elements = session.elements();
      _specs = session.specifications();
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
        _elements = session.elements();
        _specs = session.specifications();
        _opening = false;
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
    _sheet.removeListener(_syncFitInset);
    _sheet.dispose();
    _session?.close();
    super.dispose();
  }

  bool _visible(ElementInfo element) {
    if (_classFilter != null && element.ifcClass != _classFilter) return false;
    if (_query.trim().isEmpty) return true;
    final query = _query.trim().toLowerCase();
    return element.name.toLowerCase().contains(query) ||
        element.tag.toLowerCase().contains(query) ||
        element.guid.toLowerCase().contains(query) ||
        element.ifcClass.toLowerCase().contains(query);
  }

  void _choose(int? id) {
    setState(() {
      _selectedId = id;
      if (id != null && _standIns.contains(id)) _xray = true;
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
      _renderRevision++;
      _frameToken++;
    });
    if (_tabs.index != 0) _tabs.animateTo(0);
  }

  void _scheduleFitInset(double? forced) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (forced != null) {
        _pushFitInset(forced);
        return;
      }
      _syncFitInset();
    });
  }

  void _syncFitInset() {
    final stack = _portraitKey.currentContext?.size?.height;
    final bar = _renderBarKey.currentContext?.size?.height ?? 0;
    if (stack == null || stack <= bar + 1) return;
    final sheet = _sheet.isAttached ? _sheet.size : 0.22;
    final overlap = (sheet * stack).clamp(0.0, stack - bar);
    _pushFitInset(overlap / (stack - bar));
  }

  void _pushFitInset(double inset) {
    final next = inset.clamp(0.0, 0.72);
    if ((next - _fitBottomInset).abs() < 0.015) return;
    _fitBottomInset = next;
    _viewport.currentState?.setFitInset(next);
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
      _xray = false;
      _renderRevision++;
    });
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
      _renderRevision++;
    });
  }

  void _toggleXray() {
    setState(() {
      _xray = !_xray;
      _renderRevision++;
    });
  }

  ElementInfo? get _selected {
    for (final element in _elements) {
      if (element.id == _selectedId) return element;
    }
    return null;
  }

  Widget _renderBar(S strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Wrap(
        spacing: 4,
        runSpacing: 0,
        children: [
          TextButton(
            onPressed: () => _viewport.currentState?.fitAll(),
            child: Text(strings.fitAll),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.fitSelected(),
            child: Text(strings.fitSelected),
          ),
          TextButton(onPressed: _hideSelected, child: Text(strings.hide)),
          TextButton(onPressed: _showAll, child: Text(strings.showAll)),
          TextButton(onPressed: _isolateSelected, child: Text(strings.isolate)),
          Tooltip(
            message: strings.xrayHint,
            child: TextButton(
              onPressed: _toggleXray,
              child: Text(strings.xray),
            ),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('front'),
            child: Text(strings.viewFront),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('back'),
            child: Text(strings.viewBack),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('left'),
            child: Text(strings.viewLeft),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('right'),
            child: Text(strings.viewRight),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('top'),
            child: Text(strings.viewTop),
          ),
          TextButton(
            onPressed: () => _viewport.currentState?.setCamera('bottom'),
            child: Text(strings.viewBottom),
          ),
        ],
      ),
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
        final viewport = _viewportOf(selected);
        if (wide) {
          _scheduleFitInset(0);
          return _wideWorkspace(context, viewport, selected);
        }
        if (landscape) {
          _scheduleFitInset(0);
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
        _classChips(strings),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 320, child: _tree(context)),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: viewport),
                    _renderBar(strings),
                  ],
                ),
              ),
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
    _scheduleFitInset(null);
    return Stack(
      key: _portraitKey,
      children: [
        Column(
          children: [
            KeyedSubtree(key: _renderBarKey, child: _renderBar(strings)),
            Expanded(child: viewport),
          ],
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
            _cameraRail(strings),
            Expanded(child: viewport),
            SizedBox(width: side, child: _properties(context, selected)),
          ],
        );
      },
    );
  }

  Widget _cameraRail(S strings) {
    final style = IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return SizedBox(
      width: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          IconButton(
            tooltip: strings.fitAll,
            style: style,
            onPressed: () => _viewport.currentState?.fitAll(),
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            tooltip: strings.fitSelected,
            style: style,
            onPressed: () => _viewport.currentState?.fitSelected(),
            icon: const Icon(Icons.center_focus_strong),
          ),
          IconButton(
            tooltip: strings.hide,
            style: style,
            onPressed: _hideSelected,
            icon: const Icon(Icons.visibility_off_outlined),
          ),
          IconButton(
            tooltip: strings.showAll,
            style: style,
            onPressed: _showAll,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: strings.isolate,
            style: style,
            onPressed: _isolateSelected,
            icon: const Icon(Icons.filter_center_focus),
          ),
          IconButton(
            tooltip: strings.xrayHint,
            style: style,
            onPressed: _toggleXray,
            icon: const Icon(Icons.blur_on),
          ),
          PopupMenuButton<String>(
            tooltip: strings.cameraViews,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.videocam_outlined),
            onSelected: (preset) => _viewport.currentState?.setCamera(preset),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'front', child: Text(strings.viewFront)),
              PopupMenuItem(value: 'back', child: Text(strings.viewBack)),
              PopupMenuItem(value: 'left', child: Text(strings.viewLeft)),
              PopupMenuItem(value: 'right', child: Text(strings.viewRight)),
              PopupMenuItem(value: 'top', child: Text(strings.viewTop)),
              PopupMenuItem(value: 'bottom', child: Text(strings.viewBottom)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _treeTab(BuildContext context) {
    final strings = widget.strings;
    return Column(
      children: [
        _elementSearch(strings),
        _classChips(strings),
        Expanded(child: _tree(context)),
      ],
    );
  }

  Widget _elementSearch(S strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: _RememberedField(
        value: _query,
        hint: strings.searchHint,
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _classChips(S strings) {
    final classes = {..._elements.map((e) => e.ifcClass)}.toList()..sort();
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(strings.allClasses),
              selected: _classFilter == null,
              onSelected: (_) => setState(() => _classFilter = null),
            ),
          ),
          for (final name in classes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(name),
                selected: _classFilter == name,
                onSelected: (_) => setState(() => _classFilter = name),
              ),
            ),
        ],
      ),
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
      hiddenIds: _hidden,
      isolatedIds: _isolated,
      xray: _xray,
      renderRevision: _renderRevision,
      frameToken: _frameToken,
      onPick: _choose,
      onStandIns: _onStandIns,
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
    final ids = _standIns.toList()..sort();
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
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}fbv-spec-${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(specCsv(_specs));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(file.path)));
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
