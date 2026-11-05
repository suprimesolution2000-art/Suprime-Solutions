class AppConstants {
  static const String appName = 'Suprime Solutions';
  static const String appVersion = '1.0.17';
  static const int buildNumber = 17;
  static const String companyName = 'Suprime Solutions';
  static const String gstin = '22FWDPD2626D1Z7';
  static const String ePan = 'FWDPD2626D';
  static const String mobile = '9981365878';
  static const String address = 'Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001';
  static const String state = 'Chhattisgarh';
  static const String stateCode = '22';

  // Bank Info
  static const String bankName = 'Punjab National Bank';
  static const String bankAccountNumber = '1539050003087';
  static const String bankIfsc = 'PUNB0324500';

  // Units
  static const List<String> commonUnits = [
    'PCS',
    'NOS',
    'SET',
    'MTR',
    'KG',
    'BOX',
    'ROLL',
    'PAIR',
    'PKT',
    'LOT'
  ];

  // GST Rates
  static const List<double> gstRates = [
    0.0,
    5.0,
    12.0,
    18.0,
    28.0
  ];

  // Payment Methods
  static const List<String> paymentMethods = [
    'UPI',
    'Cash',
    'Bank Transfer',
    'Cheque',
    'Other'
  ];
}
