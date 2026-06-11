import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as ai;
import 'package:nutriginjal/services/auth_service.dart';
import 'package:nutriginjal/services/profile_service.dart';
import 'package:nutriginjal/services/chat_service.dart';
import 'package:nutriginjal/services/gemini_service.dart';
import 'package:nutriginjal/services/nutrisi_service.dart';
import 'package:nutriginjal/data/models/chat_model.dart';
import 'package:nutriginjal/data/models/profile_model.dart';
import 'package:nutriginjal/core/utils/ckd_nutrition_prompt.dart';
import 'package:nutriginjal/ui/widgets/chat_bubble.dart';

class UserChatHomeScreen extends StatefulWidget {
  const UserChatHomeScreen({super.key});

  @override
  State<UserChatHomeScreen> createState() => _UserChatHomeScreenState();
}

class _UserChatHomeScreenState extends State<UserChatHomeScreen> {
  final ProfileService _profileService = ProfileService();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final GeminiService _geminiService = GeminiService();
  final NutrisiService _nutrisiService = NutrisiService();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isChatActive = false;
  bool _isSessionLoading = false;
  bool _isSending = false;
  bool _isDatasetLoading = true;
  String? _currentSessionId;
  Profile? _userProfile;

  // ── Streaming state ──────────────────────────
  String _streamingText = '';
  bool _isStreaming = false;

