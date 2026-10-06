import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lendly/core/utils/image_utils.dart';

class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({Key? key}) : super(key: key);

  @override
  State<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  /// Toggle the `isBlocked` field on a user document.
  Future<void> _toggleBlock(String uid, bool currentlyBlocked) async {
    await _firestore.collection('users').doc(uid).set(
      {'isBlocked': !currentlyBlocked},
      SetOptions(merge: true),
    );
  }

  /// Show a confirmation dialog before blocking / unblocking.
  Future<void> _confirmToggle(
      BuildContext ctx, String uid, bool isBlocked, String name) async {
    final action = isBlocked ? 'Unblock' : 'Block';
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action user?'),
        content: Text(
          isBlocked
              ? 'Allow "$name" to use the app again?'
              : 'Block "$name" from using the app? They will not be able to log in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isBlocked
                  ? const Color(0xFF007799)
                  : const Color(0xFFB00020),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _toggleBlock(uid, isBlocked);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('"$name" has been ${isBlocked ? 'unblocked' : 'blocked'}.'),
            backgroundColor:
                isBlocked ? const Color(0xFF007799) : const Color(0xFFB00020),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF007799),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────
          Container(
            color: const Color(0xFF007799),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, username or email…',
                hintStyle:
                    const TextStyle(color: Colors.white70, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── Stats row ────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (ctx, snap) {
              final docs = snap.data?.docs ?? [];
              final total = docs.length;
              final blocked =
                  docs.where((d) => (d.data() as Map)['isBlocked'] == true).length;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(label: 'Total Users', value: total.toString(),
                        color: const Color(0xFF007799)),
                    _Stat(label: 'Active', value: (total - blocked).toString(),
                        color: Colors.green),
                    _Stat(label: 'Blocked', value: blocked.toString(),
                        color: const Color(0xFFB00020)),
                  ],
                ),
              );
            },
          ),

          const Divider(height: 1),

          // ── User list ────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                var docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);

                // Sort alphabetically by name / email
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aName = (aData['firstName'] ?? aData['email'] ?? '').toString().toLowerCase();
                  final bName = (bData['firstName'] ?? bData['email'] ?? '').toString().toLowerCase();
                  return aName.compareTo(bName);
                });

                // Client-side search filter
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final fn = (data['firstName'] ?? '').toString().toLowerCase();
                    final ln = (data['lastName'] ?? '').toString().toLowerCase();
                    final un = (data['username'] ?? '').toString().toLowerCase();
                    final em = (data['email'] ?? '').toString().toLowerCase();
                    return fn.contains(_searchQuery) ||
                        ln.contains(_searchQuery) ||
                        un.contains(_searchQuery) ||
                        em.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline, size: 64,
                            color: Colors.black26),
                        SizedBox(height: 12),
                        Text('No users found.',
                            style: TextStyle(color: Colors.black45)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = doc.id;
                    final firstName = data['firstName'] ?? '';
                    final lastName = data['lastName'] ?? '';
                    final fullName = '$firstName $lastName'.trim();
                    final username = data['username'] ?? '';
                    final email = data['email'] ?? '';
                    final photoURL = data['photoURL'] ?? data['profilePictureUrl'];
                    final isBlocked = data['isBlocked'] == true;
                    final isVerified = data['isVerified'] == true;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundImage: isValidImageUrl(photoURL)
                                  ? NetworkImage(photoURL!)
                                  : null,
                              backgroundColor: const Color(0xFFB2EBF2),
                              child: !isValidImageUrl(photoURL)
                                  ? Text(
                                      (firstName.isNotEmpty
                                          ? firstName[0]
                                          : '?'),
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF007799)),
                                    )
                                  : null,
                            ),
                            if (isBlocked)
                              Positioned(
                                bottom: -2,
                                right: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFB00020),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.block,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                fullName.isNotEmpty ? fullName : email,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified,
                                  color: Color(0xFF007799), size: 16),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (username.isNotEmpty)
                              Text('@$username',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54)),
                            Text(email,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black45)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isBlocked
                                    ? const Color(0xFFFFEBEE)
                                    : const Color(0xFFE0F7FA),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isBlocked ? 'Blocked' : 'Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isBlocked
                                      ? const Color(0xFFB00020)
                                      : const Color(0xFF007799),
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          tooltip: isBlocked ? 'Unblock user' : 'Block user',
                          icon: Icon(
                            isBlocked
                                ? Icons.lock_open_rounded
                                : Icons.block_rounded,
                            color: isBlocked
                                ? Colors.green
                                : const Color(0xFFB00020),
                          ),
                          onPressed: () => _confirmToggle(
                              ctx, uid, isBlocked,
                              fullName.isNotEmpty ? fullName : email),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small stat widget for the summary row.
class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}
