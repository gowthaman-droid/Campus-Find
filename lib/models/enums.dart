// Small fixed sets of values. Each one keeps the exact text that is saved in
// Firestore (`value`) and a friendly name for the screens (`label`).

enum UserRole {
  student('student', 'Student'),
  admin('admin', 'Admin');

  const UserRole(this.value, this.label);

  final String value;
  final String label;

  static UserRole fromValue(String? value) {
    for (final item in UserRole.values) {
      if (item.value == value) {
        return item;
      }
    }
    return UserRole.student;
  }
}

enum ReportType {
  lost('lost', 'Lost'),
  found('found', 'Found');

  const ReportType(this.value, this.label);

  final String value;
  final String label;

  /// Lost reports are matched with found reports and the other way round.
  ReportType get opposite =>
      this == ReportType.lost ? ReportType.found : ReportType.lost;

  static ReportType fromValue(String? value) {
    for (final item in ReportType.values) {
      if (item.value == value) {
        return item;
      }
    }
    return ReportType.lost;
  }
}

/// Where a report is in its life: active -> claimed -> returned.
enum ReportStatus {
  active('active', 'Active'),
  claimed('claimed', 'Claimed'),
  returned('returned', 'Returned');

  const ReportStatus(this.value, this.label);

  final String value;
  final String label;

  static ReportStatus fromValue(String? value) {
    for (final item in ReportStatus.values) {
      if (item.value == value) {
        return item;
      }
    }
    return ReportStatus.active;
  }
}

/// State of the matching run for one report (`reports.matchStatus`).
enum MatchState {
  pending('pending', 'Matching pending'),
  done('done', 'Matching complete'),
  failed('failed', 'Matching failed');

  const MatchState(this.value, this.label);

  final String value;
  final String label;

  static MatchState fromValue(String? value) {
    for (final item in MatchState.values) {
      if (item.value == value) {
        return item;
      }
    }
    return MatchState.pending;
  }
}

enum ClaimStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  completed('completed', 'Completed');

  const ClaimStatus(this.value, this.label);

  final String value;
  final String label;

  static ClaimStatus fromValue(String? value) {
    for (final item in ClaimStatus.values) {
      if (item.value == value) {
        return item;
      }
    }
    return ClaimStatus.pending;
  }
}

/// Status of a stored match record (`matches.status`).
enum MatchRecordStatus {
  active('active', 'Active'),
  resolved('resolved', 'Resolved');

  const MatchRecordStatus(this.value, this.label);

  final String value;
  final String label;

  static MatchRecordStatus fromValue(String? value) {
    for (final item in MatchRecordStatus.values) {
      if (item.value == value) {
        return item;
      }
    }
    return MatchRecordStatus.active;
  }
}

enum NotificationType {
  matchFound('match_found', 'Potential match'),
  claimSubmitted('claim_submitted', 'New claim'),
  claimApproved('claim_approved', 'Claim approved'),
  claimRejected('claim_rejected', 'Claim rejected'),
  itemReturned('item_returned', 'Item returned'),
  adminMessage('admin_message', 'Message from admin'),
  unknown('unknown', 'Notification');

  const NotificationType(this.value, this.label);

  final String value;
  final String label;

  static NotificationType fromValue(String? value) {
    for (final item in NotificationType.values) {
      if (item.value == value) {
        return item;
      }
    }
    return NotificationType.unknown;
  }
}
