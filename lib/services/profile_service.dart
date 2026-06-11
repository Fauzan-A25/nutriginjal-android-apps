import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nutriginjal/data/models/profile_model.dart';

class ProfileService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Profile?> getMyProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      final profile = Profile.fromJson(data);
      
      // Jika email di profile kosong, gunakan email dari auth metadata
      if (profile.email.isEmpty && user.email != null) {
        return Profile(
          id: profile.id,
          fullName: profile.fullName,
          email: user.email!,
          role: profile.role,
          avatarUrl: profile.avatarUrl,
        );
      }
      
      return profile;
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  // Admin only: Get all profiles
  Future<List<Profile>> getAllProfiles() async {
    try {
      final List<dynamic> data = await _supabase.from('profiles').select();
      return data.map((json) => Profile.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching all profiles: $e');
      return [];
    }
  }

  Future<void> updateProfile({required String fullName, String? avatarUrl}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('profiles').update({
      'full_name': fullName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    }).eq('id', userId);
  }

  // Fungsi baru untuk upload foto profil
  Future<String?> uploadAvatar(File imageFile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'profile_pics/$fileName';

      print('Mencoba upload ke bucket avatars: $path');

      // 1. Upload ke bucket 'avatars'
      await _supabase.storage.from('avatars').upload(
        path,
        imageFile,
        fileOptions: const FileOptions(upsert: true),
      );

      // 2. Dapatkan URL publik
      final String publicUrl = _supabase.storage.from('avatars').getPublicUrl(path);
      print('Upload berhasil. URL: $publicUrl');

      // 3. Update alamat avatar di tabel profiles
      final currentProfile = await getMyProfile();
      await _supabase.from('profiles').update({
        'avatar_url': publicUrl,
      }).eq('id', user.id);

      print('Database profile berhasil diupdate dengan URL baru.');
      return publicUrl;
    } on StorageException catch (e) {
      print('Error Storage Supabase: ${e.message} (Code: ${e.statusCode})');
      return null;
    } on PostgrestException catch (e) {
      print('Error Database Supabase: ${e.message}');
      return null;
    } catch (e) {
      print('Error tidak terduga saat upload: $e');
      return null;
    }
  }
}
