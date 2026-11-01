import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/customer_model.dart';
import '../data/repositories/customer_repository.dart';

class CustomerListState {
  final List<CustomerModel> customers;
  final bool isLoading;
  final String searchQuery;
  final String? errorMessage;

  CustomerListState({
    this.customers = const [],
    this.isLoading = false,
    this.searchQuery = '',
    this.errorMessage,
  });

  CustomerListState copyWith({
    List<CustomerModel>? customers,
    bool? isLoading,
    String? searchQuery,
    String? errorMessage,
  }) {
    return CustomerListState(
      customers: customers ?? this.customers,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }
}

class CustomerListNotifier extends StateNotifier<CustomerListState> {
  final CustomerRepository _repo = CustomerRepository();

  CustomerListNotifier() : super(CustomerListState()) {
    fetchCustomers();
  }

  Future<void> fetchCustomers() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _repo.getAllCustomers(searchQuery: state.searchQuery);
      state = state.copyWith(customers: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    fetchCustomers();
  }

  Future<void> addCustomer(CustomerModel customer) async {
    await _repo.saveCustomer(customer);
    fetchCustomers();
  }
}

final customerListProvider = StateNotifierProvider<CustomerListNotifier, CustomerListState>((ref) {
  return CustomerListNotifier();
});
