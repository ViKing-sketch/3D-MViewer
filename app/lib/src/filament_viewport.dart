import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'filament_channel.dart';
import 'strings.dart';
import 'walk_pose.dart';

/// Filament platform view on Android. Other targets keep the layout slot.
///
/// Channel and view type are `fbv/filament`, as described in docs/rendering.md.
/// The native view loads `mesh/lod0.glb` and any `mesh/elements/<id>.glb` that
/// is not already in that scene, and maps picks through `extras.elementId`.
class FilamentViewport extends StatefulWidget {
  const FilamentViewport({
    super.key,
    required this.strings,
    required this.elementCount,
    required this.selectedName,
    this.rootPath,
    this.selectedId,
    this.hiddenIds = const {},
    this.isolatedIds = const {},
    this.xray = false,
    this.section = const SectionView(),
    this.renderRevision = 0,
    this.frameToken = 0,
    this.fitToken = 0,
    this.walk = const WalkCommand(enabled: false, token: 0),
    this.bottomInset = 0,
    this.onPick,
    this.onStatus,
    this.onStandIns,
    this.onSectionSpan,
  });

  final S strings;
  final int elementCount;
  final String? selectedName;
  final String? rootPath;
  final int? selectedId;
  final Set<int> hiddenIds;
  final Set<int> isolatedIds;
  final bool xray;
  final SectionView section;
  final int renderRevision;
  final int frameToken;

  /// Bumped when the visible set changes and the camera should frame it.
  final int fitToken;

  /// Orbit, or a first-person pose on one storey.
  final WalkCommand walk;

  /// Fraction of this view covered from the bottom. The portrait sheet does
  /// not set this: the sheet is an overlay and the surface stays full size.
  final double bottomInset;
  final ValueChanged<int?>? onPick;
  final ValueChanged<String>? onStatus;
  final ValueChanged<Set<int>>? onStandIns;
  final void Function(double half, double box, double at)? onSectionSpan;

  @override
  State<FilamentViewport> createState() => FilamentViewportState();
}

class FilamentViewportState extends State<FilamentViewport> {
  FilamentCommands? get commands => _commands;
  FilamentCommands? _commands;
  String? _status;
  String? _statusCode;
  int _appliedFrame = 0;
  int _appliedFit = 0;

  Future<void> fitAll() =>
      _commands?.fit(selected: false) ?? Future<void>.value();

  Future<void> fitSelected() =>
      _commands?.fit(selected: true) ?? Future<void>.value();

  Future<void> setCamera(String preset) =>
      _commands?.setCamera(preset) ?? Future<void>.value();

  Future<void> setFitInset(double bottom) =>
      _commands?.setFitInset(bottom) ?? Future<void>.value();

  Future<void> release() => _commands?.release() ?? Future<void>.value();

