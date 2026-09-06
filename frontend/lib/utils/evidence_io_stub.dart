import 'dart:typed_data';

/// A file chosen by the user: (bytes, filename, mimeType).
typedef PickedEvidence = (Uint8List, String, String);

/// Non-web fallback: no file system dialog available.
Future<PickedEvidence?> pickEvidenceFile() async => null;

/// Non-web fallback: no file system dialog available.
Future<PickedEvidence?> pickSpreadsheetFile() async => null;

/// Non-web fallback: opening a blob in a new tab is a web-only operation.
void openBytesInNewTab(Uint8List bytes, String contentType) {}
