/// Maps raw Fluent Form field keys to human-readable labels.
///
/// Each property (calendar) can have its own form with different field names.
/// This utility provides friendly labels for display in the app.
class FormLabelMapper {
  /// Kirwans Lane form field label mappings.
  /// Keys are the exact raw Fluent Form field type names (case-insensitive).
  static const Map<String, String> _kirwansLaneLabels = {
    'datetime': 'Expected Arrival Time',
    'description': 'Door Code',
    'dropdown': 'Number of Guests',
    'description 1': 'Special Requests',
    'checkbox 1': 'Terms Agreement',
  };

  /// Returns the friendly label for a given form field key.
  /// Falls back to the original key if no mapping is found.
  static String getLabel(String rawKey) {
    final normalizedKey = rawKey.toLowerCase().trim();

    // Check exact match first
    if (_kirwansLaneLabels.containsKey(normalizedKey)) {
      return _kirwansLaneLabels[normalizedKey]!;
    }

    // Fallback: return original key
    return rawKey;
  }
}
