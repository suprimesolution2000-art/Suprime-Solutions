import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/city_helper.dart';
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
  final _customCityController = TextEditingController();
  String _selectedCity = 'Bilaspur';
  bool _isCustomCity = false;
  String _selectedState = 'Chhattisgarh';
  String _selectedStateCode = '22';
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _addressController.dispose();
    _customCityController.dispose();
    super.dispose();
  }

  void _saveCustomer() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _nameError = 'Please enter customer name';
      });
      return;
    }
    setState(() {
      _nameError = null;
    });

    final newCust = CustomerModel(
      uuid: const Uuid().v4(),
      name: name,
      phone: phone,
      gstin: _gstinController.text.trim().toUpperCase(),
      address: _addressController.text.trim(),
      city: _isCustomCity
          ? (_customCityController.text.trim().isNotEmpty ? _customCityController.text.trim() : 'Bilaspur')
          : _selectedCity,
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
                  const Expanded(
                    child: Text(
                      'Add New Customer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              TextField(
                controller: _nameController,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Customer / Business Name *',
                  prefixIcon: const Icon(Icons.person),
                  errorText: _nameError,
                ),
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
              if (_isCustomCity) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customCityController,
                  decoration: const InputDecoration(labelText: 'Enter Custom City Name *', prefixIcon: Icon(Icons.edit_location_alt)),
                ),
              ],
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _isCustomCity ? 'Other' : (CityHelper.commercialCities.contains(_selectedCity) ? _selectedCity : 'Bilaspur'),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'City *'),
                      items: [
                        ...CityHelper.commercialCities.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        )),
                        const DropdownMenuItem(value: 'Other', child: Text('Other...')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCity = val;
                            _isCustomCity = val == 'Other';
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedState,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'State'),
                      items: AppConstants.indianStates.entries.map((e) {
                        return DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(
                            '${e.key} (${e.value})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final code = AppConstants.indianStates[val] ?? '22';
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
