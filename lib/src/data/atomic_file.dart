import 'dart:io';

/// Writes on the same filesystem and renames over the destination. Android
/// and iOS replace the old file atomically; never delete it before renaming.
/// Each writer has its own temporary path, including background isolates.
Future<void> atomicWrite(File destination, String contents) async {
  final scratch = await destination.parent.createTemp('.atomic-');
  try {
    final temporary = File('${scratch.path}/data');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(destination.path);
  } finally {
    await scratch.delete(recursive: true);
  }
}
