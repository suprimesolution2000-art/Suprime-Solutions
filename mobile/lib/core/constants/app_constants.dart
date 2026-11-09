class AppConstants {
  static const String appName = 'Suprime Solutions';
  static const String appVersion = '1.0.31';
  static const int buildNumber = 31;
  static const String companyName = 'Suprime Solutions';
  static const String gstin = '22FWDPD2626D1Z7';
  static const String ePan = 'FWDPD2626D';
  static const String mobile = '9981365878';
  static const String address = 'Mahalaxmi Bole, Beside Yashoda Dairy, Tikrapara, Bilaspur (C.G.) 495001';
  static const String state = 'Chhattisgarh';
  static const String stateCode = '22';
  static const String defaultCity = 'Bilaspur';
  static const String defaultState = 'Chhattisgarh';
  static const String defaultStateCode = '22';

  // All 36 Indian States & Union Territories with official GST State Codes
  static const Map<String, String> indianStates = {
    'Chhattisgarh': '22',
    'Andaman & Nicobar Islands': '35',
    'Andhra Pradesh': '37',
    'Arunachal Pradesh': '12',
    'Assam': '18',
    'Bihar': '10',
    'Chandigarh': '04',
    'Dadra & Nagar Haveli and Daman & Diu': '26',
    'Delhi': '07',
    'Goa': '30',
    'Gujarat': '24',
    'Haryana': '06',
    'Himachal Pradesh': '02',
    'Jammu and Kashmir': '01',
    'Jharkhand': '20',
    'Karnataka': '29',
    'Kerala': '32',
    'Ladakh': '38',
    'Lakshadweep': '31',
    'Madhya Pradesh': '23',
    'Maharashtra': '27',
    'Manipur': '14',
    'Meghalaya': '17',
    'Mizoram': '15',
    'Nagaland': '13',
    'Odisha': '21',
    'Puducherry': '34',
    'Punjab': '03',
    'Rajasthan': '08',
    'Sikkim': '11',
    'Tamil Nadu': '33',
    'Telangana': '36',
    'Tripura': '16',
    'Uttar Pradesh': '09',
    'Uttarakhand': '05',
    'West Bengal': '19',
    'Other Territory': '97',
  };

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
