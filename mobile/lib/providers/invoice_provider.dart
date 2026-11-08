import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/invoice_model.dart';
import '../data/repositories/invoice_repository.dart';
import '../services/sync/sync_service.dart';

class InvoiceListState {
  final List<InvoiceModel> invoices;
  final bool isLoading;
  final String searchQuery;
  final String filterChip; // 'all', 'paid', 'unpaid', 'partial', 'overdue'
  final String invoiceType; // 'gst' or 'temporary'
  final DateTime? startDate;
  final DateTime? endDate;
  final String? errorMessage;

  InvoiceListState({
    this.invoices = const [],
    this.isLoading = false,
    this.searchQuery = '',
    this.filterChip = 'all',
    this.invoiceType = 'gst',
    this.startDate,
    this.endDate,
    this.errorMessage,
  });

  InvoiceListState copyWith({
    List<InvoiceModel>? invoices,
    bool? isLoading,
    String? searchQuery,
    String? filterChip,
    String? invoiceType,
    DateTime? startDate,
    DateTime? endDate,
    String? errorMessage,
  }) {
    return InvoiceListState(
      invoices: invoices ?? this.invoices,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      filterChip: filterChip ?? this.filterChip,
      invoiceType: invoiceType ?? this.invoiceType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      errorMessage: errorMessage,
    );
  }
}

class InvoiceListNotifier extends StateNotifier<InvoiceListState> {
  final InvoiceRepository _repo = InvoiceRepository();
  VoidCallback? _syncListener;

  InvoiceListNotifier() : super(InvoiceListState()) {
    fetchInvoices();
    _syncListener = () {
      if (SyncService.instance.status == SyncStatus.synced) {
        fetchInvoices();
      }
    };
    SyncService.instance.addListener(_syncListener!);
  }

  @override
  void dispose() {
    if (_syncListener != null) {
      SyncService.instance.removeListener(_syncListener!);
    }
    super.dispose();
  }

  Future<void> fetchInvoices() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _repo.getInvoices(
        searchQuery: state.searchQuery,
        paymentFilter: state.filterChip,
        invoiceType: state.invoiceType,
        startDate: state.startDate,
        endDate: state.endDate,
      );
      state = state.copyWith(invoices: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void setInvoiceType(String type) {
    if (state.invoiceType == type) return;
    state = state.copyWith(invoiceType: type);
    fetchInvoices();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    fetchInvoices();
  }

  void setFilterChip(String chip) {
    state = state.copyWith(filterChip: chip);
    fetchInvoices();
  }

  void setDateRange(DateTime? start, DateTime? end) {
    state = state.copyWith(startDate: start, endDate: end);
    fetchInvoices();
  }

  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      filterChip: 'all',
      startDate: null,
      endDate: null,
    );
    fetchInvoices();
  }
}

final invoiceListProvider = StateNotifierProvider<InvoiceListNotifier, InvoiceListState>((ref) {
  return InvoiceListNotifier();
});
