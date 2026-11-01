import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_billing/main.dart';
import 'package:mobile_billing/core/utils/number_to_words.dart';
import 'package:mobile_billing/core/utils/currency_formatter.dart';

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

  testWidgets('App Launches and displays Suprime Solutions title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SSSupremeSolutionsApp(),
      ),
    );

    expect(find.text('Suprime Solutions'), findsOneWidget);
    expect(find.text('CREATE NEW BILL'), findsOneWidget);
  });
}
