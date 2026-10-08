import '../utils/parsers.dart';

/// How a match score is made up. Every part is 0-100.
class ScoreBreakdown {
  const ScoreBreakdown({
    this.name = 0,
    this.location = 0,
    this.category = 0,
    this.description = 0,
    this.time = 0,
  });

  final int name;
  final int location;
  final int category;
  final int description;
  final int time;

  factory ScoreBreakdown.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return ScoreBreakdown(
      name: readInt(data, 'name'),
      location: readInt(data, 'location'),
      category: readInt(data, 'category'),
      description: readInt(data, 'description'),
      time: readInt(data, 'time'),
    );
  }

  /// Label and value pairs, ready for a list on screen.
  List<MapEntry<String, int>> get rows => <MapEntry<String, int>>[
        MapEntry<String, int>('Item name', name),
        MapEntry<String, int>('Location', location),
        MapEntry<String, int>('Category', category),
        MapEntry<String, int>('Description', description),
        MapEntry<String, int>('Time', time),
      ];
}

/// One match inside the answer of `POST /match`.
class MatchItem {
  const MatchItem({
    required this.matchId,
    required this.matchedReportId,
    required this.score,
    required this.strong,
    required this.breakdown,
  });

  final String matchId;
  final String matchedReportId;
  final int score;
  final bool strong;
  final ScoreBreakdown breakdown;

  factory MatchItem.fromJson(Map<String, dynamic> json) {
    final rawBreakdown = json['breakdown'];
    return MatchItem(
      matchId: readString(json, 'match_id'),
      matchedReportId: readString(json, 'matched_report_id'),
      score: readInt(json, 'score'),
      strong: readBool(json, 'strong'),
      breakdown: ScoreBreakdown.fromMap(
        rawBreakdown is Map ? Map<String, dynamic>.from(rawBreakdown) : null,
      ),
    );
  }
}

/// The whole answer of `POST /match` (see docs/API.md).
class MatchResponse {
  const MatchResponse({
    required this.reportId,
    required this.match,
    required this.score,
    this.matchedReportId,
    this.matches = const <MatchItem>[],
    this.evaluated = 0,
    this.created = 0,
    this.updated = 0,
    this.notified = 0,
  });

  final String reportId;

  /// True when at least one match was found.
  final bool match;

  /// Score of the best match (0 when there is none).
  final int score;
  final String? matchedReportId;

  /// All matches, best first.
  final List<MatchItem> matches;

  final int evaluated;
  final int created;
  final int updated;
  final int notified;

  bool get hasStrongMatch => matches.any((item) => item.strong);

  factory MatchResponse.fromJson(Map<String, dynamic> json) {
    final items = <MatchItem>[];
    final rawMatches = json['matches'];
    if (rawMatches is List) {
      for (final entry in rawMatches) {
        if (entry is Map) {
          items.add(MatchItem.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    final matched = json['matched_report_id'];
    return MatchResponse(
      reportId: readString(json, 'report_id'),
      match: readBool(json, 'match'),
      score: readInt(json, 'score'),
      matchedReportId: matched is String ? matched : null,
      matches: items,
      evaluated: readInt(json, 'evaluated'),
      created: readInt(json, 'created'),
      updated: readInt(json, 'updated'),
      notified: readInt(json, 'notified'),
    );
  }
}
