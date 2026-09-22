class RuntimeConfig {
  const RuntimeConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.apiOrigin,
  });

  final String supabaseUrl;
  final String publishableKey;
  final String apiOrigin;

  bool get cloudReady =>
      supabaseUrl.isNotEmpty &&
      publishableKey.isNotEmpty &&
      apiOrigin.isNotEmpty;

  static const environment = RuntimeConfig(
    supabaseUrl: String.fromEnvironment('KOF5_DEVICE_SUPABASE_URL'),
    publishableKey: String.fromEnvironment(
      'KOF5_DEVICE_SUPABASE_PUBLISHABLE_KEY',
    ),
    apiOrigin: String.fromEnvironment('KOF5_PAIRED_SYNTHETIC_API_ORIGIN'),
  );
}
