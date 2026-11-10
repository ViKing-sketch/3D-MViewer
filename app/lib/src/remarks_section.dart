import 'dart:io';

import 'package:flutter/material.dart';

import 'model.dart';
import 'remarks.dart';
import 'strings.dart';

class RemarksSection extends StatefulWidget {
  const RemarksSection({
    super.key,
    required this.strings,
    required this.store,
    required this.element,
    required this.guidToElement,
    required this.onChanged,
    this.captureViewpoint,
    this.onOpen,
  });

  final S strings;
  final RemarkStore store;
  final ElementInfo element;
  final Map<String, int> guidToElement;
  final VoidCallback onChanged;

  /// Current camera and filters. Null in a test that only writes text.
  final Future<RemarkViewpoint?> Function()? captureViewpoint;

  /// Applies a saved viewpoint. Null when the host has nowhere to put it.
  final void Function(Remark remark)? onOpen;

  @override
  State<RemarksSection> createState() => _RemarksSectionState();
}

class _RemarksSectionState extends State<RemarksSection> {
  final _text = TextEditingController();
  final _photo = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _photo.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      final viewpoint = await widget.captureViewpoint?.call();
      widget.store.add(
        elementId: widget.element.id,
        guid: widget.element.guid,
        text: _text.text,
        photoSource: _photo.text,
        viewpoint: viewpoint,
      );
      _text.clear();
      _photo.clear();
      setState(() => _error = null);
      widget.onChanged();
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _exchange(bool exporting) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => _BcfPathDialog(strings: widget.strings),
    );
    if (path == null || path.trim().isEmpty) return;
    try {
      if (exporting) {
        widget.store.exportBcf(path.trim());
      } else {
        widget.store.importBcf(path.trim(), widget.guidToElement);
      }
      if (!mounted) return;
      setState(() => _error = null);
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final rows = widget.store.forElement(
      widget.element.id,
      widget.element.guid,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.remarks, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(strings.remarksLocal),
          if (widget.store.loadError != null) Text(widget.store.loadError!),
          if (widget.store.unmatched > 0)
            Text(strings.unmatchedRemarks(widget.store.unmatched)),
          const SizedBox(height: 8),
          if (rows.isEmpty) Text(strings.noRemarks),
          for (final remark in rows) ...[
            Text(remark.text),
            Text(remark.createdUtc),
            if (remark.photoName != null &&
                File(
                  '${widget.store.folderPath}/${remark.photoName}',
                ).existsSync())
              Text(strings.remarkHasPhoto),
            if (remark.viewpoint != null)
              TextButton(
                onPressed: () => widget.onOpen?.call(remark),
                child: Text(strings.showViewpoint),
              ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('remark-text'),
            controller: _text,
            decoration: InputDecoration(
              hintText: strings.remarkHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('remark-photo'),
            controller: _photo,
            decoration: InputDecoration(
              hintText: strings.remarkPhoto,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _add, child: Text(strings.addRemark)),
              FilledButton.tonal(
                onPressed: () => _exchange(true),
                child: Text(strings.exportBcf),
              ),
              FilledButton.tonal(
                onPressed: () => _exchange(false),
                child: Text(strings.importBcf),
              ),
            ],
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    );
  }
}

class _BcfPathDialog extends StatefulWidget {
  const _BcfPathDialog({required this.strings});

  final S strings;

  @override
  State<_BcfPathDialog> createState() => _BcfPathDialogState();
}

class _BcfPathDialogState extends State<_BcfPathDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.bcfFile),
      content: TextField(
        key: const Key('bcf-path'),
        controller: _controller,
        decoration: InputDecoration(hintText: widget.strings.bcfFile),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.strings.csvSave),
        ),
      ],
    );
  }
}
