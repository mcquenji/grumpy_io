import 'package:grumpy/grumpy.dart';

import '../../../core/core.dart';
import '../models/fs_metadata.dart';
import '../models/io_path.dart';

/// Service for raw filesystem operations.
abstract class FileSystemService extends Service {
  /// Creates a filesystem service.
  FileSystemService.internal() : super();

  /// Returns the DI-registered implementation.
  factory FileSystemService() => Service.get<FileSystemService>();

  /// Returns whether [path] exists.
  Future<IoResult<bool>> exists(IoPath path);

  /// Returns metadata for [path].
  Future<IoResult<FsMetadata>> stat(IoPath path);

  /// Reads file bytes from [file].
  Future<IoResult<Bytes>> readBytes(IoPath file);

  /// Writes [bytes] to [file].
  Future<IoResult<void>> writeBytes(
    IoPath file,
    Bytes bytes, {
    bool overwrite = true,
    bool createParents = true,
  });

  /// Safely replaces [file] with [bytes], preserving it if replacement fails.
  ///
  /// Backends without safe replacement return unsupported without writing.
  /// Native implementations use a flushed sibling temporary file and rename.
  Future<IoResult<void>> replaceBytes(IoPath file, Bytes bytes) async =>
      const IoErr.unsupported('safe file replacement');

  /// Creates [directory].
  Future<IoResult<void>> createDirectory(
    IoPath directory, {
    bool recursive = true,
  });

  /// Deletes entity at [path].
  Future<IoResult<void>> delete(IoPath path, {bool recursive = false});

  /// Lists entities under [directory].
  Future<IoResult<List<IoPath>>> list(
    IoPath directory, {
    bool recursive = false,
  });

  /// Moves entity from [from] to [to].
  Future<IoResult<void>> move(IoPath from, IoPath to, {bool overwrite = false});

  /// Copies entity from [from] to [to].
  Future<IoResult<void>> copy(IoPath from, IoPath to, {bool overwrite = false});

  @override
  String get group => '${super.group}.FileSystemService';

  @override
  bool get singelton => true;
}
