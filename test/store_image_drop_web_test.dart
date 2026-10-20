@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;
import 'package:fideli/widgets/store_drop/drop_web.dart';

void main() {
  test(
    'native file drop receives bytes and blocks browser navigation',
    () async {
      final target = web.HTMLDivElement();
      web.document.body!.append(target);
      XFile? received;
      String? error;
      final receiver = StoreImageDropReceiver(
        target,
        enabled: () => true,
        onFile: (file) async {
          received = file;
        },
        onError: (message) {
          error = message;
        },
      );
      addTearDown(() {
        receiver.dispose();
        target.remove();
      });
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final data = web.DataTransfer();
      data.items.add(
        web.File(
          [bytes.toJS].toJS,
          'photo.png',
          web.FilePropertyBag(type: 'image/png'),
        ),
      );
      final over = web.DragEvent(
        'dragover',
        web.DragEventInit(bubbles: true, cancelable: true, dataTransfer: data),
      );
      target.dispatchEvent(over);
      expect(over.defaultPrevented, isTrue);
      final drop = web.DragEvent(
        'drop',
        web.DragEventInit(bubbles: true, cancelable: true, dataTransfer: data),
      );
      target.dispatchEvent(drop);
      for (var i = 0; received == null && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(drop.defaultPrevented, isTrue);
      expect(error, isNull);
      expect(received?.name, 'photo.png');
      expect(await received!.readAsBytes(), bytes);
      final outside = web.DragEvent(
        'drop',
        web.DragEventInit(cancelable: true),
      );
      web.window.dispatchEvent(outside);
      expect(outside.defaultPrevented, isTrue);
    },
  );
  test(
    'dragged website image links report a useful error without navigation',
    () {
      final target = web.HTMLDivElement();
      String? error;
      final receiver = StoreImageDropReceiver(
        target,
        enabled: () => true,
        onFile: (_) async {
          fail('Link is not a local file');
        },
        onError: (message) {
          error = message;
        },
      );
      addTearDown(receiver.dispose);
      final data = web.DataTransfer();
      data.items.add('https://example.com/photo.png'.toJS, 'text/uri-list');
      final event = web.DragEvent(
        'drop',
        web.DragEventInit(cancelable: true, dataTransfer: data),
      );
      target.dispatchEvent(event);
      expect(event.defaultPrevented, isTrue);
      expect(error, contains('computadora'));
    },
  );
  test(
    'disabled receiver ignores dropped files while still preventing navigation',
    () async {
      final target = web.HTMLDivElement();
      var calls = 0;
      final receiver = StoreImageDropReceiver(
        target,
        enabled: () => false,
        onFile: (_) async {
          calls++;
        },
        onError: (_) {
          calls++;
        },
      );
      addTearDown(receiver.dispose);
      final event = web.DragEvent(
        'drop',
        web.DragEventInit(cancelable: true, dataTransfer: web.DataTransfer()),
      );
      target.dispatchEvent(event);
      expect(event.defaultPrevented, isTrue);
      expect(calls, 0);
    },
  );
}
