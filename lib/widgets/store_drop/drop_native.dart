import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _hover = false;
  @override
  Widget build(BuildContext context) => DropTarget(
    enable: widget.enabled,
    onDragEntered: (_) => setState(() => _hover = true),
    onDragExited: (_) => setState(() => _hover = false),
    onDragDone: (detail) async {
      setState(() => _hover = false);
      if (detail.files.length != 1) {
        widget.onError('Suelta una sola foto a la vez.');
        return;
      }
      await widget.onFile(detail.files.single);
    },
    child: Container(
      height: 126,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _hover ? const Color(0xffe7e4f0) : const Color(0xfff5f4f7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffcfccd8)),
      ),
      child: Text(
        widget.enabled
            ? 'Arrastra y suelta la foto aquí\nO usa Elegir foto'
            : 'Preparando imagen…',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
