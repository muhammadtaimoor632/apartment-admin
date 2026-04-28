/// Maps raw Fluent Form field keys to human-readable labels.
///
/// Each property (calendar) can have its own form with different field names.
/// This utility provides friendly labels for display in the app.
class FormLabelMapper {
  /// Form field label mappings for all properties.
  /// Keys are the exact raw Fluent Form field type names (case-insensitive).
  static const Map<String, String> _labelMap = {
    // ── Eyre Square keys ──
    'datetime': 'Expected Arrival Time',
    'description': 'Door Code',
    'dropdown': 'Number of Guests',
    'dropdown 1': 'Car Park',
    'description 1': 'Special Requests',
    'description 2': 'Special Requests',
    'checkbox 1': 'Terms Agreement',

    // ── Kirwans Lane keys ──
    'names': 'Name',
    'checkin': 'Checkin Date',
    'input radio': 'Number of Beds',
    'input radio 1': 'Sofa Bed Preferences',
    'input radio 2': 'Travel Cot/Crib',
    'input radio 3': 'Travel Cot/Crib Preferences',
    'input text': 'Door Code',
    'input radio 4': 'Parking',
    'input radio 5': 'Number of Cars',
    'checkbox': 'Confirmation',
    'input text 1': 'Special Requests',
  };

  /// Returns the friendly label for a given form field key.
  /// Falls back to the original key if no mapping is found.
  static String getLabel(String rawKey, {String propertyName = ''}) {
    final normalizedKey = rawKey.toLowerCase().trim();
    final lowerProperty = propertyName.toLowerCase();

    if (normalizedKey == 'description') {
      if (lowerProperty.contains('kirwan')) {
        return 'Special Requests';
      }
      return 'Door Code';
    }

    if (_labelMap.containsKey(normalizedKey)) {
      return _labelMap[normalizedKey]!;
    }

    // Fallback: return original key
    return rawKey;
  }
}
