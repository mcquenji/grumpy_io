import 'dart:convert';
import 'dart:io';
import 'package:grumpy_io/grumpy_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late FileSystemService service;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('grumpy-safe-write-');
    service = DefaultFileSystemService();
  });
  tearDown(() => temporary.delete(recursive: true));

  test('replaces bytes and cleans staging files', () async {
    final path = IoPath('${temporary.path}/config.json');
    final old = Bytes.fromList(utf8.encode('old'));
    final updated = Bytes.fromList(utf8.encode('updated'));
    expect(await service.replaceBytes(path, old), isA<IoOk<void>>());
    expect(await service.replaceBytes(path, updated), isA<IoOk<void>>());
    expect(await File(path.value).readAsString(), 'updated');
    expect(await temporary.list().length, 1);
  });

  test(
    'failed replacement leaves existing destination contents intact',
    () async {
      final directory = await Directory('${temporary.path}/config').create();
      final sentinel = await File(
        '${directory.path}/keep',
      ).writeAsString('original');
      final result = await service.replaceBytes(
        IoPath(directory.path),
        Bytes.fromList([1]),
      );
      expect(result, isA<IoErr<void>>());
      expect(await sentinel.readAsString(), 'original');
      expect(await temporary.list().length, 1);
    },
  );
}