  // ── Riwayat lokal untuk sidebar ──────────────
  List<ChatSession> _sessions = [];
  bool _isSessionsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final profile = await _profileService.getMyProfile();
      await _nutrisiService.loadDataset();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isDatasetLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isDatasetLoading = false);
    }
    _loadSessions();
  }

  // ── Load & Refresh riwayat ───────────────────
  Future<void> _loadSessions() async {
    if (mounted) setState(() => _isSessionsLoading = true);
    try {
      final sessions = await _chatService.getChatSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {}
    if (mounted) setState(() => _isSessionsLoading = false);
  }

  String? _getUserAvatar() {
    if (_userProfile?.avatarUrl != null &&
        _userProfile!.avatarUrl!.isNotEmpty) {
      return _userProfile!.avatarUrl;
    }
    final metadata = _authService.currentUser?.userMetadata;
    return metadata?['avatar_url'] ?? metadata?['picture'];
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ─── Start Chat ─────────────────────────────
  Future<void> _startChat(String initialText) async {
    if (initialText.trim().isEmpty || _isDatasetLoading) return;

    setState(() {
      _isSessionLoading = true;
      _isChatActive = true;
    });

    try {
      final session = await _chatService
          .createChatSession(
        initialText.length > 30
            ? '${initialText.substring(0, 30)}...'
            : initialText,
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        _currentSessionId = session.id;
        _isSessionLoading = false;
      });

      // Refresh sidebar setelah sesi baru dibuat
      _loadSessions();

      await _sendMessage(initialText);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChatActive = false;
          _isSessionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memulai chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── Send Message (Streaming) ───────────────
  Future<void> _sendMessage(String text) async {
    final messageContent = text.trim();
    if (messageContent.isEmpty || _currentSessionId == null || _isSending) {
      return;
    }

    _controller.clear();
    setState(() {
      _isSending = true;
      _streamingText = '';
      _isStreaming = true;
    });

    try {
      // 1. Simpan pesan user
      await _chatService.sendMessage(
        sessionId: _currentSessionId!,
        content: messageContent,
        role: 'user',
      );

      // Ambil riwayat lengkap dari database
      final allMessages = await _chatService.getMessages(_currentSessionId!);
      
      // History yang dikirim ke Gemini adalah SEMUA pesan SEBELUM pesan yang sedang diproses.
      // Karena kita baru saja menyimpan pesan User terbaru ke DB, maka dia ada di urutan terakhir.
      // Kita ambil N-1 pesan pertama sebagai history.
      final List<ai.Content> geminiHistory = [];
      if (allMessages.length > 1) {
        for (int i = 0; i < allMessages.length - 1; i++) {
          final m = allMessages[i];
          geminiHistory.add(ai.Content(
            m.role == 'user' ? 'user' : 'model',
            [ai.TextPart(m.content)],
          ));
        }
      }

      // Validasi urutan history untuk mencegah error "Invalid Sequence" (User -> Model -> User)
      // Jika history tidak kosong, pesan TERAKHIR di history HARUS dari 'model' (assistant)
      // karena prompt berikutnya yang dikirim adalah dari 'user'.
      if (geminiHistory.isNotEmpty && geminiHistory.last.role == 'user') {
        geminiHistory.removeLast();
      }

      // 2. RAG Flow
      final relevantItems = _nutrisiService.retrieve(messageContent);
      final contextText = _nutrisiService.formatContext(relevantItems);

      // 3. Build Prompt
      final fullPrompt = CkdNutritionPrompt.build(
        context: contextText,
        userQuestion: messageContent,
      );

      // 4. Streaming ke Gemini
      final buffer = StringBuffer();
      await for (final chunk in _geminiService.generateResponseStream(
        prompt: fullPrompt,
        history: geminiHistory,
      )) {
        buffer.write(chunk);
        if (mounted) {
          setState(() => _streamingText = buffer.toString());
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToBottom());
        }
      }

      final finalReply = buffer.toString().trim().isEmpty
          ? 'Maaf, saya tidak dapat memproses permintaan Anda saat ini.'
          : buffer.toString();

      // 5. Simpan jawaban AI ke DB
      await _chatService.sendMessage(
        sessionId: _currentSessionId!,
        content: finalReply,
        role: 'assistant',
      );
    } catch (e) {
      debugPrint('Chat AI Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI sedang sibuk atau ada masalah: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Coba Lagi',
              textColor: Colors.white,
              onPressed: () => _sendMessage(text),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isStreaming = false;
          _streamingText = '';
        });
      }
    }
  }

  void _handleSubmit() {
    final text = _controller.text;
    if (text.trim().isEmpty || _isSending || _isDatasetLoading) return;

    if (!_isChatActive) {
      _startChat(text);
    } else {
      _sendMessage(text);
    }
  }

  // ─── Hapus Session ───────────────────────────
  Future<void> _deleteSession(ChatSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Riwayat'),
        content: Text(
          'Hapus "${session.title}"?\nSemua pesan di dalamnya akan ikut terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _chatService.deleteChatSession(session.id);

      if (mounted) {
        // Jika yang dihapus adalah sesi aktif, reset ke welcome
        if (_currentSessionId == session.id) {
          setState(() {
            _isChatActive = false;
            _currentSessionId = null;
            _isStreaming = false;
            _streamingText = '';
          });
        }
        setState(() =>
            _sessions.removeWhere((s) => s.id == session.id));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Riwayat berhasil dihapus'),
              ],
            ),
            backgroundColor: const Color(0xFF0284C7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  // ─── Rename Session ──────────────────────────
  Future<void> _renameSession(ChatSession session) async {
    final TextEditingController controller =
        TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Nama Chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Judul Baru',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newTitle != null &&
        newTitle.trim().isNotEmpty &&
        newTitle != session.title) {
      try {
        await _chatService.updateSessionTitle(
          sessionId: session.id,
          newTitle: newTitle.trim(),
        );
        _loadSessions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengubah nama: $e')),
          );
        }
      }
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: _buildSidebar(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MedAI',
          style: TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () async {
                await Navigator.pushNamed(context, '/profile');
                _loadInitialData();
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFE0F2FE),
                backgroundImage: _getUserAvatar() != null
                    ? NetworkImage(_getUserAvatar()!)
                    : null,
                child: _getUserAvatar() == null
                    ? const Icon(Icons.person,
                    color: Color(0xFF0284C7), size: 18)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: _isDatasetLoading
          ? const Center(
          child: CircularProgressIndicator(
              color: Color(0xFF0284C7)))
          : Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _isSending ? 3 : 0,
            child: _isSending
                ? const LinearProgressIndicator(
              color: Color(0xFF0284C7),
              backgroundColor: Color(0xFFE0F2FE),
            )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: _isSessionLoading
                ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF0284C7)),
            )
                : _isChatActive
                ? _buildChatArea()
                : _buildWelcomeArea(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ─── Sidebar / Drawer ────────────────────────
  Widget _buildSidebar() {
    return Drawer(
      child: Column(
        children: [
          // Header: avatar + nama + email
          _buildDrawerHeader(),

          // Tombol Chat Baru
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isChatActive = false;
                  _currentSessionId = null;
                  _isSending = false;
                  _isStreaming = false;
                  _streamingText = '';
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Chat Baru'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: const Color(0xFF0284C7),
                side: const BorderSide(color: Color(0xFF0284C7)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const Divider(height: 1),

          // Label RIWAYAT + tombol refresh
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RIWAYAT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _loadSessions,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.refresh,
                        size: 16, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),

          // List Riwayat
          Expanded(
            child: _isSessionsLoading
                ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF0284C7), strokeWidth: 2),
            )
                : _sessions.isEmpty
                ? Center(
              child: Text(
                'Belum ada riwayat',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected =
                    session.id == _currentSessionId;
                return _buildSessionTile(session, isSelected);
              },
            ),
          ),

          // Tidak ada footer — profil & logout ada di halaman /profile
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Session Tile di Sidebar ─────────────────
  Widget _buildSessionTile(ChatSession session, bool isSelected) {
    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteSession(session);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline,
            color: Colors.white, size: 20),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0284C7).withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: Icon(
            Icons.chat_bubble_outline,
            size: 18,
            color: isSelected
                ? const Color(0xFF0284C7)
                : Colors.grey.shade400,
          ),
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
              isSelected ? FontWeight.w600 : FontWeight.normal,
              color:
              isSelected ? const Color(0xFF0284C7) : Colors.black87,
            ),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade400),
            onSelected: (value) {
              if (value == 'rename') {
                _renameSession(session);
              } else if (value == 'delete') {
                _deleteSession(session);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Ubah Nama'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Hapus', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          onTap: () {
            setState(() {
              _currentSessionId = session.id;
              _isChatActive = true;
              _isSending = false;
              _isStreaming = false;
              _streamingText = '';
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  // ─── Drawer Header ───────────────────────────
  Widget _buildDrawerHeader() {
    final avatarUrl = _getUserAvatar();
    return UserAccountsDrawerHeader(
      margin: EdgeInsets.zero,
      decoration: const BoxDecoration(color: Colors.white),
      currentAccountPicture: CircleAvatar(
        backgroundColor: const Color(0xFFE0F2FE),
        backgroundImage:
        avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? const Icon(Icons.person,
            color: Color(0xFF0284C7), size: 32)
            : null,
      ),
      accountName: Text(
        _userProfile?.fullName ?? 'User',
        style: const TextStyle(
            color: Colors.black, fontWeight: FontWeight.bold),
      ),
      accountEmail: Text(
        _authService.currentUser?.email ?? '',
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  // ─── Welcome Area ────────────────────────────
  Widget _buildWelcomeArea() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFF0284C7),
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'NutriGinjal AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Konsultasi gizi & kesehatan ginjal instan',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),
            _buildSuggestionChips(),
          ],
        ),
      ),
    );
  }

  // ─── Suggestion Chips ────────────────────────
  Widget _buildSuggestionChips() {
    final suggestions = [
      'Pantangan CKD?',
      'Menu protein?',
      'Batas air minum?',
      'Ciri ginjal sehat?',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions
          .map(
            (text) => ActionChip(
          label: Text(text,
              style: const TextStyle(fontSize: 12)),
          backgroundColor: const Color(0xFFE0F2FE),
          side: const BorderSide(
              color: Color(0xFF0284C7), width: 0.5),
          labelStyle:
          const TextStyle(color: Color(0xFF0284C7)),
          onPressed:
          _isSending ? null : () => _startChat(text),
        ),
      )
          .toList(),
    );
  }

  // ─── Chat Area ───────────────────────────────
  Widget _buildChatArea() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.getMessagesStream(_currentSessionId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF0284C7)),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final messages = snapshot.data ?? [];

        final lastIsSaved = messages.isNotEmpty &&
            messages.last.role == 'assistant' &&
            messages.last.id != 'streaming';
        final showStreamBubble = _isStreaming && !lastIsSaved;

        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());

        if (messages.isEmpty && !_isSending) {
          return const Center(
            child: Text(
              'Memulai percakapan...',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 16),
          itemCount:
          messages.length + (showStreamBubble ? 1 : 0),
          itemBuilder: (context, index) {
            if (showStreamBubble && index == messages.length) {
              final streamMsg = ChatMessage(
                id: 'streaming',
                sessionId: _currentSessionId!,
                role: 'assistant',
                content: _streamingText,
                createdAt: DateTime.now(),
              );
              return ChatBubble(
                  message: streamMsg, isStreaming: true);
            }
            return ChatBubble(message: messages[index]);
          },
        );
      },
    );
  }

  // ─── Input Bar ───────────────────────────────
  Widget _buildInputBar() {
    final bool isDisabled =
        _isSending || _isDatasetLoading || _isSessionLoading;

    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
        Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: !isDisabled,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: _isSending
                        ? 'NutriSnapS AI sedang membalas...'
                        : 'Tanya sesuatu...',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isDisabled
                    ? Colors.grey.shade300
                    : const Color(0xFF0284C7),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                onPressed: isDisabled ? null : _handleSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}