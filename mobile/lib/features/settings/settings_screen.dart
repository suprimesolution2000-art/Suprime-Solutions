import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/auth_provider.dart';
import '../../services/sync/sync_service.dart';
import '../../services/api/api_client.dart';
import '../../data/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _nextNumberController = TextEditingController(text: '1');
  final _prefixController = TextEditingController(text: '');

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = ApiClient.instance.baseUrl;
    _loadInvoiceSettings();
  }

  Future<void> _loadInvoiceSettings() async {
    try {
      final db = await AppDatabase.instance.database;
      final numRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['next_usable_number']);
      final pfxRes = await db.query('app_settings', where: 'key = ?', whereArgs: ['invoice_prefix']);
      if (mounted) {
        setState(() {
          if (numRes.isNotEmpty) _nextNumberController.text = numRes.first['value'] as String;
          if (pfxRes.isNotEmpty) _prefixController.text = pfxRes.first['value'] as String;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveInvoiceSettings() async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'app_settings',
      {'key': 'next_usable_number', 'value': _nextNumberController.text.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'app_settings',
      {'key': 'invoice_prefix', 'value': _prefixController.text.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice numbering settings saved!')),
      );
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _nextNumberController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final authNotifier = ref.read(authProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings & Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. User & Role Switch Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primaryContainer,
                          radius: 24,
                          child: Icon(
                            auth.isOwner ? Icons.admin_panel_settings : Icons.badge,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.user?.name ?? 'Father',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Role: ${auth.user?.role.toUpperCase() ?? "OWNER"}',
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Switch Active Role:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'owner', label: Text('Father (Owner)')),
                        ButtonSegment(value: 'employee', label: Text('Staff (Employee)')),
                      ],
                      selected: {auth.user?.role ?? 'owner'},
                      onSelectionChanged: (set) {
                        authNotifier.switchRole(set.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Cloud Sync Management Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListenableBuilder(
                  listenable: SyncService.instance,
                  builder: (context, _) {
                    final sync = SyncService.instance;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_sync, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text(
                              'Cloud Synchronization',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Status: ${sync.statusMessage}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sync.status == SyncStatus.offline ? Colors.deepOrange : AppColors.primary,
                          ),
                        ),
                        if (sync.pendingCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${sync.pendingCount} local bills waiting to upload when internet is connected.',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        if (sync.lastSyncTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Last Synced: ${DateFormatter.formatDateTime(sync.lastSyncTime)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          icon: sync.status == SyncStatus.syncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.sync, size: 20),
                          label: Text(sync.status == SyncStatus.syncing ? 'Syncing...' : 'Sync Now with Cloud'),
                          onPressed: sync.status == SyncStatus.syncing
                              ? null
                              : () async {
                                  final ok = await SyncService.instance.synchronize();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(ok ? 'Sync successful!' : 'Saved offline on device.'),
                                        backgroundColor: ok ? AppColors.paid : Colors.deepOrange,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Business Profile & GST Master Details Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.store, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Business Master Details',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildDetailRow('Business Name', AppConstants.companyName),
                    _buildDetailRow('GSTIN', AppConstants.gstin),
                    _buildDetailRow('E-PAN No.', AppConstants.ePan),
                    _buildDetailRow('Mobile', AppConstants.mobile),
                    _buildDetailRow('Address', AppConstants.address),
                    _buildDetailRow('Bank', AppConstants.bankName),
                    _buildDetailRow('A/c Number', AppConstants.bankAccountNumber),
                    _buildDetailRow('IFSC Code', AppConstants.bankIfsc),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Simple Invoice Numbering Settings Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.numbers, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Simple Invoice Numbering',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Set starting number or simple prefix (e.g. 1, 2, 3 or SS-1).',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _nextNumberController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Next Bill Number',
                              hintText: 'e.g. 1, 101, 25',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _prefixController,
                            decoration: const InputDecoration(
                              labelText: 'Prefix (Optional)',
                              hintText: 'e.g. SS- (or leave blank)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _saveInvoiceSettings,
                      child: const Text('Save Numbering Settings'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Server Backend Connection URL
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.dns, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Backend Server URL',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API Endpoint URL',
                        hintText: 'e.g. http://10.0.2.2:5000/api or https://api.render.com/api',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () {
                        final newUrl = _serverUrlController.text.trim();
                        if (newUrl.isNotEmpty) {
                          ApiClient.instance.updateBaseUrl(newUrl);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Server URL updated')),
                          );
                        }
                      },
                      child: const Text('Update Server URL'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
