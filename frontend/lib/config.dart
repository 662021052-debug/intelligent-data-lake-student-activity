class AppConfig {
  // ปรับ URL ตอน deploy ด้วย --dart-define=API_BASE_URL=https://your-api.example.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
