import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/models/product_model.dart';

class AddItemDialog extends StatefulWidget {
  final bool isTemporary;
  final Function({
    required String description,
    required String hsnCode,
    required double quantity,
    required String unit,
    required double rate,
    required double discount,
    required double gstRate,
  }) onAdd;

  const AddItemDialog({
    super.key,
    required this.onAdd,
    this.isTemporary = false,
  });

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
  String? _validationError;

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
    final taxable = math.max(0.0, (q * r) - d);
    if (widget.isTemporary) return taxable;
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
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
                  const Expanded(
                    child: Text(
                      'Add Product / Item',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const Divider(),
              if (_validationError != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationError!,
                          style: const TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),

              // Description of Goods (Autocomplete or manual typing)
              Autocomplete<ProductModel>(
                displayStringForOption: (option) => option.description,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _savedProducts.take(6);
                  }
                  final query = textEditingValue.text.toLowerCase().trim();
                  return _savedProducts.where((p) =>
                      p.description.toLowerCase().contains(query) ||
                      p.hsnCode.contains(query));
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(option.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: option.hsnCode.isNotEmpty
                                  ? Text('HSN: ${option.hsnCode} • ₹${option.defaultRate}', style: const TextStyle(fontSize: 11))
                                  : null,
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                FocusManager.instance.primaryFocus?.unfocus();
                                onSelected(option);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (ProductModel selection) {
                  FocusScope.of(context).unfocus();
                  FocusManager.instance.primaryFocus?.unfocus();
                  _descController.text = selection.description;
                  _hsnController.text = selection.hsnCode;
                  if (selection.defaultRate > 0) {
                    _rateController.text = selection.defaultRate.toString();
                  }
                  setState(() {
                    _selectedUnit = selection.unit;
                    _selectedGstRate = selection.gstRate;
                    _validationError = null;
                  });
                },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (text) {
                        _descController.text = text;
                        if (_validationError != null) {
                          setState(() => _validationError = null);
                        }
                        if (_hsnController.text.trim().isEmpty && text.trim().length >= 3) {
                          final match = _savedProducts.firstWhere(
                            (p) => p.description.trim().toLowerCase() == text.trim().toLowerCase(),
                            orElse: () => ProductModel(uuid: '', description: ''),
                          );
                          if (match.hsnCode.isNotEmpty) {
                            _hsnController.text = match.hsnCode;
                            if (_rateController.text.isEmpty && match.defaultRate > 0) {
                              _rateController.text = match.defaultRate.toString();
                            }
                          }
                        }
                      },
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
                    if (!widget.isTemporary) ...[
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hsnController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'HSN / SAC Code',
                            hintText: 'e.g. 8484',
                            helperText: 'Saved for future bills',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: widget.isTemporary ? 1 : 2,
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
                    if (!widget.isTemporary) ...[
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
                    Text(
                      widget.isTemporary ? 'Item Total:' : 'Item Total (Incl. GST):',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
                    setState(() => _validationError = 'Please enter item description');
                    return;
                  }
                  if (qty <= 0) {
                    setState(() => _validationError = 'Quantity must be greater than 0');
                    return;
                  }
                  if (rate <= 0) {
                    setState(() => _validationError = 'Rate must be greater than 0');
                    return;
                  }
                  if (discount < 0) {
                    setState(() => _validationError = 'Discount cannot be negative');
                    return;
                  }
                  if (discount > (qty * rate)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Discount cannot exceed item total (Qty × Rate)')),
                    );
                    return;
                  }

                  final hsn = widget.isTemporary ? '' : _hsnController.text.trim();
                  final effectiveGst = widget.isTemporary ? 0.0 : _selectedGstRate;

                  // Save product & HSN code in catalogue for all future bills
                  if (!widget.isTemporary) {
                    ProductRepository().saveOrUpdateProduct(
                      description: desc,
                      hsnCode: hsn,
                      unit: _selectedUnit,
                      defaultRate: rate,
                      gstRate: effectiveGst,
                    );
                  }

                  FocusScope.of(context).unfocus();
                  FocusManager.instance.primaryFocus?.unfocus();

                  widget.onAdd(
                    description: desc,
                    hsnCode: hsn,
                    quantity: qty,
                    unit: _selectedUnit,
                    rate: rate,
                    discount: discount,
                    gstRate: effectiveGst,
                  );

                  Navigator.of(context, rootNavigator: true).pop();
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
