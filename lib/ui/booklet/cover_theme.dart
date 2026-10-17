import 'dart:ui';

class CoverTheme {
  const CoverTheme({
    required this.paper,
    required this.ink,
    required this.band,
  });

  final Color paper;
  final Color ink;
  final List<Color> band;
}

const _byCountry = <String, CoverTheme>{
  'JP': CoverTheme(
    paper: Color(0xFF7A1423),
    ink: Color(0xFFF4EFE6),
    band: [Color(0xFFF4EFE6), Color(0xFFBC002D)],
  ),
  'TW': CoverTheme(
    paper: Color(0xFF14206B),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFC1121F), Color(0xFFF2F2F2)],
  ),
  'KR': CoverTheme(
    paper: Color(0xFF0F2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFCD2E3A), Color(0xFFF2F2F2), Color(0xFF0047A0)],
  ),
  'CN': CoverTheme(
    paper: Color(0xFF8B1A1A),
    ink: Color(0xFFF2C230),
    band: [Color(0xFFDE2910), Color(0xFFFFDE00)],
  ),
  'HK': CoverTheme(
    paper: Color(0xFF9B1B24),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFDE2910), Color(0xFFF2F2F2)],
  ),
  'SG': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFEF3340), Color(0xFFFFFFFF)],
  ),
  'TH': CoverTheme(
    paper: Color(0xFF1F2D5C),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFA51931), Color(0xFFF4F5F8), Color(0xFF2D2A4A)],
  ),
  'VN': CoverTheme(
    paper: Color(0xFF8B1A1A),
    ink: Color(0xFFFFCD00),
    band: [Color(0xFFDA251D), Color(0xFFFFCD00)],
  ),
  'MY': CoverTheme(
    paper: Color(0xFF1A2A66),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFCC0001), Color(0xFFF2F2F2), Color(0xFFFFCC00)],
  ),
  'ID': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFCE1126), Color(0xFFFFFFFF)],
  ),
  'PH': CoverTheme(
    paper: Color(0xFF0A2A66),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF0038A8), Color(0xFFF2F2F2), Color(0xFFCE1126)],
  ),
  'IN': CoverTheme(
    paper: Color(0xFF0F4A2A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
  ),
  'AU': CoverTheme(
    paper: Color(0xFF0B1F4D),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF00008B), Color(0xFFFFFFFF), Color(0xFFE4002B)],
  ),
  'NZ': CoverTheme(
    paper: Color(0xFF0B1F4D),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF00247D), Color(0xFFFFFFFF), Color(0xFFCC142B)],
  ),
  'US': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFB22234), Color(0xFFFFFFFF), Color(0xFF3C3B6E)],
  ),
  'CA': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFD52B1E), Color(0xFFFFFFFF)],
  ),
  'GB': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFC8102E), Color(0xFFFFFFFF), Color(0xFF012169)],
  ),
  'FR': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF0055A4), Color(0xFFFFFFFF), Color(0xFFEF4135)],
  ),
  'DE': CoverTheme(
    paper: Color(0xFF1B1B1B),
    ink: Color(0xFFE0B43A),
    band: [Color(0xFF000000), Color(0xFFDD0000), Color(0xFFFFCE00)],
  ),
  'IT': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF009246), Color(0xFFFFFFFF), Color(0xFFCE2B37)],
  ),
  'ES': CoverTheme(
    paper: Color(0xFF8B1A1A),
    ink: Color(0xFFFFC400),
    band: [Color(0xFFAA151B), Color(0xFFF1BF00), Color(0xFFAA151B)],
  ),
  'PT': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFFFE000),
    band: [Color(0xFF006600), Color(0xFFFF0000)],
  ),
  'NL': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFAE1C28), Color(0xFFFFFFFF), Color(0xFF21468B)],
  ),
  'BE': CoverTheme(
    paper: Color(0xFF1B1B1B),
    ink: Color(0xFFFAE042),
    band: [Color(0xFF000000), Color(0xFFFAE042), Color(0xFFED2939)],
  ),
  'CH': CoverTheme(
    paper: Color(0xFF9B1B24),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFDA291C), Color(0xFFFFFFFF)],
  ),
  'AT': CoverTheme(
    paper: Color(0xFF9B1B24),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFED2939), Color(0xFFFFFFFF), Color(0xFFED2939)],
  ),
  'SE': CoverTheme(
    paper: Color(0xFF0B3A66),
    ink: Color(0xFFFECC00),
    band: [Color(0xFF006AA7), Color(0xFFFECC00)],
  ),
  'NO': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFBA0C2F), Color(0xFFFFFFFF), Color(0xFF00205B)],
  ),
  'DK': CoverTheme(
    paper: Color(0xFF9B1B24),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFC8102E), Color(0xFFFFFFFF)],
  ),
  'FI': CoverTheme(
    paper: Color(0xFF123B7A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF003580), Color(0xFFFFFFFF)],
  ),
  'IE': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF169B62), Color(0xFFFFFFFF), Color(0xFFFF883E)],
  ),
  'CZ': CoverTheme(
    paper: Color(0xFF1B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFFFFFFF), Color(0xFFD7141A), Color(0xFF11457E)],
  ),
  'PL': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFFFFFFF), Color(0xFFDC143C)],
  ),
  'HU': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFCE2939), Color(0xFFFFFFFF), Color(0xFF477050)],
  ),
  'GR': CoverTheme(
    paper: Color(0xFF0D3B7A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF0D5EAF), Color(0xFFFFFFFF)],
  ),
  'TR': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFFFFFFF),
    band: [Color(0xFFE30A17), Color(0xFFFFFFFF)],
  ),
  'MX': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF006847), Color(0xFFFFFFFF), Color(0xFFCE1126)],
  ),
  'BR': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFFFDF00),
    band: [Color(0xFF009C3B), Color(0xFFFFDF00), Color(0xFF002776)],
  ),
  'AR': CoverTheme(
    paper: Color(0xFF2B6A9A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF74ACDF), Color(0xFFFFFFFF), Color(0xFFF6B40E)],
  ),
  'ZA': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFFFB612),
    band: [Color(0xFF007749), Color(0xFFFFB612), Color(0xFFDE3831)],
  ),
  'EG': CoverTheme(
    paper: Color(0xFF8F1D28),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFCE1126), Color(0xFFFFFFFF), Color(0xFF000000)],
  ),
  'MA': CoverTheme(
    paper: Color(0xFF8B1A1A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFFC1272D), Color(0xFF006233)],
  ),
  'IS': CoverTheme(
    paper: Color(0xFF0B2A5A),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF02529C), Color(0xFFFFFFFF), Color(0xFFDC1E35)],
  ),
  'AE': CoverTheme(
    paper: Color(0xFF1E4D2B),
    ink: Color(0xFFF2F2F2),
    band: [Color(0xFF00732F), Color(0xFFFFFFFF), Color(0xFF000000)],
  ),
};

const _kraft = [
  Color(0xFFC79F73),
  Color(0xFF9AA58F),
  Color(0xFF9DA9B8),
  Color(0xFFBA9C98),
  Color(0xFFB9A877),
  Color(0xFF8E9AA8),
];

const _plainBand = [Color(0xFF55585A)];

const _plainInk = Color(0xFF2B2B2B);

CoverTheme coverThemeFor(String? country) {
  final known = country == null ? null : _byCountry[country];
  if (known != null) return known;
  final seed = (country ?? '').codeUnits.fold(0, (n, c) => n * 31 + c);
  return CoverTheme(
    paper: _kraft[country == null ? 0 : seed % _kraft.length],
    ink: _plainInk,
    band: _plainBand,
  );
}

bool hasCoverTheme(String code) => _byCountry.containsKey(code);

int get coverThemeCount => _byCountry.length;
