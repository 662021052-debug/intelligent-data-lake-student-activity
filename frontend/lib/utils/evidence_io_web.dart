// This file is only ever compiled for the web target (selected via the
// conditional import in evidence_io.dart), where dart:html is the supported way
// to open a file dialog and create object URLs.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// A file chosen by the user: (bytes, filename, mimeType).
typedef PickedEvidence = (Uint8List, String, String);

/// Opens the browser file dialog (images + PDF) and returns the chosen file's
/// bytes, filename and MIME type, or null if the user cancels.
Future<PickedEvidence?> pickEvidenceFile() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/jpeg,image/png,application/pdf'
    ..multiple = false;
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final file = files.first;

  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;

  final result = reader.result;
  final bytes = result is Uint8List ? result : Uint8List.fromList(List<int>.from(result as List));
  final contentType = file.type.isNotEmpty ? file.type : 'application/octet-stream';
  return (bytes, file.name, contentType);
}

/// Wraps bytes in an object URL and opens it in a new browser tab (used for PDFs).
void openBytesInNewTab(Uint8List bytes, String contentType) {
  final blob = html.Blob([bytes], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  // The URL is revoked after a short delay so the new tab has time to load it.
  Timer(const Duration(minutes: 1), () => html.Url.revokeObjectUrl(url));
}
