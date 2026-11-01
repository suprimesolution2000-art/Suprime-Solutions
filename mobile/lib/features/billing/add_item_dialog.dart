import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/models/product_model.dart';

class AddItemDialog extends StatefulWidget {
  final Function({
    required String description,
    required String hsnCode,
    required double quantity,
    required String unit,
    required double rate,
    required double discount,
    required double gstRate,
  }) onAdd;

  const AddItemDialog({super.key, required this.onAdd});

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _descController = TextEditingController();
  final _hsnController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _rateController = TextEditingController();
  final _discountController = TextEditingController(text: '0');

  String _selectedUnit = 'PCS';
  double _selectedGstRate = 18.0;

  List<ProductModel> _savedProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _qtyController.addListener(() => setState(() {}));
    _rateController.addListener(() => setState(() {}));
    _discountController.addListener(() => setState(() {}));
  }

  Future<void> _loadProducts() async {
    final list = await ProductRepository().getAllProducts();
    if (mounted) {
      setState(() {
        _savedProducts = list;
      });
    }
  }

  double get _itemTotal {
    final q = double.tryParse(_qtyController.text) ?? 0.0;
    final r = double.tryParse(_rateController.text) ?? 0.0;
    final d = double.tryParse(_discountController.text) ?? 0.0;
    final taxable = (q * r) - d;
    final tax = taxable * (_selectedGstRate / 100);
    return taxable + tax;
  }

  @override
  void dispose() {
    _descController.dispose();
    _hsnController.dispose();
    _qtyController.dispose();
    _rateController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Product / Item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // Description of Goods (Autocomplete or manual typing)
              Autocomplete<ProductModel>(
                displayStringForOption: (option) => option.description,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _savedProducts.take(5);
                  }
                  return _savedProducts.where((p) =>
                      p.description.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (ProductModel selection) {
                  _descController.text = selection.description;
                  _hsnController.text = selection.hsnCode;
                  _rateController.text = selection.defaultRate > 0 ? selection.defaultRate.toString() : '';
                  setState(() {
                    _selectedUnit = selection.unit;
                    _selectedGstRate = selection.gstRate;
                  });
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  // Keep sync with _descController
                  controller.addListener(() {
                    _descController.text = controller.text;
                  });
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Description of Goods *',
                      hintText: 'e.g. Spiral Wound Gasket 2" 150#',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // HSN & Unit Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hsnController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'HSN / SAC Code',
                        hintText: 'e.g. 8484',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedUnit,
                      decoration: const InputDecoration(
                        labelText: 'Unit *',
                      ),
                      items: AppConstants.commonUnits.map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedUnit = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Quantity & Rate Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantity *',
                        prefixIcon: Icon(Icons.format_list_numbered),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Rate (₹) *',
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Discount & GST Rate Row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Discount (₹)',
                        hintText: '0',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _selectedGstRate,
                      decoration: const InputDecoration(
                        labelText: 'GST Rate *',
                      ),
                      items: AppConstants.gstRates.map((r) {
                        return DropdownMenuItem(value: r, child: Text('${r.toInt()}%'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedGstRate = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Live Item Total Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Item Total (Incl. GST):', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      CurrencyFormatter.format(_itemTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Add Button
              ElevatedButton(
                onPressed: () {
                  final desc = _descController.text.trim();
                  final qty = double.tryParse(_qtyController.text) ?? 0.0;
                  final rate = double.tryParse(_rateController.text) ?? 0.0;
                  final discount = double.tryParse(_discountController.text) ?? 0.0;

                  if (desc.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter item description')),
                    );
                    return;
                  }
                  if (qty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Quantity must be greater than 0')),
                    );
                    return;
                  }
                  if (rate <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rate must be greater than 0')),
                    );
                    return;
                  }

                  widget.onAdd(
                    description: desc,
                    hsnCode: _hsnController.text.trim(),
                    quantity: qty,
                    unit: _selectedUnit,
                    rate: rate,
                    discount: discount,
                    gstRate: _selectedGstRate,
                  );

                  Navigator.pop(context);
                },
                child: const Text('Add Item to Bill'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
