import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../services/api/api_client.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiClient.instance.getAdminUsers();
      if (mounted) {
        if (res.statusCode == 200 && res.data['success'] == true) {
          setState(() {
            _users = res.data['data'] ?? [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = res.data['message'] ?? 'Failed to load staff list.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not connect to server. Please check your internet connection.';
          _isLoading = false;
        });
      }
    }
  }

  void _showAddUserDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'employee';
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add New Staff Account',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      hintText: 'e.g. Ramesh Sharma',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username *',
                      hintText: 'e.g. ramesh',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile Number',
                      hintText: 'e.g. 9876543210',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Initial Password (min 6 chars) *',
                      hintText: 'e.g. ramesh@2026',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'employee', child: Text('Staff (Billing Operator)')),
                      DropdownMenuItem(value: 'owner', child: Text('Administrator (Owner)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedRole = val);
                      }
                    },
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final username = usernameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        final pass = passCtrl.text;

                        if (name.isEmpty || username.isEmpty || pass.isEmpty) {
                          setDialogState(() => dialogError = 'Name, username, and password are required.');
                          return;
                        }
                        if (pass.length < 6) {
                          setDialogState(() => dialogError = 'Password must be at least 6 characters.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });

                        try {
                          final res = await ApiClient.instance.createAdminUser(
                            name: name,
                            username: username,
                            password: pass,
                            phone: phone.isNotEmpty ? phone : null,
                            role: selectedRole,
                          );

                          if (ctx.mounted) {
                            if (res.statusCode == 201 && res.data['success'] == true) {
                              Navigator.pop(ctx);
                              _loadUsers();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Staff @$username created successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                                dialogError = res.data['message'] ?? 'Failed to create user.';
                              });
                            }
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = 'Error: $e';
                            });
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Create Staff'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showResetPasswordDialog(Map<String, dynamic> user) {
    final passCtrl = TextEditingController();
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Reset Password for ${user['name']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Username: @${user['username']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: 'New Password *',
                      hintText: 'Enter new password (min 6 chars)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final newPass = passCtrl.text;
                        if (newPass.length < 6) {
                          setDialogState(() => dialogError = 'Password must be at least 6 characters.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });

                        try {
                          final userId = user['_id'] ?? user['id'];
                          final res = await ApiClient.instance.resetAdminUserPassword(userId, newPass);
                          if (ctx.mounted) {
                            if (res.statusCode == 200 && res.data['success'] == true) {
                              Navigator.pop(ctx);
                              _loadUsers();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Password for @${user['username']} updated!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                                dialogError = res.data['message'] ?? 'Failed to reset password.';
                              });
                            }
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = 'Error: $e';
                            });
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Password'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Staff Account?'),
        content: Text('Are you sure you want to delete @${user['username']} (${user['name']})? They will no longer be able to log in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final userId = user['_id'] ?? user['id'];
                final res = await ApiClient.instance.deleteAdminUser(userId);
                if (mounted) {
                  if (res.statusCode == 200 && res.data['success'] == true) {
                    _loadUsers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Account @${user['username']} deleted.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res.data['message'] ?? 'Failed to delete user.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & User Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
        onPressed: _showAddUserDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 54, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadUsers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _users.isEmpty
                  ? const Center(child: Text('No staff accounts found.'))
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                        itemCount: _users.length,
                        itemBuilder: (context, idx) {
                          final u = _users[idx];
                          final isOwner = u['role'] == 'owner';
                          final plainPass = u['plainPassword'];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isOwner ? AppColors.primary : Colors.teal,
                                        child: Icon(
                                          isOwner ? Icons.admin_panel_settings : Icons.person,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              u['name'] ?? 'Unnamed',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            Text(
                                              '@${u['username']}',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isOwner ? Colors.blue.shade50 : Colors.teal.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isOwner ? Colors.blue.shade300 : Colors.teal.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          isOwner ? 'Admin' : 'Staff',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isOwner ? Colors.blue.shade800 : Colors.teal.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  if (u['phone'] != null && u['phone'].toString().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                                        const SizedBox(width: 6),
                                        Text('Mobile: ${u['phone']}', style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (plainPass != null && plainPass.toString().isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.key, size: 16, color: Colors.amber),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Password: $plainPass',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(Icons.copy, size: 16),
                                            tooltip: 'Copy Password',
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: plainPass));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Password copied to clipboard!'), duration: Duration(seconds: 1)),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.lock_reset, size: 18),
                                        label: const Text('Reset Password'),
                                        onPressed: () => _showResetPasswordDialog(u),
                                      ),
                                      if (!isOwner)
                                        TextButton.icon(
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          label: const Text('Delete'),
                                          onPressed: () => _confirmDeleteUser(u),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
