import 'dart:async';

import 'package:flutter/material.dart';

import 'named_views.dart';
import 'remarks.dart';
import 'strings.dart';

class NamedViewsSection extends StatefulWidget {
  const NamedViewsSection({
    super.key,
    required this.strings,
    required this.store,
    required this.xray,
    required this.capture,
    required this.onOpen,
    required this.onChanged,
  });

  final S strings;
  final NamedViewStore store;
  final bool xray;
  final Future<RemarkViewpoint> Function() capture;
  final void Function(NamedView view) onOpen;
  final VoidCallback onChanged;

  @override
  State<NamedViewsSection> createState() => _NamedViewsSectionState();
}

class _NamedViewsSectionState extends State<NamedViewsSection> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final viewpoint = await widget.capture();
      widget.store.add(
        name: _name.text,
        viewpoint: viewpoint,
        xray: widget.xray,
      );
      _name.clear();
      if (!mounted) return;
      setState(() => _error = null);
      widget.onChanged();
    } on NamedViewNameException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.empty
            ? widget.strings.savedViewEmpty
            : widget.strings.savedViewLong;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  void _delete(String id) {
    widget.store.remove(id);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.savedViewsHint, style: theme.textTheme.bodySmall),
        if (widget.store.loadError != null) ...[
          const SizedBox(height: 8),
          Text(widget.store.loadError!),
        ],
        const SizedBox(height: 8),
        TextField(
          key: const Key('named-view-name'),
          controller: _name,
          decoration: InputDecoration(
            hintText: strings.savedViewName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => unawaited(_save()),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('named-view-save'),
          onPressed: _save,
          child: Text(strings.saveView),
        ),
        if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
        const SizedBox(height: 8),
        if (widget.store.views.isEmpty)
          Text(strings.noSavedViews)
        else
          for (final view in widget.store.views)
            ListTile(
              key: ValueKey('named-view-${view.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(view.name),
              subtitle: Text(view.createdUtc),
              onTap: () => widget.onOpen(view),
              trailing: IconButton(
                key: ValueKey('named-view-delete-${view.id}'),
                tooltip: strings.delete,
                onPressed: () => _delete(view.id),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
      ],
    );
  }
}
