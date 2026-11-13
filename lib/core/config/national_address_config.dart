/// Provide this at build time with --dart-define=SPL_API_KEY=...
/// Do not commit a real SPL key in the client application.
const String splApiKey = String.fromEnvironment(
  'SPL_API_KEY',
  defaultValue: 'PUT_YOUR_SPL_API_KEY_HERE',
);

const String splApiKeyPlaceholder = 'PUT_YOUR_SPL_API_KEY_HERE';

bool get isSplApiKeyConfigured =>
    splApiKey.trim().isNotEmpty && splApiKey != splApiKeyPlaceholder;
