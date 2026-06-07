import 'package:flutter_test/flutter_test.dart';
import 'package:resumetailor/models/journal_entry.dart';

void main() {
  test('JournalEntry round trips through JSON', () {
    final entry = JournalEntry(
      id: 'abc123',
      createdAt: DateTime.parse('2026-04-11T10:00:00.000Z'),
      fileUri: 'file:///tmp/resume.html',
      fileName: 'Tailored_Resume_2026-04-11_10-00-00.html',
      jobDescription: 'Sample JD',
    );

    final decoded = JournalEntry.fromJson(entry.toJson());

    expect(decoded.id, entry.id);
    expect(decoded.createdAt, entry.createdAt);
    expect(decoded.fileUri, entry.fileUri);
    expect(decoded.fileName, entry.fileName);
    expect(decoded.jobDescription, entry.jobDescription);
  });
}
