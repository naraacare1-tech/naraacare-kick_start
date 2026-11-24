/// Marks the time a system prompt that the app itself opened is on screen:
/// the Google / Apple account picker, a permission request, the fingerprint
/// or face prompt, the photo picker.
///
/// While one is open, the app is "inactive" but the user is still in it, so
/// the app-switcher privacy cover stays off and the real page shows behind
/// the prompt (owner 2026-11-24). Leaving the app for real still covers it.
abstract final class SystemPrompt {
  static int _open = 0;

  /// True while at least one prompt opened through [guard] is showing.
  static bool get active => _open > 0;

  /// Runs [prompt] (the call that shows the system UI) as an app prompt.
  static Future<T> guard<T>(Future<T> Function() prompt) async {
    _open++;
    try {
      return await prompt();
    } finally {
      _open--;
    }
  }
}
