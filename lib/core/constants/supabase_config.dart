class SupabaseConfig {
  static const String url = 'https://bogged-desolate-washable.ngrok-free.dev';
  static const String anonKey = 'eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3NzkyNDMyMDAsICJleHAiOiAxODEwNzc5MjAwfQ.7w-1OW4iayZXq5jPNYPPmW_JXhRTqy_BticloiGqjKU';

  // Masukkan daftar API Key Gemini Anda di sini untuk rotasi otomatis jika limit
  static const List<String> geminiApiKeys = [
    '-----',
    '----',
    '---',
  ];
}
