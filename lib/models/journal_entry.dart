class JournalEntry {
  final String id;
  final DateTime createdAt;
  final String fileUri;
  final String fileName;
  final String jobDescription;

  const JournalEntry({
    required this.id,
    required this.createdAt,
    required this.fileUri,
    required this.fileName,
    required this.jobDescription,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'fileUri': fileUri,
        'fileName': fileName,
        'jobDescription': jobDescription,
      };

  static JournalEntry fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        fileUri: json['fileUri'] as String? ?? '',
        fileName: json['fileName'] as String,
        jobDescription: json['jobDescription'] as String? ?? '',
      );
}
