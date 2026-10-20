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
  if (image.width > 1200 || image.height > 1200) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1200 : null,
      height: image.height > image.width ? 1200 : null,
    );
  }
  for (final quality in [82, 70, 55, 40]) {
    final result = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (result.length <= 350000) return result;
  }
  throw StateError(
    'La foto tiene demasiado detalle. Elige una imagen más pequeña.',
  );
}

Future<Uint8List?> pickStoreImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 90,
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
