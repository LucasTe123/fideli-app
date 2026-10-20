import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;

import '../widgets/common.dart';

class WalletCropResult {
  const WalletCropResult({required this.oneX, required this.twoX});

  final Uint8List oneX;
  final Uint8List twoX;
}

class WalletImageCropScreen extends StatefulWidget {
  const WalletImageCropScreen({
    super.key,
    required this.image,
    this.title = 'Ajustar fotografía',
    this.aspectRatio = 345 / 505,
    this.oneXWidth = 345,
    this.oneXHeight = 505,
    this.twoXWidth = 690,
    this.twoXHeight = 1010,
    this.resolution = '1035 × 1515 px',
    this.compactGuide = false,
  });
  final Uint8List image;
  final String title;
  final double aspectRatio;
  final int oneXWidth;
  final int oneXHeight;
  final int twoXWidth;
  final int twoXHeight;
  final String resolution;
  final bool compactGuide;

  @override
  State<WalletImageCropScreen> createState() => _WalletImageCropScreenState();
}

class _WalletImageCropScreenState extends State<WalletImageCropScreen> {
  final _controller = CropController();
  bool _processing = false;

  void _finish(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        final decoded = image_lib.decodeImage(croppedImage);
        if (decoded == null) {
          setState(() => _processing = false);
          return;
        }
        Uint8List resize(int width, int height) => Uint8List.fromList(
          image_lib.encodePng(
            image_lib.copyResize(decoded, width: width, height: height),
            level: 6,
          ),
        );
        Navigator.of(context).pop(
          WalletCropResult(
            oneX: resize(widget.oneXWidth, widget.oneXHeight),
            twoX: resize(widget.twoXWidth, widget.twoXHeight),
          ),
        );
      case CropFailure():
        setState(() => _processing = false);
        showMessage(context, 'No se pudo recortar la imagen');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Column(
              children: [
                if (!widget.compactGuide) ...[
                  const Text(
                    'Mueve la imagen con un dedo y usa dos dedos para ampliar.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  widget.resolution,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (!widget.compactGuide) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Formato vertical de Apple Wallet en iOS 27',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: Crop(
                image: widget.image,
                controller: _controller,
                aspectRatio: widget.aspectRatio,
                interactive: true,
                fixCropRect: true,
                baseColor: Colors.black,
                maskColor: Colors.black.withValues(alpha: 0.72),
                progressIndicator: const Center(
                  child: CircularProgressIndicator(),
                ),
                onCropped: _finish,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _processing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _processing
                        ? null
                        : () {
                            setState(() => _processing = true);
                            _controller.crop();
                          },
                    icon: const Icon(Icons.crop),
                    label: Text(_processing ? 'Preparando…' : 'Usar recorte'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
