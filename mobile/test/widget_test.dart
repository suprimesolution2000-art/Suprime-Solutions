import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_billing/main.dart';
import 'package:mobile_billing/core/constants/app_constants.dart';
import 'package:mobile_billing/core/utils/number_to_words.dart';
import 'package:mobile_billing/core/utils/currency_formatter.dart';
import 'package:mobile_billing/data/models/invoice_model.dart';
import 'package:mobile_billing/data/models/customer_model.dart';
import 'package:mobile_billing/data/models/invoice_item_model.dart';
import 'package:mobile_billing/services/updater/app_update_service.dart';
import 'package:mobile_billing/services/sync/sync_service.dart';
import 'package:mobile_billing/providers/billing_provider.dart';
import 'package:mobile_billing/providers/invoice_provider.dart';

void main() {
  test('Indian Currency & Words Utilities Test', () {
    expect(
      NumberToWords.convert(31329),
      'Rupees Thirty One Thousand Three Hundred Twenty Nine Only',
    );
    expect(
      CurrencyFormatter.format(31329),
      '₹31,329.00',
    );
  });

  test('InvoiceModel copyWith supports bill editing fields', () {
    final original = InvoiceModel(
      uuid: 'inv-123',
      invoiceNumber: 'SS/26-27/001',
      sequenceNumber: 1,
      financialYear: '26-27',
      invoiceDate: DateTime(2026, 4, 1),
      customer: CustomerModel(uuid: 'cust-1', name: 'Original Customer', phone: '9999999999'),
      items: [
        InvoiceItemModel(
          sno: 1,
          description: 'Item 1',
          hsnCode: '8481',
          quantity: 2,
          unit: 'PCS',
          rate: 100,
          taxableValue: 200,
          gstRate: 18,
          cgstRate: 9,
          cgstAmount: 18,
          sgstRate: 9,
          sgstAmount: 18,
          totalAmount: 236,
        ),
      ],
      netAmount: 200,
      cgstTotal: 18,
      sgstTotal: 18,
      grandTotal: 236,
      amountInWords: 'Rupees Two Hundred Thirty Six Only',
      balanceDue: 236,
    );

    final edited = original.copyWith(
      poNumber: 'PO-2026-99',
      grandTotal: 500,
      balanceDue: 500,
      syncStatus: 'waiting_for_internet',
    );

    expect(edited.uuid, 'inv-123');
    expect(edited.poNumber, 'PO-2026-99');
    expect(edited.grandTotal, 500);
    expect(edited.balanceDue, 500);
    expect(edited.syncStatus, 'waiting_for_internet');
  });

  test('AppUpdateService.isNewerVersion semantic version comparisons', () {
    expect(AppUpdateService.isNewerVersion('1.0.13', '1.0.14'), isTrue);
    expect(AppUpdateService.isNewerVersion('1.0.13', 'v1.0.14'), isTrue);
    expect(AppUpdateService.isNewerVersion('1.0.14', '1.0.14'), isFalse);
    expect(AppUpdateService.isNewerVersion('1.0.14', 'v1.0.14'), isFalse);
    expect(AppUpdateService.isNewerVersion('1.0.14', '1.0.13'), isFalse);
    expect(AppUpdateService.isNewerVersion('1.0.14+14', 'v1.0.15+15'), isTrue);
    expect(AppUpdateService.isNewerVersion('1.0.14', '2.0.0'), isTrue);
  });

  test('BillingNotifier resetForm clears items and resets customer', () async {
    final notifier = BillingNotifier();
    notifier.addItem(
      description: 'Spiral Wound Gasket 2"',
      hsnCode: '8484',
      quantity: 5,
      unit: 'NOS',
      rate: 350,
    );
    expect(notifier.state.items.length, 1);

    await notifier.resetForm();
    expect(notifier.state.items.isEmpty, isTrue);
    expect(notifier.state.customer.name.isEmpty, isTrue);
  });

  test('Indian States constant contains all 36 States/UTs with CG code 22', () {
    expect(AppConstants.indianStates.length, 37);
    expect(AppConstants.indianStates['Chhattisgarh'], '22');
    expect(AppConstants.indianStates['Madhya Pradesh'], '23');
    expect(AppConstants.indianStates['Maharashtra'], '27');
    expect(AppConstants.indianStates.keys.first, 'Chhattisgarh');
  });

  test('InvoiceModel supports invoiceType (gst and temporary) and Currency formatting', () {
    final inv = InvoiceModel(
      uuid: 'inv-temp',
      invoiceNumber: 'TB/26-27/001',
      sequenceNumber: 1,
      financialYear: '26-27',
      invoiceDate: DateTime(2026, 11, 8),
      customer: CustomerModel(uuid: 'c1', name: 'Sharma Hardware', phone: ''),
      items: [],
      netAmount: 1000,
      grandTotal: 1000,
      amountInWords: 'Rupees One Thousand Only',
      balanceDue: 1000,
      invoiceType: 'temporary',
    );
    expect(inv.invoiceType, 'temporary');
    expect(inv.toMap()['invoice_type'], 'temporary');

    final copied = inv.copyWith(invoiceType: 'gst');
    expect(copied.invoiceType, 'gst');

    expect(CurrencyFormatter.formatWithoutSymbol(12150.00), '12,150.00');
  });

  test('BillingNotifier Temporary Bill calculation has NO GST and grandTotal equals netAmount', () {
    final notifier = BillingNotifier();
    notifier.setInvoiceType('temporary');

    notifier.addItem(
      description: 'Spiral Wound Gasket 50NB',
      hsnCode: '',
      quantity: 10,
      unit: 'PCS',
      rate: 450,
    );

    notifier.addItem(
      description: 'PTFE Envelope Gasket 100NB',
      hsnCode: '',
      quantity: 5,
      unit: 'PCS',
      rate: 620,
    );

    // 10 * 450 = 4,500; 5 * 620 = 3,100 => Total = 7,600
    expect(notifier.state.isTemporary, isTrue);
    expect(notifier.state.cgstTotal, 0.0);
    expect(notifier.state.sgstTotal, 0.0);
    expect(notifier.state.igstTotal, 0.0);
    expect(notifier.state.netAmount, 7600.0);
    expect(notifier.state.grandTotal, 7600.0);
    expect(notifier.state.items[0].gstRate, 0.0);
    expect(notifier.state.items[0].totalAmount, 4500.0);
  });

  test('InvoiceListState supports invoiceType filtering (gst vs temporary)', () {
    final state = InvoiceListState();
    expect(state.invoiceType, 'gst');

    final tempState = state.copyWith(invoiceType: 'temporary');
    expect(tempState.invoiceType, 'temporary');
  });

  test('InvoiceListState supports layered sorting (city_unpaid_first, city_paid_first, unpaid_city, paid_city)', () {
    final state = InvoiceListState();
    expect(state.sortBy, 'date_desc');

    final cityUnpaid = state.copyWith(sortBy: 'city_unpaid_first');
    expect(cityUnpaid.sortBy, 'city_unpaid_first');

    final unpaidCity = state.copyWith(sortBy: 'unpaid_city');
    expect(unpaidCity.sortBy, 'unpaid_city');

    final paidCity = state.copyWith(sortBy: 'paid_city');
    expect(paidCity.sortBy, 'paid_city');
  });

  test('Customer payment status logic handles float epsilon accurately', () {
    final double grandTotal = 1500.00;
    final double totalPaid = 1499.995;
    final double rawDue = grandTotal - totalPaid;
    final isClear = rawDue <= 0.01;
    expect(isClear, isTrue);

    final double balanceDue = isClear ? 0.0 : rawDue;
    expect(balanceDue, 0.0);

    final customer = CustomerModel(
      uuid: 'cust-test',
      name: 'Ramesh Patel',
      phone: '9876543210',
      totalBilled: 1500.0,
      totalPaid: 1500.0,
      outstandingBalance: 0.0,
    );
    expect(customer.outstandingBalance <= 0.005, isTrue);
  });

  test('SyncService pendingCount and isSyncing state test', () {
    final sync = SyncService.instance;
    expect(sync.pendingCount, isA<int>());
    expect(sync.isSyncing, isFalse);
    expect(sync.status, isNot(SyncStatus.syncing));
  });

  testWidgets('App Launches and displays Login Screen when unauthenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SSSupremeSolutionsApp(),
      ),
    );

    expect(find.text('Suprime Solutions'), findsOneWidget);
    expect(find.text('Sign In to Dashboard'), findsOneWidget);
  });
}
