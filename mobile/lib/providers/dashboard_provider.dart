import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/invoice_repository.dart';
import '../services/sync/sync_service.dart';

class DashboardSummary {
  final double todaySales;
  final int todayCount;
  final double monthlySales;
  final int monthlyCount;
  final double pendingPayments;
  final int pendingCount;
  final int customerCount;
  final bool isLoading;

  DashboardSummary({
    this.todaySales = 0.0,
    this.todayCount = 0,
    this.monthlySales = 0.0,
    this.monthlyCount = 0,
    this.pendingPayments = 0.0,
    this.pendingCount = 0,
    this.customerCount = 0,
    this.isLoading = false,
  });

  DashboardSummary copyWith({
    double? todaySales,
    int? todayCount,
    double? monthlySales,
    int? monthlyCount,
    double? pendingPayments,
    int? pendingCount,
    int? customerCount,
    bool? isLoading,
  }) {
    return DashboardSummary(
      todaySales: todaySales ?? this.todaySales,
      todayCount: todayCount ?? this.todayCount,
      monthlySales: monthlySales ?? this.monthlySales,
      monthlyCount: monthlyCount ?? this.monthlyCount,
      pendingPayments: pendingPayments ?? this.pendingPayments,
      pendingCount: pendingCount ?? this.pendingCount,
      customerCount: customerCount ?? this.customerCount,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardSummary> {
  final InvoiceRepository _repo = InvoiceRepository();
  VoidCallback? _syncListener;

  DashboardNotifier() : super(DashboardSummary()) {
    refreshSummary();
    _syncListener = () {
      if (SyncService.instance.status == SyncStatus.synced) {
        refreshSummary();
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

  Future<void> refreshSummary() async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _repo.getDashboardSummary();
      state = DashboardSummary(
        todaySales: res['todaySales'],
        todayCount: res['todayCount'],
        monthlySales: res['monthlySales'],
        monthlyCount: res['monthlyCount'],
        pendingPayments: res['pendingPayments'],
        pendingCount: res['pendingCount'],
        customerCount: res['customerCount'],
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final dashboardProvider = StateNotifierProvider<DashboardNotifier, DashboardSummary>((ref) {
  return DashboardNotifier();
});
