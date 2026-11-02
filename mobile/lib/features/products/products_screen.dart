import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/product_repository.dart';
import '../../services/api/api_client.dart';
import '../../services/sync/sync_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  final ProductRepository _repo = ProductRepository();
  List<ProductModel> _products = [];
  bool _isLoading = true;
  VoidCallback? _syncListener;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _syncListener = () {
      if (SyncService.instance.status == SyncStatus.synced && mounted) {
        _loadProducts();
      }
    };
    SyncService.instance.addListener(_syncListener!);
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_syncListener != null) {
      SyncService.instance.removeListener(_syncListener!);
    }
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final list = await _repo.getAllProducts(searchQuery: _searchController.text.trim());
      if (mounted) {
        setState(() {
          _products = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddOrEditDialog({ProductModel? product}) {
    final isEditing = product != null;
    final descCtrl = TextEditingController(text: product?.description ?? '');
    final hsnCtrl = TextEditingController(text: product?.hsnCode ?? '');
    final rateCtrl = TextEditingController(text: product != null && product.defaultRate > 0 ? product.defaultRate.toStringAsFixed(2) : '');
    String selectedUnit = product?.unit ?? 'PCS';
    double selectedGst = product?.gstRate ?? 18.0;

    final units = ['PCS', 'NOS', 'SET', 'MTR', 'BOX', 'KGS', 'ROLL', 'PKT'];
    final gstRates = [0.0, 5.0, 12.0, 18.0, 28.0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(isEditing ? Icons.edit_note : Icons.add_box, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(isEditing ? 'Edit Product' : 'Add New Product'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Product Description *',
                      hintText: 'e.g. Spiral Wound Gasket 2"',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hsnCtrl,
                          decoration: const InputDecoration(
                            labelText: 'HSN Code',
                            hintText: 'e.g. 8484',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(),
                          ),
                          items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedUnit = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Default Rate (₹)',
                            hintText: '0.00',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          initialValue: selectedGst,
                          decoration: const InputDecoration(
                            labelText: 'GST %',
                            border: OutlineInputBorder(),
                          ),
                          items: gstRates.map((r) => DropdownMenuItem(value: r, child: Text('${r.toInt()}%'))).toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedGst = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final desc = descCtrl.text.trim();
                  if (desc.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a product description.')),
                    );
                    return;
                  }
                  final rate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                  final hsn = hsnCtrl.text.trim();

                  await _repo.saveOrUpdateProduct(
                    uuid: product?.uuid,
                    description: desc,
                    hsnCode: hsn,
                    unit: selectedUnit,
                    defaultRate: rate,
                    gstRate: selectedGst,
                    active: true,
                  );

                  Navigator.pop(ctx);
                  await _loadProducts();
                  SyncService.instance.synchronize();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(isEditing ? 'Product updated.' : 'Product added to catalogue.')),
                    );
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Add Product'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteProduct(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Delete Product?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${product.description}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'HSN: ${product.hsnCode.isNotEmpty ? product.hsnCode : "N/A"}  •  Rate: ${CurrencyFormatter.format(product.defaultRate)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            const Text(
              'This product will be removed from your catalogue and autocomplete across all synced devices. Past invoices will keep their item details.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _repo.deleteProduct(product.uuid);
      try {
        await ApiClient.instance.deleteProduct(product.uuid);
      } catch (_) {}
      await _loadProducts();
      SyncService.instance.synchronize();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product "${product.description}" deleted.'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Catalogue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Product',
            onPressed: () => _showAddOrEditDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync & Refresh',
            onPressed: () async {
              await SyncService.instance.synchronize(forceFullSync: true);
              await _loadProducts();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search product description or HSN code...',
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadProducts();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _loadProducts(),
            ),
          ),

          // Product List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await _loadProducts();
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: 350,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No products matching "${_searchController.text}"'
                                      : 'No products in catalogue yet',
                                  style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Tap "+" to add an industrial product',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await SyncService.instance.synchronize(forceFullSync: true);
                          await _loadProducts();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final p = _products[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primaryContainer,
                                  child: const Icon(Icons.hardware, color: AppColors.primary),
                                ),
                                title: Text(
                                  p.description,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      if (p.hsnCode.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('HSN: ${p.hsnCode}', style: const TextStyle(fontSize: 11)),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(p.unit, style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('${p.gstRate.toInt()}% GST', style: TextStyle(fontSize: 11, color: Colors.green.shade800)),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      CurrencyFormatter.format(p.defaultRate),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                                      tooltip: 'Edit Product',
                                      onPressed: () => _showAddOrEditDialog(product: p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      tooltip: 'Delete Product',
                                      onPressed: () => _confirmDeleteProduct(p),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        onPressed: () => _showAddOrEditDialog(),
      ),
    );
  }
}
