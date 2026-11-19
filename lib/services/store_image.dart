import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

Uint8List compressStoreImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw StateError('No pudimos leer esa foto. Prueba con otra imagen.');
  }
  if (decoded == null || decoded.width * decoded.height > 40000000) {
    throw StateError('No pudimos leer esa foto. Prueba con otra imagen.');
  }
  var image = img.bakeOrientation(decoded);
  const maxBytes = 1800000;
  for (final maxDimension in [2000, 1800, 1600]) {
    if (image.width > maxDimension || image.height > maxDimension) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? maxDimension : null,
        height: image.height > image.width ? maxDimension : null,
      );
    }
    for (final quality in [90, 86, 82, 80]) {
      final result = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (result.length <= maxBytes) return result;
    }
  }
  throw StateError(
    'No se pudo reducir la foto manteniendo una buena calidad. Elige otra imagen.',
  );
}

Future<Uint8List?> pickStoreImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 100,
  );
  if (file == null) return null;
  return prepareStoreImage(file);
}

Future<Uint8List> prepareStoreImage(XFile file) async {
  if (await file.length() > 10000000) {
    throw StateError('Elige una foto de menos de 10 MB.');
  }
  return compute(compressStoreImage, await file.readAsBytes());
}

String newStoreOrderRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
