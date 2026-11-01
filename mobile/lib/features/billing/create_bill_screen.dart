import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/billing_provider.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import 'add_item_dialog.dart';
import '../invoices/invoice_detail_screen.dart';

class CreateBillScreen extends ConsumerStatefulWidget {
  const CreateBillScreen({super.key});

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

  String _selectedState = 'Chhattisgarh';

  List<CustomerModel> _recentCustomers = [];
  bool _showPoDetails = false;

  @override
  void initState() {
    super.initState();
    _loadRecentCustomers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final num = ref.read(billingProvider).invoiceNumber;
      if (num.isNotEmpty) {
        _invoiceNumberController.text = num;
      }
    });
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
    _customerNameController.text = c.name;
    _phoneController.text = c.phone;
    _gstinController.text = c.gstin;
    _addressController.text = c.address;
    setState(() {
      _selectedState = c.state;
    });

    ref.read(billingProvider.notifier).setCustomer(c);
  }

  @override
  Widget build(BuildContext context) {
    final billState = ref.watch(billingProvider);
    final billingNotifier = ref.read(billingProvider.notifier);

    ref.listen<BillingState>(billingProvider, (prev, next) {
      if (_invoiceNumberController.text.isEmpty && next.invoiceNumber.isNotEmpty) {
        _invoiceNumberController.text = next.invoiceNumber;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Tax Invoice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear Form',
            onPressed: () {
              billingNotifier.resetForm();
              _customerNameController.clear();
              _phoneController.clear();
              _gstinController.clear();
              _addressController.clear();
              _invoiceNumberController.clear();
              _poController.clear();
              _challanController.clear();
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
                        controller.addListener(() {
                          _customerNameController.text = controller.text;
                          billingNotifier.updateCustomerDetails(name: controller.text);
                        });
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
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
                              labelText: 'GSTIN (Optional)',
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
                        labelText: 'Address & City',
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
                            value: _selectedState,
                            decoration: const InputDecoration(
                              labelText: 'State (Place of Supply)',
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Chhattisgarh', child: Text('Chhattisgarh (22)')),
                              DropdownMenuItem(value: 'Madhya Pradesh', child: Text('Madhya Pradesh (23)')),
                              DropdownMenuItem(value: 'Odisha', child: Text('Odisha (21)')),
                              DropdownMenuItem(value: 'Maharashtra', child: Text('Maharashtra (27)')),
                              DropdownMenuItem(value: 'Jharkhand', child: Text('Jharkhand (20)')),
                              DropdownMenuItem(value: 'Other State', child: Text('Other State (IGST)')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                String code = '22';
                                if (val == 'Madhya Pradesh') code = '23';
                                if (val == 'Odisha') code = '21';
                                if (val == 'Maharashtra') code = '27';
                                if (val == 'Jharkhand') code = '20';
                                if (val == 'Other State') code = '99';

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
                                Text(
                                  billState.isInterState ? 'IGST (Inter-state)' : 'CGST + SGST (Local)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: billState.isInterState ? Colors.deepOrange : AppColors.primary,
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
                        separatorBuilder: (_, __) => const Divider(height: 1),
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
                        Text(
                          CurrencyFormatter.format(billState.grandTotal),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
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
                  : () async {
                      final invoice = await billingNotifier.saveAndIssueInvoice();
                      if (!context.mounted) return;
                      if (invoice != null) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailScreen(invoice: invoice),
                          ),
                        );
                      } else if (billState.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(billState.errorMessage!),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: billState.isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'SAVE & GENERATE INVOICE',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCalcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
