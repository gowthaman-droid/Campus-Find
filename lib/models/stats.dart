/// Numbers shown on the student home dashboard.
class DashboardStats {
  const DashboardStats({
    this.lostItems = 0,
    this.foundItems = 0,
    this.returnedItems = 0,
    this.potentialMatches = 0,
  });

  const DashboardStats.empty() : this();

  /// Active lost reports on campus.
  final int lostItems;

  /// Active found reports on campus.
  final int foundItems;

  /// Items that went back to their owners.
  final int returnedItems;

  /// Active matches that involve the signed-in person.
  final int potentialMatches;
}

/// Numbers shown on the admin dashboard.
class AdminStats {
  const AdminStats({
    this.totalUsers = 0,
    this.totalLostReports = 0,
    this.totalFoundReports = 0,
    this.pendingClaims = 0,
    this.returnedItems = 0,
    this.activeMatches = 0,
  });

  const AdminStats.empty() : this();

  final int totalUsers;
  final int totalLostReports;
  final int totalFoundReports;
  final int pendingClaims;
  final int returnedItems;
  final int activeMatches;
}

/// Everything on the analytics screen. All values come from real Firestore
/// counts, nothing is hard-coded.
class AnalyticsSummary {
  const AnalyticsSummary({
    this.totalReports = 0,
    this.lostReports = 0,
    this.foundReports = 0,
    this.returnedItems = 0,
    this.pendingClaims = 0,
    this.successfulMatches = 0,
    this.byCategory = const <String, int>{},
    this.byLocation = const <String, int>{},
    this.generatedAt,
  });

  const AnalyticsSummary.empty() : this();

  final int totalReports;
  final int lostReports;
  final int foundReports;
  final int returnedItems;
  final int pendingClaims;

  /// Matches whose items were returned afterwards (`matches.status == resolved`).
  final int successfulMatches;

  final Map<String, int> byCategory;
  final Map<String, int> byLocation;
  final DateTime? generatedAt;

  /// Share of reports that ended with the item returned (0-100).
  int get returnRatePercent =>
      totalReports == 0 ? 0 : ((returnedItems * 100) / totalReports).round();

  /// Categories with at least one report, biggest first.
  List<MapEntry<String, int>> get topCategories => _sorted(byCategory);

  /// Campus areas with at least one report, biggest first.
  List<MapEntry<String, int>> get topLocations => _sorted(byLocation);

  static List<MapEntry<String, int>> _sorted(Map<String, int> source) {
    final entries = source.entries.where((entry) => entry.value > 0).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}
