import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nutriginjal/services/auth_service.dart';
import 'package:nutriginjal/services/profile_service.dart';
import 'package:nutriginjal/data/models/profile_model.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();
  final ImagePicker _picker = ImagePicker();

  Profile? _profile;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileService.getMyProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50, // Kompresi agar hemat storage
    );

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final url = await _profileService.uploadAvatar(File(image.path));
      if (url != null) {
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto profil berhasil diperbarui!')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showEditNameDialog() {
    final TextEditingController nameController =
    TextEditingController(text: _profile?.fullName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Nama'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nama Lengkap',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await _profileService.updateProfile(
                    fullName: nameController.text);
                if (mounted) {
                  Navigator.pop(context);
                  _loadProfile();
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar'),
        content: const Text('Kamu yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _authService.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Profil Saya'),
        backgroundColor: const Color(0xFF26C6DA),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFF26C6DA)))
          : _profile == null
          ? const Center(child: Text('Gagal memuat profil'))
          : ListView(
        children: [
          // ── Header Avatar ───────────────────────
          _buildProfileHeader(),

          const SizedBox(height: 8),

          // ── Info Section ────────────────────────
          _buildSectionLabel('Informasi Akun'),
          _buildInfoTile(
            label: 'Nama Lengkap',
            value: _profile!.fullName,
            icon: Icons.person_outline_rounded,
            onTap: _showEditNameDialog,
            trailing: const Icon(Icons.edit_outlined,
                size: 16, color: Color(0xFF26C6DA)),
          ),
          _buildInfoTile(
            label: 'Email',
            value: _profile!.email,
            icon: Icons.email_outlined,
          ),
          _buildInfoTile(
            label: 'Peran',
            value: _profile!.role.toUpperCase(),
            icon: Icons.badge_outlined,
          ),

          const SizedBox(height: 8),

          // ── Pengaturan Section ──────────────────
          _buildSectionLabel('Pengaturan'),
          _buildActionTile(
            label: 'Ubah Foto Profil',
            icon: Icons.camera_alt_outlined,
            iconColor: const Color(0xFF26C6DA),
            onTap: _pickAndUploadImage,
          ),
          _buildActionTile(
            label: 'Ubah Nama',
            icon: Icons.drive_file_rename_outline_rounded,
            iconColor: const Color(0xFF26C6DA),
            onTap: _showEditNameDialog,
          ),

          const SizedBox(height: 8),

          // ── Danger Zone Section ─────────────────
          _buildSectionLabel('Akun'),
          _buildActionTile(
            label: 'Keluar',
            icon: Icons.logout_rounded,
            iconColor: Colors.red.shade400,
            labelColor: Colors.red.shade400,
            onTap: _showLogoutDialog,
          ),

          const SizedBox(height: 32),

          // Versi app (opsional)
          Center(
            child: Text(
              'NutriGinjal v1.0.0',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Profile Header ─────────────────────────────────
  Widget _buildProfileHeader() {
    final avatarUrl = _profile?.avatarUrl;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFFE0F7FA),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? (_isUploading 
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.person, size: 48, color: Color(0xFF26C6DA)))
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26C6DA),
                      shape: BoxShape.circle,
                      border:
                      Border.all(color: Colors.white, width: 2),
                    ),
                    child: _isUploading 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _profile?.fullName ?? 'User',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _profile?.email ?? '',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF26C6DA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _profile!.role.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0E7490),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Label ───────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ── Info Tile (read-only / editable) ────────────────
  Widget _buildInfoTile({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF26C6DA).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF26C6DA)),
        ),
        title: Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1E293B),
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  // ── Action Tile (tombol aksi) ───────────────────────
  Widget _buildActionTile({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF26C6DA),
    Color? labelColor,
  }) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: labelColor ?? const Color(0xFF1E293B),
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: Colors.grey.shade400, size: 20),
        onTap: onTap,
      ),
    );
  }
}