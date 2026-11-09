class CityHelper {
  static const List<String> commercialCities = [
    'Bilaspur',
    'Raipur',
    'Durg',
    'Bhilai',
    'Korba',
    'Rajnandgaon',
    'Raigarh',
    'Jagdalpur',
    'Ambikapur',
    'Dhamtari',
    'Mahasamund',
    'Champa',
    'Janjgir',
    'Bhatapara',
    'Kawardha',
    'Kanker',
    'Balod',
    'Bemetara',
    'Mungeli',
    'Kondagaon',
    'Gariaband',
    'Surajpur',
    'Balrampur',
    'Jashpur',
    'Sukma',
    'Bijapur',
    'Narayanpur',
    'Gaurela-Pendra-Marwahi',
    'Manendragarh',
    'Sakti',
    'Sarangarh',
    'Khairagarh',
    'Mohla-Manpur',
    'Takhatpur',
    'Ratanpur',
    'Tilda-Neora',
    'Kota',
    'Simga',
    'Arang',
    'Abhanpur',
    'Birgaon',
    'Kumhari',
    'Patan',
    'Dongargarh',
    'Katghora',
    'Dipka',
    'Kharsia',
    'Gharghoda',
    'Nagpur',
    'Kolkata',
    'Mumbai',
    'Delhi',
    'Hyderabad',
    'Bhubaneswar',
    'Rourkela',
    'Jharsuguda',
    'Cuttack',
    'Indore',
    'Jabalpur',
  ];

  /// Extracts the true city from explicit city or address text.
  /// If city was previously defaulted to 'Bilaspur', but address mentions another city
  /// (e.g. "Pandri, Raipur"), it accurately extracts and returns "Raipur".
  static String extractCity(String? city, String? address) {
    final cleanCity = (city ?? '').trim();
    final cleanAddress = (address ?? '').trim();

    // 1. If explicit city is specified other than empty or Bilaspur, use it.
    if (cleanCity.isNotEmpty && cleanCity.toLowerCase() != 'bilaspur') {
      return _formatCity(cleanCity);
    }

    // 2. Check if the address contains any known city (longer names checked first)
    if (cleanAddress.isNotEmpty) {
      final addrLower = cleanAddress.toLowerCase();
      final sortedCities = List<String>.from(commercialCities)
        ..sort((a, b) => b.length.compareTo(a.length));

      for (final c in sortedCities) {
        final pattern = RegExp(r'\b' + RegExp.escape(c.toLowerCase()) + r'\b');
        if (pattern.hasMatch(addrLower)) {
          return c;
        }
      }

      // Check comma-separated tokens in address
      final parts = cleanAddress.split(RegExp(r'[,;\n]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      for (final part in parts.reversed) {
        if (RegExp(r'^\d+$').hasMatch(part)) continue;
        final cleanPart = part.replaceAll(RegExp(r'\b(chhattisgarh|c\.g\.|cg|india|\d{6})\b', caseSensitive: false), '').trim();
        if (cleanPart.isNotEmpty) {
          for (final c in commercialCities) {
            if (c.toLowerCase() == cleanPart.toLowerCase()) {
              return c;
            }
          }
        }
      }
    }

    // 3. Fallback to explicit city or 'Bilaspur'
    if (cleanCity.isNotEmpty) {
      return _formatCity(cleanCity);
    }

    return 'Bilaspur';
  }

  static String _formatCity(String c) {
    if (c.isEmpty) return 'Bilaspur';
    for (final known in commercialCities) {
      if (known.toLowerCase() == c.toLowerCase()) return known;
    }
    return c.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : '').join(' ');
  }
}
