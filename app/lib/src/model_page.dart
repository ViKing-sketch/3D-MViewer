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

class _ModelPageState extends State<ModelPage> with SingleTickerProviderStateMixin {
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
  final _viewport = GlobalKey<FilamentViewportState>();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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

  @override
  void dispose() {
    _tabs.dispose();
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
      _renderRevision++;
    });
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
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton(onPressed: () => _viewport.currentState?.fitAll(), child: Text(strings.fitAll)),
          TextButton(onPressed: () => _viewport.currentState?.fitSelected(), child: Text(strings.fitSelected)),
          TextButton(onPressed: _hideSelected, child: Text(strings.hide)),
          TextButton(onPressed: _showAll, child: Text(strings.showAll)),
          TextButton(onPressed: _isolateSelected, child: Text(strings.isolate)),
          TextButton(onPressed: _toggleXray, child: Text(strings.xray)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('front'), child: Text(strings.viewFront)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('back'), child: Text(strings.viewBack)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('left'), child: Text(strings.viewLeft)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('right'), child: Text(strings.viewRight)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('top'), child: Text(strings.viewTop)),
          TextButton(onPressed: () => _viewport.currentState?.setCamera('bottom'), child: Text(strings.viewBottom)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(_session?.summary.name ?? strings.appTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: strings.library),
            Tab(text: strings.specification),
          ],
        ),
      ),
      floatingActionButton: const AppearanceButtons(tag: 'model'),
      body: _error != null
          ? Center(child: Text(_error!))
          : _session == null
              ? const SizedBox.shrink()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _modelTab(context),
                    _specTab(context),
                  ],
                ),
    );
  }

  Widget _modelTab(BuildContext context) {
    final strings = widget.strings;
    final classes = {..._elements.map((e) => e.ifcClass)}.toList()..sort();
    final selected = _selected;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: strings.searchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SizedBox(
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
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              // The default widget surface leaves about 370px here. A 320px
              // view plus the property pane overflows that and the tree never
              // lays out. Short windows keep the original 96px slot.
              final short = !wide && constraints.maxHeight < 520;
              final filament = FilamentViewport(
                key: _viewport,
                strings: strings,
                rootPath: _session?.rootPath,
                elementCount: _elements.length,
                selectedName: selected?.name,
                selectedId: _selectedId,
                hiddenIds: _hidden,
                isolatedIds: _isolated,
                xray: _xray,
                renderRevision: _renderRevision,
                onPick: _choose,
              );
              final viewport = short
                  ? Stack(
                      children: [
                        Positioned.fill(child: filament),
                        Positioned(left: 0, right: 0, bottom: 0, child: _renderBar(strings)),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: filament),
                        _renderBar(strings),
                      ],
                    );
              final tree = _tree(context);
              final props = _properties(context, selected);
              if (wide) {
                return Row(
                  children: [
                    SizedBox(width: 320, child: tree),
                    Expanded(child: viewport),
                    SizedBox(width: 340, child: props),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(height: short ? 96 : 320, child: viewport),
                  Expanded(child: tree),
                  SizedBox(height: 160, child: props),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tree(BuildContext context) {
    final roots = _spatial.where((node) => node.parentId == 0).toList();
    return ListView(
      children: [
        for (final node in roots) _spatialTile(node),
        for (final element in _elements.where((e) => e.parentId == 0 && _visible(e)))
          _elementTile(element),
      ],
    );
  }

  Widget _spatialTile(SpatialNode node) {
    final children = _spatial.where((item) => item.parentId == node.id);
    final elements = _elements.where((item) => item.parentId == node.id && _visible(item));
    return ExpansionTile(
      initiallyExpanded: true,
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

  Widget _properties(BuildContext context, ElementInfo? element) {
    final strings = widget.strings;
    if (element == null || _session == null) {
      return Center(child: Text(strings.noSelection));
    }
    final props = _session!.props(element.id);
    final quantities = _session!.quantities(element.id);
    final classes = _session!.classes(element.id);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(strings.properties, style: Theme.of(context).textTheme.titleMedium),
        Text(element.guid),
        if (element.tag.isNotEmpty) Text(element.tag),
        if (element.typeName.isNotEmpty) Text(element.typeName),
        if (element.material.isNotEmpty) Text(element.material),
        const Divider(),
        for (final prop in props)
          ListTile(
            minTileHeight: 48,
            title: Text(prop.name),
            subtitle: Text(prop.pset),
            trailing: Text(_displayValue(prop.valueText)),
          ),
        if (quantities.isNotEmpty) ...[
          Text(strings.quantities, style: Theme.of(context).textTheme.titleMedium),
          for (final quantity in quantities)
            ListTile(
              minTileHeight: 48,
              title: Text(quantity.name),
              subtitle: Text(quantity.qset),
              trailing: Text(_displayQuantity(quantity)),
            ),
        ],
        if (classes.isNotEmpty) ...[
          Text(strings.classification, style: Theme.of(context).textTheme.titleMedium),
          for (final item in classes)
            ListTile(
              minTileHeight: 48,
              title: Text(item.code),
              subtitle: Text(item.system),
              trailing: Text(item.title),
            ),
        ],
      ],
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(file.path)));
  }
}