  @override
  void didUpdateWidget(FilamentViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderRevision != widget.renderRevision ||
        oldWidget.selectedId != widget.selectedId ||
        oldWidget.frameToken != widget.frameToken ||
        oldWidget.fitToken != widget.fitToken) {
      _pushState();
    }
    if ((oldWidget.bottomInset - widget.bottomInset).abs() > 0.001) {
      _commands?.setFitInset(widget.bottomInset);
    }
    if (oldWidget.section != widget.section) _pushSection();
    if (oldWidget.walk != widget.walk) _pushWalk();
    if (oldWidget.rootPath != widget.rootPath && widget.rootPath != null) {
      _commands?.load(widget.rootPath!);
    }
  }

  Future<void> _onCreated(int id) async {
    final channel = MethodChannel('fbv/filament/$id');
    final commands = FilamentCommands(channel);
    _commands = commands;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPick') {
        final args = call.arguments;
        final raw = args is Map ? args['elementId'] : null;
        final picked = raw is num ? raw.toInt() : 0;
        widget.onPick?.call(picked == 0 ? null : picked);
      } else if (call.method == 'onStatus') {
        final args = call.arguments;
        if (args is Map) _applyStatus(args);
      } else if (call.method == 'onSection') {
        final args = call.arguments;
        if (args is Map) {
          final half = args['half'];
          final box = args['box'];
          if (half is num && box is num) {
            final at = args['at'];
            widget.onSectionSpan?.call(
              half.toDouble(),
              box.toDouble(),
              at is num ? at.toDouble() : 0,
            );
          }
        }
      }
      return null;
    });
    final existing = await commands.sync();
    if (existing != null && mounted) _applyStatus(existing);
    // The sheet height is known before the mesh plan finishes. Send it before
    // load so the first frame is not inset=0, and again from didUpdateWidget
    // if layout measures a different collapsed height.
    await commands.setFitInset(widget.bottomInset);
    if (widget.rootPath != null) await commands.load(widget.rootPath!);
    await _pushState();
    await _pushSection();
    await _pushWalk();
  }

  void _applyStatus(Map<dynamic, dynamic> raw) {
    final listed = raw['standIns'];
    if (listed is List) {
      final ids = <int>{
        for (final item in listed)
          if (item is num) item.toInt(),
      };
      widget.onStandIns?.call(ids);
    }
    final code = raw['code']?.toString() ?? '';
    final strings = widget.strings;
    final String text;
    if (code == 'loading') {
      final loaded = (raw['loaded'] as num?)?.toInt() ?? 0;
      final total = (raw['total'] as num?)?.toInt() ?? 0;
      text = total > 0
          ? strings.meshProgress(loaded, total)
          : strings.loadingMesh;
    } else if (code == 'ready') {
      text = strings.meshReady(
        lod0: raw['lod0'] == true,
        elementFiles: (raw['elementFiles'] as num?)?.toInt() ?? 0,
        drawn: (raw['drawn'] as num?)?.toInt() ?? 0,
        partial: raw['partial'] == true,
        boxes: (raw['boxes'] as num?)?.toInt() ?? 0,
      );
    } else {
      text = raw['message']?.toString() ?? code;
    }
    setState(() {
      _statusCode = code;
      _status = text;
    });
    widget.onStatus?.call(text);
  }

  Future<void> _pushState() async {
    final commands = _commands;
    if (commands == null) return;
    final frame = widget.frameToken != _appliedFrame;
    _appliedFrame = widget.frameToken;
    final fit = widget.fitToken;
    final shouldFit = fit != _appliedFit && fit != 0;
    _appliedFit = fit;
    await commands.setViewState(
      selectedId: widget.selectedId,
      hidden: widget.hiddenIds.toList(),
      isolated: widget.isolatedIds.toList(),
      xray: widget.xray,
      frame: frame,
    );
    if (shouldFit) await commands.fit(selected: false);
  }

  Future<void> _pushSection() async {
    final commands = _commands;
    if (commands == null) return;
    await commands.setSection(widget.section);
  }

  Future<void> _pushWalk() async {
    final commands = _commands;
    if (commands == null) return;
    await commands.setNavigation(widget.walk);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || widget.rootPath == null) {
      return _Fallback(
        strings: widget.strings,
        elementCount: widget.elementCount,
        selectedName: widget.selectedName,
      );
    }
    final showStatus =
        _status != null && _statusCode != 'ready' && _statusCode != 'idle';
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(child: _platformView(context)),
        if (showStatus)
          Positioned(
            left: 8,
            right: 8,
            top: 48,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      _status!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _platformView(BuildContext context) {
    final gestures = <Factory<OneSequenceGestureRecognizer>>{
      Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
    };
    return PlatformViewLink(
      viewType: 'fbv/filament',
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: gestures,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final created = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: 'fbv/filament',
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParams: {'root': widget.rootPath},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        created.addOnPlatformViewCreatedListener((id) {
          params.onPlatformViewCreated(id);
          _onCreated(id);
        });
        return created..create();
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.strings,
    required this.elementCount,
    required this.selectedName,
  });

  final S strings;
  final int elementCount;
  final String? selectedName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 36, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              strings.renderStub,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${strings.elements}: $elementCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (selectedName != null)
              Text(
                selectedName!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
          ],
        ),
      ),
    );
  }
}
