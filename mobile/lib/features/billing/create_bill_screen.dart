import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/billing_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/repositories/customer_repository.dart';
import 'add_item_dialog.dart';
import '../invoices/invoice_detail_screen.dart';

class CreateBillScreen extends ConsumerStatefulWidget {
  final InvoiceModel? invoiceToEdit;

  const CreateBillScreen({super.key, this.invoiceToEdit});

  @override
  ConsumerState<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends ConsumerState<CreateBillScreen> {
  final _customerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  final _poController = TextEditingController();
  final _challanController = TextEditingController();
  TextEditingController? _customerAutocompleteController;

  String _selectedState = 'Chhattisgarh';
  int _formVersion = 0;

  List<CustomerModel> _recentCustomers = [];
  bool _showPoDetails = false;

  @override
  void initState() {
    super.initState();
    _loadRecentCustomers();
    if (widget.invoiceToEdit != null) {
      final inv = widget.invoiceToEdit!;
      _customerNameController.text = inv.customer.name;
      _phoneController.text = inv.customer.phone;
      _gstinController.text = inv.customer.gstin;
      _addressController.text = inv.customer.address;
      _selectedState = inv.customer.state;
      _invoiceNumberController.text = inv.invoiceNumber;
      _poController.text = inv.poNumber;
      _challanController.text = inv.challanNumber;
      _showPoDetails = inv.poNumber.isNotEmpty || inv.challanNumber.isNotEmpty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(billingProvider.notifier).initForEdit(inv);
      });
    } else {
      _customerNameController.clear();
      _phoneController.clear();
      _gstinController.clear();
      _addressController.clear();
      _invoiceNumberController.clear();
      _poController.clear();
      _challanController.clear();
      _selectedState = 'Chhattisgarh';
      _showPoDetails = false;
      _formVersion++;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(billingProvider.notifier).resetForm();
        if (mounted) {
          final num = ref.read(billingProvider).invoiceNumber;
          if (num.isNotEmpty) {
            _invoiceNumberController.text = num;
          }
        }
      });
    }
  }

  Future<void> _loadRecentCustomers() async {
    final list = await CustomerRepository().getAllCustomers();
    if (mounted) {
      setState(() {
        _recentCustomers = list;
      });
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _invoiceNumberController.dispose();
    _poController.dispose();
    _challanController.dispose();
    super.dispose();
  }

  void _onCustomerSelected(CustomerModel c) {
    _customerAutocompleteController?.text = c.name;
    _customerNameController.text = c.name;
    _phoneController.text = c.phone;
    _gstinController.text = c.gstin;
    _addressController.text = c.address;
    if (c.state.isNotEmpty) {
      setState(() {
        _selectedState = c.state;
      });
    }

    ref.read(billingProvider.notifier).setCustomer(c);
  }

  @override
  Widget build(BuildContext context) {
    final billState = ref.watch(billingProvider);
    final billingNotifier = ref.read(billingProvider.notifier);

    ref.listen<BillingState>(billingProvider, (prev, next) {
      if (widget.invoiceToEdit == null) {
        if (next.invoiceNumber.isNotEmpty &&
            (_invoiceNumberController.text.isEmpty || prev?.invoiceNumber != next.invoiceNumber)) {
          _invoiceNumberController.text = next.invoiceNumber;
        }
      }
    });

    if (widget.invoiceToEdit == null && _invoiceNumberController.text.isEmpty && billState.invoiceNumber.isNotEmpty) {
      _invoiceNumberController.text = billState.invoiceNumber;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoiceToEdit != null ? 'Edit Bill (${widget.invoiceToEdit!.invoiceNumber})' : 'New Tax Invoice'),
        actions: [
          if (widget.invoiceToEdit == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Clear Form',
              onPressed: () async {
                await billingNotifier.resetForm();
                _customerAutocompleteController?.clear();
                _customerNameController.clear();
                _phoneController.clear();
                _gstinController.clear();
                _addressController.clear();
                _invoiceNumberController.clear();
                _poController.clear();
                _challanController.clear();
                setState(() {
                  _formVersion++;
                  _selectedState = 'Chhattisgarh';
                });
                if (context.mounted) {
                  final num = ref.read(billingProvider).invoiceNumber;
                  if (num.isNotEmpty) {
                    _invoiceNumberController.text = num;
                  }
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Customer Information Card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Customer / Billed To',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Customer Name with autocomplete
                    Autocomplete<CustomerModel>(
                      key: ValueKey('cust_ac_$_formVersion'),
                      initialValue: TextEditingValue(text: widget.invoiceToEdit?.customer.name ?? ''),
                      displayStringForOption: (c) => c.name,
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _recentCustomers.take(5);
                        }
                        return _recentCustomers.where((c) =>
                            c.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                            c.phone.contains(textEditingValue.text));
                      },
                      onSelected: _onCustomerSelected,
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        _customerAutocompleteController = controller;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (val) {
                            _customerNameController.text = val;
                            billingNotifier.updateCustomerDetails(name: val);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Customer / Party Name *',
                            hintText: 'e.g. Jindal Steel / Sharma Hardware',
                            prefixIcon: Icon(Icons.business),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Phone & GSTIN Row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number (Optional)',
                              hintText: 'Optional mobile',
                              prefixIcon: Icon(Icons.phone),
                            ),
                            onChanged: (val) {
                              billingNotifier.updateCustomerDetails(phone: val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _gstinController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'GSTIN *',
                              hintText: 'e.g. 22AAAAA0000A1Z5',
                            ),
                            onChanged: (val) {
                              billingNotifier.updateCustomerDetails(gstin: val.toUpperCase());
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Address
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address & City *',
                        hintText: 'e.g. Industrial Area, Bilaspur',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      onChanged: (val) {
                        billingNotifier.updateCustomerDetails(address: val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // State & State Code Row
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: AppConstants.indianStates.containsKey(_selectedState) ? _selectedState : 'Chhattisgarh',
                            decoration: const InputDecoration(
                              labelText: 'State (Place of Supply) *',
                            ),
                            items: AppConstants.indianStates.entries.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.key,
                                child: Text('${e.key} (${e.value})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                final code = AppConstants.indianStates[val] ?? '22';
                                setState(() {
                                  _selectedState = val;
                                });
                                billingNotifier.updateCustomerDetails(
                                  stateName: val,
                                  stateCode: code,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: billState.isInterState ? Colors.amber.shade50 : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tax Type', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    billState.isInterState ? 'IGST (Inter-state)' : 'CGST + SGST (Local)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: billState.isInterState ? Colors.deepOrange : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Invoice Details
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invoice Details',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _invoiceNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Invoice Number',
                              hintText: 'e.g. 1, 2, 3',
                              prefixIcon: Icon(Icons.tag),
                            ),
                            onChanged: (val) {
                              billingNotifier.setCustomInvoiceNumber(val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(130, 52),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(DateFormatter.format(billState.invoiceDate)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: billState.invoiceDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              billingNotifier.setInvoiceDate(picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      icon: Icon(_showPoDetails ? Icons.expand_less : Icons.expand_more),
                      label: Text(_showPoDetails ? 'Hide P.O. / Challan fields' : '+ Add P.O. Number / Challan Number'),
                      onPressed: () {
                        setState(() {
                          _showPoDetails = !_showPoDetails;
                        });
                      },
                    ),

                    if (_showPoDetails) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _poController,
                              decoration: const InputDecoration(labelText: 'P.O. Number'),
                              onChanged: (val) => billingNotifier.setPoDetails(val, billState.poDate),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _challanController,
                              decoration: const InputDecoration(labelText: 'Challan Number'),
                              onChanged: (val) => billingNotifier.setChallanDetails(val, billState.challanDate),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Line Items Section
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Items (${billState.items.length})',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size(140, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add Item', style: TextStyle(fontSize: 15)),
                          onPressed: () {
                            if (billState.items.length >= 11) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Maximum 11 items allowed per invoice for single-page paper template.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            showDialog(
                              context: context,
                              builder: (_) => AddItemDialog(
                                onAdd: ({
                                  required description,
                                  required hsnCode,
                                  required quantity,
                                  required unit,
                                  required rate,
                                  required discount,
                                  required gstRate,
                                }) {
                                  billingNotifier.addItem(
                                    description: description,
                                    hsnCode: hsnCode,
                                    quantity: quantity,
                                    unit: unit,
                                    rate: rate,
                                    discount: discount,
                                    gstRate: gstRate,
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (billState.items.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        alignment: Alignment.center,
                        child: const Column(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textMuted),
                            SizedBox(height: 8),
                            Text('No items added yet', style: TextStyle(color: AppColors.textSecondary)),
                            Text('Tap "+ Add Item" above to add products', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: billState.items.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final itm = billState.items[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: AppColors.primaryContainer,
                                  child: Text('${itm.sno}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itm.description,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Qty: ${itm.quantity.toStringAsFixed(itm.quantity.truncateToDouble() == itm.quantity ? 0 : 2)} ${itm.unit}  ×  ₹${itm.rate.toStringAsFixed(2)}  (GST ${itm.gstRate.toInt()}%)',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.format(itm.totalAmount),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => billingNotifier.removeItem(index),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Live Automatic Calculation Summary
            Card(
              margin: EdgeInsets.zero,
              color: AppColors.surfaceLight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildCalcRow('Taxable Net Amount', CurrencyFormatter.format(billState.netAmount)),
                    if (!billState.isInterState) ...[
                      _buildCalcRow('Add CGST', CurrencyFormatter.format(billState.cgstTotal)),
                      _buildCalcRow('Add SGST', CurrencyFormatter.format(billState.sgstTotal)),
                    ] else ...[
                      _buildCalcRow('Add IGST', CurrencyFormatter.format(billState.igstTotal)),
                    ],
                    if (billState.roundOff != 0.0)
                      _buildCalcRow('Round Off', (billState.roundOff > 0 ? '+₹' : '-₹') + billState.roundOff.abs().toStringAsFixed(2)),
                    const Divider(thickness: 1.5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GRAND TOTAL',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                CurrencyFormatter.format(billState.grandTotal),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        billState.amountInWords,
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 5. THE BIG SAVE & ISSUE BUTTON
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: billState.isSaving
                  ? null
                  : () => _handleSaveInvoice(isEdit: widget.invoiceToEdit != null),
              child: billState.isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      widget.invoiceToEdit != null ? 'UPDATE INVOICE' : 'SAVE & GENERATE INVOICE',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSaveInvoice({required bool isEdit}) async {
    final billState = ref.read(billingProvider);
    final billingNotifier = ref.read(billingProvider.notifier);

    // 1. Validate Customer Name (Compulsory)
    final custName = _customerNameController.text.trim().isNotEmpty
        ? _customerNameController.text.trim()
        : billState.customer.name.trim();
    if (custName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer name is compulsory to generate bill.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Validate GSTIN (Compulsory)
    final gstin = _gstinController.text.trim().isNotEmpty
        ? _gstinController.text.trim()
        : billState.customer.gstin.trim();
    if (gstin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GSTIN number is compulsory to generate bill.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 3. Validate Address (Compulsory)
    final address = _addressController.text.trim().isNotEmpty
        ? _addressController.text.trim()
        : billState.customer.address.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Address is compulsory to generate bill.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 4. Validate Items (Compulsory)
    if (billState.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item to generate bill.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Synchronize customer details before opening confirmation dialog
    final selectedCode = AppConstants.indianStates[_selectedState] ?? '22';
    billingNotifier.updateCustomerDetails(
      name: custName,
      gstin: gstin,
      address: address,
      phone: _phoneController.text.trim(),
      stateName: _selectedState,
      stateCode: selectedCode,
    );

    final invNum = _invoiceNumberController.text.trim().isNotEmpty
        ? _invoiceNumberController.text.trim()
        : billState.invoiceNumber;
    final invDateStr = DateFormatter.format(billState.invoiceDate);

    // 5. Ask confirmation about bill number and bill date
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.verified_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(isEdit ? 'Confirm Bill Update' : 'Confirm Bill Generation'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please verify the bill details before saving:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildDialogRow('Bill Number:', invNum, isHighlight: true, isBold: true),
                    const Divider(height: 16),
                    _buildDialogRow('Bill Date:', invDateStr, isHighlight: true, isBold: true),
                    const Divider(height: 16),
                    _buildDialogRow('Customer:', custName),
                    const Divider(height: 16),
                    _buildDialogRow('GSTIN:', gstin),
                    const Divider(height: 16),
                    _buildDialogRow('Place of Supply:', '$_selectedState ($selectedCode)'),
                    const Divider(height: 16),
                    _buildDialogRow('Total Items:', '${billState.items.length}'),
                    const Divider(height: 16),
                    _buildDialogRow('Grand Total:', CurrencyFormatter.format(billState.grandTotal), isBold: true, isHighlight: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Edit / Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEdit ? 'Confirm & Update' : 'Confirm & Generate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 6. Proceed to save
    if (isEdit) {
      final updated = await billingNotifier.updateExistingInvoice();
      if (!mounted) return;
      if (updated != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill ${updated.invoiceNumber} updated successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context, true);
      } else {
        final currentError = ref.read(billingProvider).errorMessage;
        if (currentError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(currentError),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      final invoice = await billingNotifier.saveAndIssueInvoice();
      if (!mounted) return;
      if (invoice != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoice: invoice),
          ),
        );
      } else {
        final currentError = ref.read(billingProvider).errorMessage;
        if (currentError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(currentError),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildDialogRow(String label, String value, {bool isHighlight = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold || isHighlight ? FontWeight.bold : FontWeight.w500,
              color: isHighlight ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
