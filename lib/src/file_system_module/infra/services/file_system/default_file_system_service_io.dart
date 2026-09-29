import 'dart:io';

import '../../../../core/core.dart';
import '../../../domain/models/fs_entity_type.dart';
import '../../../domain/models/fs_metadata.dart';
import '../../../domain/models/io_path.dart';
import '../../../domain/services/file_system_service.dart';

/// Native filesystem implementation.
class DefaultFileSystemService extends FileSystemService {
  /// Creates a filesystem service.
  DefaultFileSystemService() : super.internal();

  @override
  Future<IoResult<void>> replaceBytes(IoPath file, Bytes bytes) async {
    Directory? temporary;
    try {
      final target = File(file.value);
      await target.parent.create(recursive: true);
      temporary = await target.parent.createTemp('.grumpy-replace-');
      final staged = File('${temporary.path}/value');
      await staged.writeAsBytes(bytes, flush: true);
      // File.rename replaces files without first removing the destination.
      await staged.rename(target.path);
      return const IoOk(null);
    } catch (error, stack) {
      return IoErr(_mapError(error, stack));
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  @override
  Future<IoResult<bool>> exists(IoPath path) async {
    try {
      final entityType = await FileSystemEntity.type(path.value);
      return IoOk<bool>(entityType != FileSystemEntityType.notFound);
    } catch (error, stackTrace) {
      return IoErr<bool>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<FsMetadata>> stat(IoPath path) async {
    try {
      final entityType = await FileSystemEntity.type(path.value);
      if (entityType == FileSystemEntityType.notFound) {
        return IoOk<FsMetadata>(
          FsMetadata(path: path, type: FsEntityType.unknown, exists: false),
        );
      }
      final fileStat = await FileStat.stat(path.value);
      return IoOk<FsMetadata>(
        FsMetadata(
          path: path,
          type: _mapEntityType(entityType),
          exists: true,
          sizeBytes: fileStat.size,
          createdAt: fileStat.changed,
          modifiedAt: fileStat.modified,
        ),
      );
    } catch (error, stackTrace) {
      return IoErr<FsMetadata>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<Bytes>> readBytes(IoPath file) async {
    try {
      final bytes = await File(file.value).readAsBytes();
      return IoOk<Bytes>(Bytes.fromList(bytes));
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<Bytes>(_mapError(error, stackTrace));
    } catch (error, stackTrace) {
      return IoErr<Bytes>(
        IoFailure(
          code: IoFailureCode.unknown,
          message: 'Unexpected filesystem read failure.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<IoResult<void>> writeBytes(
    IoPath file,
    Bytes bytes, {
    bool overwrite = true,
    bool createParents = true,
  }) async {
    try {
      final output = File(file.value);
      if (!overwrite && await output.exists()) {
        return IoErr<void>(
          IoFailure(
            code: IoFailureCode.alreadyExists,
            message: 'Target file already exists.',
            details: <String, Object?>{'path': file.value},
          ),
        );
      }
      if (createParents) {
        await output.parent.create(recursive: true);
      }
      await output.writeAsBytes(bytes, flush: true);
      return const IoOk<void>(null);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<void>(_mapError(error, stackTrace));
    } catch (error, stackTrace) {
      return IoErr<void>(
        IoFailure(
          code: IoFailureCode.unknown,
          message: 'Unexpected filesystem write failure.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<IoResult<void>> createDirectory(
    IoPath directory, {
    bool recursive = true,
  }) async {
    try {
      await Directory(directory.value).create(recursive: recursive);
      return const IoOk<void>(null);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<void>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<void>> delete(IoPath path, {bool recursive = false}) async {
    try {
      final entityType = await FileSystemEntity.type(path.value);
      switch (entityType) {
        case FileSystemEntityType.file:
          await File(path.value).delete();
        case FileSystemEntityType.directory:
          await Directory(path.value).delete(recursive: recursive);
        case FileSystemEntityType.link:
          await Link(path.value).delete();
        case FileSystemEntityType.notFound:
          return IoErr<void>(
            IoFailure(
              code: IoFailureCode.notFound,
              message: 'Path not found.',
              details: <String, Object?>{'path': path.value},
            ),
          );
        case FileSystemEntityType.unixDomainSock:
          return IoErr<void>(
            IoFailure(
              code: IoFailureCode.unsupported,
              message: 'Unix domain sockets are not supported.',
              details: <String, Object?>{'path': path.value},
            ),
          );
        case FileSystemEntityType.pipe:
          return IoErr<void>(
            IoFailure(
              code: IoFailureCode.unsupported,
              message: 'Unsupported filesystem entity type.',
              details: <String, Object?>{'path': path.value},
            ),
          );
      }
      return const IoOk<void>(null);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<void>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<List<IoPath>>> list(
    IoPath directory, {
    bool recursive = false,
  }) async {
    try {
      final dir = Directory(directory.value);
      if (!await dir.exists()) {
        return IoErr<List<IoPath>>(
          IoFailure(
            code: IoFailureCode.notFound,
            message: 'Directory not found.',
            details: <String, Object?>{'path': directory.value},
          ),
        );
      }
      final items = await dir
          .list(recursive: recursive)
          .map((entity) => IoPath(entity.path))
          .toList();
      return IoOk<List<IoPath>>(items);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<List<IoPath>>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<void>> move(
    IoPath from,
    IoPath to, {
    bool overwrite = false,
  }) async {
    final sourceType = await FileSystemEntity.type(from.value);
    if (sourceType == FileSystemEntityType.notFound) {
      return IoErr<void>(
        IoFailure(
          code: IoFailureCode.notFound,
          message: 'Source path not found.',
          details: <String, Object?>{'path': from.value},
        ),
      );
    }

    final targetType = await FileSystemEntity.type(to.value);
    if (!overwrite && targetType != FileSystemEntityType.notFound) {
      return IoErr<void>(
        IoFailure(
          code: IoFailureCode.alreadyExists,
          message: 'Target path already exists.',
          details: <String, Object?>{'path': to.value},
        ),
      );
    }

    if (targetType != FileSystemEntityType.notFound) {
      final deleteResult = await delete(to, recursive: true);
      if (deleteResult is IoErr<void>) return deleteResult;
    }

    try {
      switch (sourceType) {
        case FileSystemEntityType.file:
          await File(to.value).parent.create(recursive: true);
          await File(from.value).rename(to.value);
        case FileSystemEntityType.directory:
          await Directory(to.value).parent.create(recursive: true);
          await Directory(from.value).rename(to.value);
        case FileSystemEntityType.link:
          await File(to.value).parent.create(recursive: true);
          await Link(from.value).rename(to.value);
        case FileSystemEntityType.unixDomainSock:
        case FileSystemEntityType.notFound:
          return IoErr<void>(
            IoFailure(
              code: IoFailureCode.unsupported,
              message: 'Unsupported source entity type for move.',
              details: <String, Object?>{'path': from.value},
            ),
          );
        case FileSystemEntityType.pipe:
          return IoErr<void>(
            IoFailure(
              code: IoFailureCode.unsupported,
              message: 'Unsupported filesystem entity type.',
              details: <String, Object?>{'path': from.value},
            ),
          );
      }
      return const IoOk<void>(null);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<void>(_mapError(error, stackTrace));
    }
  }

  @override
  Future<IoResult<void>> copy(
    IoPath from,
    IoPath to, {
    bool overwrite = false,
  }) async {
    final sourceType = await FileSystemEntity.type(from.value);
    if (sourceType != FileSystemEntityType.file) {
      return IoErr<void>(
        IoFailure(
          code: IoFailureCode.unsupported,
          message: 'Only file copy is supported.',
          details: <String, Object?>{'path': from.value},
        ),
      );
    }

    final target = File(to.value);
    if (!overwrite && await target.exists()) {
      return IoErr<void>(
        IoFailure(
          code: IoFailureCode.alreadyExists,
          message: 'Target file already exists.',
          details: <String, Object?>{'path': to.value},
        ),
      );
    }

    try {
      await target.parent.create(recursive: true);
      await File(from.value).copy(to.value);
      return const IoOk<void>(null);
    } on FileSystemException catch (error, stackTrace) {
      return IoErr<void>(_mapError(error, stackTrace));
    }
  }

  static FsEntityType _mapEntityType(FileSystemEntityType type) {
    return switch (type) {
      FileSystemEntityType.file => FsEntityType.file,
      FileSystemEntityType.directory => FsEntityType.directory,
      FileSystemEntityType.link => FsEntityType.symlink,
      FileSystemEntityType.notFound => FsEntityType.unknown,
      FileSystemEntityType.unixDomainSock => FsEntityType.unknown,
      _ => FsEntityType.unknown,
    };
  }

  static IoFailure _mapError(Object error, StackTrace stackTrace) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code == 2) {
        return IoFailure(
          code: IoFailureCode.notFound,
          message: error.message,
          cause: error,
          details: <String, Object?>{'path': error.path},
          stackTrace: stackTrace,
        );
      }
      if (code == 17) {
        return IoFailure(
          code: IoFailureCode.alreadyExists,
          message: error.message,
          cause: error,
          details: <String, Object?>{'path': error.path},
          stackTrace: stackTrace,
        );
      }
      if (code == 13) {
        return IoFailure(
          code: IoFailureCode.permissionDenied,
          message: error.message,
          cause: error,
          details: <String, Object?>{'path': error.path},
          stackTrace: stackTrace,
        );
      }
      return IoFailure(
        code: IoFailureCode.unknown,
        message: error.message,
        cause: error,
        details: <String, Object?>{'path': error.path},
        stackTrace: stackTrace,
      );
    }

    return IoFailure(
      code: IoFailureCode.unknown,
      message: 'Unexpected filesystem error.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  @override
  Future<void> destroy() async {}

  @override
  String get logTag => 'DefaultFileSystemService';
}
