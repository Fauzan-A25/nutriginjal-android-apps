import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:nutriginjal/core/constants/supabase_config.dart';
import 'package:flutter/foundation.dart';

class GeminiService {
  GenerativeModel _model;
  int _currentKeyIndex = 0;

  GeminiService({GenerativeModel? model})
      : _model = model ?? _createModel(SupabaseConfig.geminiApiKeys[0]);

  static GenerativeModel _createModel(String apiKey) {
    return GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(
        'Kamu adalah NutriSnapS AI, Asisten Gizi Klinis untuk pasien '
            'Penyakit Ginjal Kronis (CKD). Selalu jawab dalam Bahasa Indonesia '
            'yang ramah, terstruktur, dan berbasis data referensi yang diberikan. '
            'Jangan pernah mengarang informasi nutrisi di luar data yang ada.',
      ),
      generationConfig: GenerationConfig(
        temperature: 0.1,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 4096,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ],
    );
  }

  void _rotateKey() {
    if (SupabaseConfig.geminiApiKeys.length <= 1) return;
    _currentKeyIndex = (_currentKeyIndex + 1) % SupabaseConfig.geminiApiKeys.length;
    _model = _createModel(SupabaseConfig.geminiApiKeys[_currentKeyIndex]);
    debugPrint('[GeminiService] Limit reached. Rotating to API Key Index: $_currentKeyIndex');
  }

  /// Stream respons token demi token dengan rotasi otomatis jika limit
  Stream<String> generateResponseStream({
    required String prompt,
    List<Content>? history,
    int retryCount = 0,
  }) async* {
    try {
      final chat = _model.startChat(history: (history == null || history.isEmpty) ? null : history);
      final responseStream = chat.sendMessageStream(Content.text(prompt));
      await for (final chunk in responseStream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) yield text;
      }
    } catch (e) {
      // Deteksi error Quota Exceeded (429)
      if (e.toString().contains('429') && retryCount < SupabaseConfig.geminiApiKeys.length - 1) {
        _rotateKey();
        yield* generateResponseStream(
          prompt: prompt,
          history: history,
          retryCount: retryCount + 1,
        );
      } else {
        rethrow;
      }
    }
  }

  /// Fallback non-stream dengan rotasi otomatis jika limit
  Future<String> generateResponse({
    required String prompt,
    List<Content>? history,
    int retryCount = 0,
  }) async {
    try {
      final chat = _model.startChat(history: (history == null || history.isEmpty) ? null : history);
      final response = await chat.sendMessage(Content.text(prompt));
      return response.text ?? 'Maaf, saya tidak dapat memproses permintaan Anda saat ini.';
    } catch (e) {
      if (e.toString().contains('429') && retryCount < SupabaseConfig.geminiApiKeys.length - 1) {
        _rotateKey();
        return generateResponse(
          prompt: prompt,
          history: history,
          retryCount: retryCount + 1,
        );
      }
      rethrow;
    }
  }

  Future<String> generateTitle(String firstMessage, {int retryCount = 0}) async {
    try {
      final prompt =
          'Buat judul ringkas maksimal 5 kata dalam Bahasa Indonesia '
          'untuk percakapan yang dimulai dengan: "$firstMessage". '
          'Hanya tulis judulnya saja, tanpa tanda kutip.';
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text?.replaceAll('"', '').trim() ?? 'Chat Baru';
    } catch (e) {
      if (e.toString().contains('429') && retryCount < SupabaseConfig.geminiApiKeys.length - 1) {
        _rotateKey();
        return generateTitle(firstMessage, retryCount: retryCount + 1);
      }
      return 'Chat Baru';
    }
  }
}
