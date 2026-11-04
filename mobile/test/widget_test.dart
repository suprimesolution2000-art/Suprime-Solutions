import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_billing/main.dart';
import 'package:mobile_billing/core/utils/number_to_words.dart';
import 'package:mobile_billing/core/utils/currency_formatter.dart';
import 'package:mobile_billing/data/models/invoice_model.dart';
import 'package:mobile_billing/data/models/customer_model.dart';
import 'package:mobile_billing/data/models/invoice_item_model.dart';
import 'package:mobile_billing/services/updater/app_update_service.dart';

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
