import '../utils/constants.dart';
import 'enums.dart';
import 'picked_image.dart';

/// What the "Report lost / found" form collects, before anything is saved.
/// ReportService turns it into a report (and checks it again with [validate]).
class ReportDraft {
  const ReportDraft({
    required this.type,
    required this.itemName,
    required this.category,
    required this.description,
    required this.location,
    required this.eventAt,
    this.additionalDetails = '',
    this.locationDetail = '',
    this.newImage,
    this.removeImage = false,
  });

  final ReportType type;
  final String itemName;
  final String category;
  final String description;
  final String additionalDetails;

  /// Campus area chosen from AppConstants.locations.
  final String location;

  /// Optional exact spot, e.g. "2nd floor reading hall".
  final String locationDetail;

  /// When it was lost/found (date and time combined, device time zone).
  final DateTime eventAt;

  /// A photo to upload. Null keeps the existing photo (when editing).
  final PickedImage? newImage;

  /// When editing: true removes the existing photo.
  final bool removeImage;

  /// The form has a date picker and a time picker; this joins them.
  static DateTime combine(DateTime date, int hour, int minute) {
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Returns the first problem as a sentence, or null when the draft is fine.
  /// [now] exists so tests can use a fixed clock.
  String? validate({DateTime? now}) {
    final name = itemName.trim();
    if (name.length < AppConstants.itemNameMin ||
        name.length > AppConstants.itemNameMax) {
      return 'Item name must be ${AppConstants.itemNameMin} to '
          '${AppConstants.itemNameMax} characters.';
    }
    if (!AppConstants.categories.contains(category)) {
      return 'Please choose a category.';
    }
    final text = description.trim();
    if (text.length < AppConstants.descriptionMinUi ||
        text.length > AppConstants.descriptionMax) {
      return 'Description must be ${AppConstants.descriptionMinUi} to '
          '${AppConstants.descriptionMax} characters.';
    }
    if (additionalDetails.trim().length > AppConstants.additionalDetailsMax) {
      return 'Additional details must be at most '
          '${AppConstants.additionalDetailsMax} characters.';
    }
    if (!AppConstants.locations.contains(location)) {
      return 'Please choose a campus area.';
    }
    if (locationDetail.trim().length > AppConstants.locationDetailMax) {
      return 'The exact spot must be at most '
          '${AppConstants.locationDetailMax} characters.';
    }
    final clock = now ?? DateTime.now();
    if (eventAt.isAfter(clock.add(const Duration(minutes: 5)))) {
      return 'The date and time cannot be in the future.';
    }
    return null;
  }
}
