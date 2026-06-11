import 'package:flutter_test/flutter_test.dart';
import 'package:nutriginjal/services/gemini_service.dart';
import 'package:nutriginjal/core/constants/supabase_config.dart';

void main() {
  group('Gemini Service Smoke Test (Real API Check)', () {
    final service = GeminiService();

    test('Harus mendapatkan balasan teks dari Gemini AI', () async {
      // Test ini akan benar-benar memanggil API Gemini
      // Berguna untuk memastikan API Key aktif dan kuota tersedia
      try {
        final response = await service.generateResponse(
          prompt: "Halo, siapa kamu? Jawab dalam 5 kata.",
        );
        
        print('AI Response: $response');
        
        expect(response, isNotEmpty);
        expect(response, isNot(contains("Maaf, saya tidak dapat memproses")));
      } catch (e) {
        fail("Gagal memanggil API Gemini: $e");
      }
    }, skip: SupabaseConfig.geminiApiKeys.isEmpty);

    test('Harus bisa membuat judul otomatis dari pesan user', () async {
      try {
        final title = await service.generateTitle("Saya ingin diet rendah kalium untuk ginjal");
        
        print('Generated Title: $title');
        
        expect(title, isNotEmpty);
        expect(title.length, lessThan(100));
      } catch (e) {
        fail("Gagal membuat judul: $e");
      }
    }, skip: SupabaseConfig.geminiApiKeys.isEmpty);
  });
}
