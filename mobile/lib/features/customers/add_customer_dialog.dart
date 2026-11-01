import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';

class AddCustomerDialog extends StatefulWidget {
  final Function(CustomerModel) onCustomerAdded;

  const AddCustomerDialog({super.key, required this.onCustomerAdded});

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gstinController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController(text: 'Bilaspur');
  String _selectedState = 'Chhattisgarh';
  String _selectedStateCode = '22';

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _saveCustomer() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name')),
      );
      return;
    }

    final newCust = CustomerModel(
      uuid: const Uuid().v4(),
      name: name,
      phone: phone,
      gstin: _gstinController.text.trim().toUpperCase(),
      address: _addressController.text.trim(),
      city: _cityController.text.trim(),
      state: _selectedState,
      stateCode: _selectedStateCode,
    );

    await CustomerRepository().saveCustomer(newCust);
    widget.onCustomerAdded(newCust);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add New Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Customer / Business Name *', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number (Optional)', prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _gstinController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'GSTIN (Optional)', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedState,
                      decoration: const InputDecoration(labelText: 'State'),
                      items: const [
                        DropdownMenuItem(value: 'Chhattisgarh', child: Text('Chhattisgarh (22)')),
                        DropdownMenuItem(value: 'Madhya Pradesh', child: Text('Madhya Pradesh (23)')),
                        DropdownMenuItem(value: 'Odisha', child: Text('Odisha (21)')),
                        DropdownMenuItem(value: 'Maharashtra', child: Text('Maharashtra (27)')),
                        DropdownMenuItem(value: 'Jharkhand', child: Text('Jharkhand (20)')),
                        DropdownMenuItem(value: 'Other State', child: Text('Other State')),
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
                            _selectedStateCode = code;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _saveCustomer,
                child: const Text('Save Customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
