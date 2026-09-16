import 'dart:io';

/// Allows writes only below configured harness output roots.
class HarnessOutputPolicy {
  HarnessOutputPolicy(Iterable<String> allowedRoots)
      : _allowedRoots = allowedRoots.map(_canonicalize).toList(growable: false);

  final List<String> _allowedRoots;

  bool allows(String path) {
    final candidate = _canonicalize(path);
    return _allowedRoots.any(
      (root) =>
          candidate == root ||
          candidate.startsWith('$root${Platform.pathSeparator}'),
    );
  }

  void requireAllowed(String path) {
    if (!allows(path)) {
      throw ArgumentError(
        'Harness output path is outside configured output roots.',
      );
    }
  }

  static String _canonicalize(String path) =>
      File(path).absolute.normalize().path.toLowerCase();
}

extension on File {
  File normalize() =>
      File(path.replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator));
}
