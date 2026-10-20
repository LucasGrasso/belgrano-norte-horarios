import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tren_bn_horarios/src/data/atomic_file.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('atomic-test-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('replaces an existing cache without leaving scratch files', () async {
    final file = File('${directory.path}/cache.json');
    await file.writeAsString('old');
    await atomicWrite(file, 'new');
    expect(await file.readAsString(), 'new');
    expect(await directory.list().length, 1);
  });

  test('concurrent writes leave one complete, readable document', () async {
    final file = File('${directory.path}/cache.json');
    final first = 'a' * 100000;
    final second = 'b' * 100000;
    await Future.wait([atomicWrite(file, first), atomicWrite(file, second)]);
    expect(await file.readAsString(), anyOf(first, second));
    expect(await directory.list().length, 1);
  });

  test(
    'failed rename preserves the destination and cleans temporary data',
    () async {
      final existing = await Directory('${directory.path}/cache').create();
      final sentinel = File('${existing.path}/keep');
      await sentinel.writeAsString('old');
      await expectLater(
        atomicWrite(File(existing.path), 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'old');
      expect(await directory.list().length, 1);
    },
  );
}
