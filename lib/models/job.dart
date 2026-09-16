class Job {
  final String id;
  final String title;
  final String company;
  final String location;
  final String postedTime;
  final String url;
  final String description;
  final String source;
  final DateTime firstSeen;
  final DateTime lastUpdated;

  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.postedTime,
    required this.url,
    required this.description,
    required this.source,
    required this.firstSeen,
    required this.lastUpdated,
  });

  Map<String, Object?> toMap() => {
    'job_id': id,
    'title': title,
    'company': company,
    'location': location,
    'posted_time': postedTime,
    'url': url,
    'description': description,
    'source': source,
    'first_seen': firstSeen.toIso8601String(),
    'last_updated': lastUpdated.toIso8601String(),
  };

  factory Job.fromMap(Map<String, Object?> map) => Job(
    id: '${map['job_id'] ?? ''}',
    title: '${map['title'] ?? ''}',
    company: '${map['company'] ?? ''}',
    location: '${map['location'] ?? ''}',
    postedTime: '${map['posted_time'] ?? ''}',
    url: '${map['url'] ?? ''}',
    description: '${map['description'] ?? ''}',
    source: '${map['source'] ?? 'unknown'}',
    firstSeen:
        DateTime.tryParse('${map['first_seen'] ?? ''}') ?? DateTime.now(),
    lastUpdated:
        DateTime.tryParse('${map['last_updated'] ?? ''}') ?? DateTime.now(),
  );
}

class JobFilter {
  final List<String> keywords;
  final List<String> companyWhitelist;
  final List<String> companyBlacklist;
  final String location;
  const JobFilter({
    this.keywords = const [],
    this.companyWhitelist = const [],
    this.companyBlacklist = const [],
    this.location = '',
  });

  bool matches(Job job) {
    final haystack = '${job.title} ${job.company} ${job.description}'
        .toLowerCase();
    final company = job.company.toLowerCase();
    final place = job.location.toLowerCase();
    final terms = keywords
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    final white = companyWhitelist
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    final black = companyBlacklist
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    final wantedLocation = location.trim().toLowerCase();
    return (terms.isEmpty || terms.any(haystack.contains)) &&
        (white.isEmpty || white.any(company.contains)) &&
        !black.any(company.contains) &&
        (wantedLocation.isEmpty || place.contains(wantedLocation));
  }
}
