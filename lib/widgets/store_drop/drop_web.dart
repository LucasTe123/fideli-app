import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

/// Native browser events deliberately use addEventListener rather than replacing
/// window.ondrop, so other Flutter plugins cannot overwrite this receiver.
class StoreImageDropReceiver {
  StoreImageDropReceiver(
    this.element, {
    required this.enabled,
    required this.onFile,
    required this.onError,
  }) {
    _guard = ((web.Event event) => event.preventDefault()).toJS;
    _over = ((web.DragEvent event) {
      event.preventDefault();
      event.dataTransfer?.dropEffect = enabled() ? 'copy' : 'none';
      paint(enabled());
    }).toJS;
    _leave = ((web.Event event) => paint(false)).toJS;
    _drop = ((web.DragEvent event) {
      event.preventDefault();
      event.stopPropagation();
      paint(false);
      if (!enabled()) return;
      final files = event.dataTransfer?.files;
      if (files == null || files.length != 1) {
        onError(
          'Suelta una sola foto desde una carpeta de tu computadora. También puedes usar Elegir foto.',
        );
        return;
      }
      final file = files.item(0)!;
      if (file.size > 10000000 ||
          (!file.type.startsWith('image/') &&
              !RegExp(
                r'\.(png|jpe?g|webp)$',
                caseSensitive: false,
              ).hasMatch(file.name))) {
        onError('Elige una foto JPG, PNG o WebP de menos de 10 MB.');
        return;
      }
      () async {
        try {
          final buffer = await file.arrayBuffer().toDart;
          if (!_active) return;
          await onFile(
            XFile.fromData(
              Uint8List.view(buffer.toDart),
              name: file.name,
              mimeType: file.type,
            ),
          );
        } catch (_) {
          if (_active) {
            onError('No pudimos leer esa imagen. Prueba con otra foto.');
          }
        }
      }();
    }).toJS;
    element.setAttribute('role', 'region');
    element.setAttribute('aria-label', 'Soltar foto del producto');
    element.style.cssText =
        'box-sizing:border-box;width:100%;height:100%;border:2px dashed #cfccd8;border-radius:22px;background:#f5f4f7;color:#171225;display:flex;align-items:center;justify-content:center;text-align:center;white-space:pre-line;font:14px system-ui;line-height:1.8;cursor:copy;';
    element.addEventListener('dragover', _over);
    element.addEventListener('dragleave', _leave);
    element.addEventListener('drop', _drop);
    web.window.addEventListener('dragover', _guard);
    web.window.addEventListener('drop', _guard);
    paint(false);
  }
  final web.HTMLDivElement element;
  final bool Function() enabled;
  final Future<void> Function(XFile) onFile;
  final void Function(String) onError;
  late final JSFunction _guard, _over, _leave, _drop;
  bool _active = true;
  void paint(bool hover) {
    element.style.backgroundColor = hover ? '#e7e4f0' : '#f5f4f7';
    element.style.borderColor = hover ? '#171225' : '#cfccd8';
    element.textContent = enabled()
        ? 'Arrastra y suelta una foto aquí\nJPG, PNG o WebP · hasta 10 MB'
        : 'Preparando imagen…';
  }

  void dispose() {
    _active = false;
    element.removeEventListener('dragover', _over);
    element.removeEventListener('dragleave', _leave);
    element.removeEventListener('drop', _drop);
    web.window.removeEventListener('dragover', _guard);
    web.window.removeEventListener('drop', _guard);
  }
}

class StoreImageDropArea extends StatefulWidget {
  const StoreImageDropArea({
    super.key,
    required this.enabled,
    required this.onFile,
    required this.onError,
  });
  final bool enabled;
  final Future<void> Function(XFile) onFile;
  final void Function(String) onError;
  @override
  State<StoreImageDropArea> createState() => _StoreImageDropAreaState();
}

class _StoreImageDropAreaState extends State<StoreImageDropArea> {
  StoreImageDropReceiver? _receiver;
  @override
  void didUpdateWidget(covariant StoreImageDropArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _receiver?.paint(false);
  }

  @override
  void dispose() {
    _receiver?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 126,
    width: double.infinity,
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        _receiver?.dispose();
        _receiver = StoreImageDropReceiver(
          element as web.HTMLDivElement,
          enabled: () => widget.enabled,
          onFile: (file) => widget.onFile(file),
          onError: (error) => widget.onError(error),
        );
      },
    ),
  );
}
