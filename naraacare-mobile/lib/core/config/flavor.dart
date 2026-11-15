/// Build flavors (doc 08 §4). Each has its own app ID, API base URL and
/// Firebase project.
enum Flavor {
  dev,
  staging,
  prod;

  /// Parses the `ENV_NAME` value; returns null when it is not a known flavor.
  static Flavor? tryParse(String value) {
    for (final flavor in Flavor.values) {
      if (flavor.name == value) return flavor;
    }
    return null;
  }
}
