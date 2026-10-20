import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:fideli/services/store_image.dart';
import 'package:fideli/config/supabase_config.dart';

void main() {
  test('form and store share tenant host with distinct paths', () {
    final form = SupabaseConfig.publicClubUriForBusiness('business-a', publicSlug: 'padelbo');
    final store = SupabaseConfig.publicStoreUriForBusiness('business-a', publicSlug: 'padelbo');
    final other = SupabaseConfig.publicStoreUriForBusiness('business-b', publicSlug: 'culina');
    expect(form.host, 'padelbo.fideli.site');
    expect(form.path, '/');
    expect(store.host, form.host);
    expect(store.path, '/tienda');
    expect(store.toString(), 'https://padelbo.fideli.site/tienda');
    expect(store.query, isEmpty);
    expect(other.host, isNot(store.host));
  });
  test('uploaded photo is bounded JPEG with preserved aspect ratio', () {
    final source = img.Image(width: 1800, height: 900);
    img.fill(source, color: img.ColorRgb8(120, 180, 210));
    final compressed = compressStoreImage(Uint8List.fromList(img.encodePng(source)));
    final result = img.decodeJpg(compressed)!;
    expect(result.width, 1200);
    expect(result.height, 600);
    expect(compressed.length, lessThanOrEqualTo(350000));
    expect(compressed.length, greaterThan(0));
  });
  test('invalid image produces a useful failure', () {
    expect(() => compressStoreImage(Uint8List.fromList([1, 2, 3])), throwsStateError);
  });
  test('dropped file follows the same compressed-image pipeline', () async {
    final source = img.Image(width: 1500, height: 750);
    final file = XFile.fromData(Uint8List.fromList(img.encodePng(source)), name: 'dropped.png');
    final result = await prepareStoreImage(file);
    expect(img.decodeJpg(result)!.width, 1200);
    expect(result.length, lessThanOrEqualTo(350000));
  });
  test('dropped oversized file fails before decoding', () async {
    final file = XFile.fromData(Uint8List(10000001), name: 'large.png');
    await expectLater(prepareStoreImage(file), throwsStateError);
  });
  test('checkout retry key is a unique valid UUID', () {
    final first = newStoreOrderRequestId();
    expect(first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(first, isNot(newStoreOrderRequestId()));
  });

}
