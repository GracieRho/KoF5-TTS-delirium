class RuntimeConfig {
  const RuntimeConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.apiOrigin,
    required this.internalToken,
  });

  final String supabaseUrl;
  final String publishableKey;
  final String apiOrigin;
  final String internalToken;

  bool get cloudReady =>
      supabaseUrl.isNotEmpty &&
      publishableKey.isNotEmpty &&
      apiOrigin.isNotEmpty &&
      internalToken.isNotEmpty;

  static const environment = RuntimeConfig(
    supabaseUrl: String.fromEnvironment('KOF5_DEVICE_SUPABASE_URL'),
    publishableKey: String.fromEnvironment(
      'KOF5_DEVICE_SUPABASE_PUBLISHABLE_KEY',
    ),
    apiOrigin: String.fromEnvironment('KOF5_PAIRED_SYNTHETIC_API_ORIGIN'),
    internalToken: String.fromEnvironment('KOF5_INTERNAL_DEMO_TOKEN'),
  );
}
