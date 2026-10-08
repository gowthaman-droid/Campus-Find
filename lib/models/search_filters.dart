import '../utils/search_keywords.dart';
import 'enums.dart';

/// Everything a person can choose on the Search screen.
/// Immutable: change it with [copyWith] and the screen reloads.
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.type,
    this.status,
    this.category,
    this.location,
  });

  /// Free text typed by the person ("black wallet").
  final String query;
  final ReportType? type;
  final ReportStatus? status;
  final String? category;
  final String? location;

  /// The words used for the keyword search. Empty = no text search.
  List<String> get tokens => SearchKeywords.forQuery(query);

  bool get hasText => tokens.isNotEmpty;

  /// True when nothing is chosen (browse everything).
  bool get isEmpty =>
      !hasText &&
      type == null &&
      status == null &&
      category == null &&
      location == null;

  /// Number of dropdown filters in use (the text box is not counted).
  int get activeFilterCount {
    var count = 0;
    if (type != null) count++;
    if (status != null) count++;
    if (category != null) count++;
    if (location != null) count++;
    return count;
  }

  /// Pass a value to set it, or the matching `clear...: true` to remove it.
  SearchFilters copyWith({
    String? query,
    ReportType? type,
    ReportStatus? status,
    String? category,
    String? location,
    bool clearType = false,
    bool clearStatus = false,
    bool clearCategory = false,
    bool clearLocation = false,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
      category: clearCategory ? null : (category ?? this.category),
      location: clearLocation ? null : (location ?? this.location),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchFilters &&
        other.query == query &&
        other.type == type &&
        other.status == status &&
        other.category == category &&
        other.location == location;
  }

  @override
  int get hashCode => Object.hash(query, type, status, category, location);
}
