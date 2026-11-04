import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'filament_channel.dart';
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
  final _portraitKey = GlobalKey();
  final _sheet = DraggableScrollableController();
  double _fitBottomInset = 0;
  int _insetTries = 0;
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
    if (stack == null || stack <= 1) {
      // The sheet is not laid out yet. Try the next frames, then stop.
      if (_portraitKey.currentContext != null && _insetTries < 8) {
        _insetTries++;
        _scheduleFitInset(null);
      }
      return;
    }
    _insetTries = 0;
    final sheet = _sheet.isAttached ? _sheet.size : 0.22;
    final overlap = (sheet * stack).clamp(0.0, stack);
    _pushFitInset(overlap / stack);
  }

  void _pushFitInset(double inset) {
    final next = inset.clamp(0.0, 0.72);
    if ((next - _fitBottomInset).abs() < 0.015) return;
    setState(() => _fitBottomInset = next);
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
      _section = const SectionView();
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
                tooltip: strings.cameraHome,
                icon: Icons.restart_alt,
                onPressed: () => _viewport.currentState?.setCamera('iso'),
              ),
              PopupMenuButton<String>(
                tooltip: strings.actions,
                padding: EdgeInsets.zero,
                iconSize: 20,
                onSelected: _onToolAction,
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'fit', child: Text(strings.fitAll)),
                  PopupMenuItem(value: 'fit-selected', child: Text(strings.fitSelected)),
                  PopupMenuItem(value: 'hide', child: Text(strings.hide)),
                  PopupMenuItem(value: 'show', child: Text(strings.showAll)),
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
        ),
      ),
    );
  }

  void _onToolAction(String value) {
    final view = _viewport.currentState;
    if (value == 'fit') {
      view?.fitAll();
    } else if (value == 'fit-selected') {
      view?.fitSelected();
    } else if (value == 'hide') {
      _hideSelected();
    } else if (value == 'show') {
      _showAll();
    } else {
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
    _scheduleFitInset(null);
    return Stack(
      key: _portraitKey,
      children: [
        Positioned.fill(child: viewport),
        Positioned(left: 0, right: 0, top: 4, child: _modelTools(strings)),
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
      ],
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

  Widget _sectionFrame(Widget viewport) {
    if (!_section.enabled) return viewport;
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight > constraints.maxWidth &&
            constraints.maxWidth < 1100;
        final sideRail = !portrait &&
            constraints.maxWidth > constraints.maxHeight &&
            constraints.maxHeight < 560;
        final lift = portrait ? _fitBottomInset * constraints.maxHeight : 0.0;
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
                bottom: 8 + lift,
                child: _sectionPanel(widget.strings),
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
    final left = origin.dx.clamp(8.0, math.max(8.0, screen.width - width - 8)).toDouble();
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
                      _section.copyWith(box: value, inset: value ? _section.inset : 0),
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
            inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28),
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
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
      hiddenIds: _hidden,
      isolatedIds: _isolated,
      xray: _xray,
      section: _section,
      renderRevision: _renderRevision,
      frameToken: _frameToken,
      bottomInset: _fitBottomInset,
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
