// Facade over platform-specific file picking / blob viewing.
//
// `dart:html` only exists on the web target. Using a conditional export keeps
// the non-web build (including `flutter test` on the Dart VM) compilable: it
// falls back to the no-op stub when `dart:html` is unavailable.
export 'evidence_io_stub.dart' if (dart.library.html) 'evidence_io_web.dart';
