# NutriGinjal 🥗: Dokumentasi Teknis & Panduan Ekosistem Digital CKD

**NutriGinjal** adalah platform kesehatan digital komprehensif yang dirancang untuk membantu penderita Penyakit Ginjal Kronis (CKD) dalam manajemen nutrisi dan pemantauan klinis. Proyek ini mengintegrasikan **Generative AI** (Google Gemini) dan **Machine Learning** untuk memberikan asisten gizi yang cerdas serta prediksi risiko kesehatan berbasis data laboratorium.

---

## 📲 Download & Coba Aplikasi
Coba langsung aplikasi NutriGinjal di perangkat Android Anda dengan mengunduh file APK melalui tautan di bawah ini:

[![Download APK Android](https://img.shields.io/badge/Download-APK_Android-0077b5?style=for-the-badge&logo=android&logoColor=white)](https://drive.google.com/file/d/17yrGmR_jhDxFZu_y-gZxwdEolMlzN122/view?usp=sharing)

---

## 📑 Daftar Isi
1. [Visi & Solusi](#-visi--solusi)
2. [Fitur Utama (Detailed)](#-fitur-utama-detailed)
3. [Arsitektur Perangkat Lunak](#-arsitektur-perangkat-lunak)
4. [Struktur Folder & Kegunaan Komponen](#-struktur-folder--kegunaan-komponen)
5. [Analisis Deep Dive: Service Layer](#-analisis-deep-dive-service-layer)
6. [Skema Database & Keamanan (Supabase)](#-skema-database--keamanan-supabase)
7. [Pipeline AI & Machine Learning](#-pipeline-ai--machine-learning)
8. [Panduan Instalasi & Konfigurasi](#-panduan-instalasi--konfigurasi)

---

## 🎯 Visi & Solusi
NutriGinjal hadir untuk memecahkan masalah kompleksitas diet pada pasien ginjal. Dengan batasan ketat pada protein, kalium, dan fosfor, pasien membutuhkan asisten yang selalu siap menjawab pertanyaan nutrisi secara akurat berdasarkan kondisi medis mereka.

---

## ✨ Fitur Utama (Detailed)

### 👤 Modul Pasien (User)
*   **NutriSnap AI Chat**: Chatbot cerdas yang menggunakan model Gemini 2.5 Flash. AI ini bertindak sebagai "Health Buddy" yang ramah, memberikan saran menu, dan menjawab pertanyaan seputar pantangan makanan dengan mempertimbangkan riwayat chat sebelumnya.
*   **Prediction Risk Engine**: Mengizinkan pasien memasukkan 24 parameter laboratorium (dari hasil tes klinis) untuk mendapatkan prediksi risiko perkembangan CKD (Rendah/Tinggi).
*   **Lab Vault (Riwayat Lab)**: Penyimpanan digital terstruktur untuk hasil laboratorium. Pasien dapat melihat tren kesehatan mereka dari waktu ke waktu.
*   **Smart Dashboard**: Menampilkan status kesehatan terbaru, artikel edukasi pilihan, dan akses cepat ke layanan utama.

### 👨‍⚕️ Modul Dokter (Medical)
*   **Medical Analytics Dashboard**: Memberikan statistik real-time mengenai jumlah pasien yang dikelola dan aktivitas pemeriksaan harian.
*   **Patient List & Monitoring**: Dokter dapat melihat daftar pasien yang terhubung dan mengakses detail riwayat laboratorium mereka untuk keperluan diagnosa.
*   **Data Validation (CRUD)**: Memberikan wewenang kepada dokter untuk menghapus atau mengoreksi data riwayat lab pasien guna menjaga integritas data medis di server.

---

## 🏗 Arsitektur Perangkat Lunak
Aplikasi ini menggunakan pola **Layered Architecture** untuk memisahkan tanggung jawab (Separation of Concerns):

1.  **Presentation Layer (UI)**: Dibangun dengan Flutter Material 3. Menggunakan `Stateless` dan `StatefulWidget` yang efisien.
2.  **Service Layer (Business Logic)**: Jembatan antara UI dan Data. Menampung logika kompleks seperti pengolahan riwayat chat untuk AI dan integrasi API ML.
3.  **Data Model Layer**: Standarisasi objek data menggunakan `factory` methods untuk serialisasi JSON (`fromJson`, `toJson`).
4.  **Infrastruktur (External)**: Supabase (PostgreSQL & Auth), Google Gemini API, dan Gradio (ML Hosting).

---

## 📁 Struktur Folder & Kegunaan Komponen

```text
lib/
├── core/
│   ├── constants/
│   │   └── supabase_config.dart   # Pusat konfigurasi API Key & URL Server.
│   ├── theme/                    # Warna, Tipografi, dan Style Button aplikasi.
│   └── utils/                    # Helper: Format tanggal, validator, dan snackbar global.
│
├── data/
│   └── models/                   # Representasi Objek (Data Model)
│       ├── chat_model.dart       # Struktur ChatSession & ChatMessage.
│       ├── lab_model.dart        # Blueprint 24 parameter lab klinis.
│       ├── profile_model.dart    # Atribut User (ID, Nama, Role: doctor/patient).
│       └── nutrisi_model.dart    # Model untuk rekomendasi makanan.
│
├── services/                     # Pusat Logika Operasional
│   ├── auth_service.dart         # Google Sign-In & Supabase Auth management.
│   ├── chat_service.dart         # CRUD Chat ke Supabase (Full History retrieval).
│   ├── gemini_service.dart       # Engine AI: System Prompting & Streaming Response.
│   ├── lab_service.dart          # Logika penyimpanan & penghapusan riwayat lab.
│   ├── api_service.dart          # Integrasi ke model ML (Gradio/REST API).
│   └── profile_service.dart      # Manajemen sinkronisasi profil & deteksi role.
│
├── ui/                           # Layer Antarmuka (UI)
│   ├── pages/
│   │   ├── auth/                 # Halaman Login & Landing.
│   │   ├── user/                 # Fitur Pasien: Dashboard, Chat AI, Form Lab.
│   │   └── doctor/               # Fitur Dokter: Dashboard, Riwayat Pasien, Detail Lab.
│   └── widgets/                  # Komponen Modular (ChatBubble, StatCard, CustomDialog).
│
└── main.dart                     # Inisialisasi Supabase, Auth State, & Root App.
```

---

## ⚙️ Analisis Deep Dive: Service Layer

### 1. `GeminiService` (AI Engine)
Layanan ini menggunakan model `gemini-1.5-flash`.
*   **Persona**: AI dipaksa melalui `systemInstruction` untuk selalu bersikap sebagai asisten gizi ginjal yang ramah.
*   **Safety**: Menggunakan `SafetySetting` untuk memblokir konten berbahaya atau tidak sopan secara otomatis.
*   **Streaming**: Menggunakan `yield` untuk memberikan efek teks mengetik (real-time) sehingga user tidak menunggu respon lama.

### 2. `ChatService` (Memory Management)
*   **Full Context**: Fungsi `getMessages()` mengambil seluruh riwayat percakapan sesi tersebut untuk dikirimkan kembali ke Gemini. Ini memastikan AI "ingat" apa yang dibahas sebelumnya.
*   **Real-time**: Menggunakan `Stream` Supabase agar UI otomatis terupdate saat ada pesan baru masuk.

### 3. `LabService` (Medical Data Sync)
*   Mengelola relasi antara `doctor_id` dan `patient_id`.
*   Memastikan sinkronisasi state antara halaman Detail Lab dan Dashboard Dokter menggunakan mekanisme *callback* setelah proses hapus data.

---

## 🔒 Skema Database & Keamanan (Supabase)

Keamanan data kesehatan pengguna dilindungi melalui **Row Level Security (RLS)** di PostgreSQL:

1.  **Profil Pengguna**: User hanya dapat melihat dan mengubah profil miliknya sendiri berdasarkan `auth.uid()`.
2.  **Pesan Chat**: Hanya pemilik sesi yang diizinkan melakukan `SELECT` dan `INSERT` pada pesan tersebut.
3.  **Riwayat Lab**:
    *   **Pasien**: Hanya bisa melihat data miliknya.
    *   **Dokter**: Memiliki akses baca (`SELECT`) ke semua data pasien dan akses hapus (`DELETE`) jika data tersebut ia yang menginputkan.
4.  **Triggers**: Sinkronisasi otomatis data pendaftaran Google ke tabel `profiles` aplikasi.

---

## 🚀 Pipeline AI & Machine Learning

### Alur Chat AI
1. User mengirim pesan.
2. `ChatService` menarik seluruh riwayat pesan dari tabel `messages`.
3. `GeminiService` menyusun prompt: `[System Instruction] + [Chat History] + [New Message]`.
4. Gemini API memproses dengan `temperature: 0.1` (untuk hasil yang faktual).
5. Jawaban ditampilkan di UI dan disimpan ke database untuk sesi berikutnya.

### Alur Prediksi CKD
1. User menginput 24 data laboratorium klinis.
2. Data dikemas menjadi JSON dan dikirim ke Gradio API.
3. Server ML melakukan inferensi (prediksi) secara remote.
4. Skor risiko dikembalikan ke aplikasi dan disimpan sebagai riwayat laboratorium resmi.

---

## 📥 Panduan Instalasi & Konfigurasi

### 1. Prasyarat
- Flutter SDK terbaru.
- Akun Supabase (URL & Anon Key).
- API Key Google Gemini (AI Studio).

### 2. Konfigurasi API
Edit file `lib/core/constants/supabase_config.dart`:
```dart
class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';
}
```

### 3. Setup Android
- Letakkan `google-services.json` di `android/app/`.
- Pastikan `AndroidManifest.xml` memiliki izin internet dan `usesCleartextTraffic="true"`.

### 4. Running
```bash
flutter pub get
flutter run
```

---
© 2026 **NutriGinjal Project** - Health Technology for a Better Future.
