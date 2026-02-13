import 'package:positioning_core/positioning_core.dart';

class CampusLevelIdCodec implements LevelIdCodec {
  const CampusLevelIdCodec();

  @override
  int? tryParseIndex(String levelId) {
    final s = levelId.trim().toUpperCase();

    if (s == 'GF' || s == 'G' || s == 'GROUND') return 0;

    if (s.startsWith('B')) {
      final n = int.tryParse(s.substring(1));
      if (n == null) return null;
      return -n;
    }

    if (s.startsWith('F')) {
      final n = int.tryParse(s.substring(1));
      return n;
    }

    return int.tryParse(s); // fallback
  }

  @override
  String formatIndex(int index) {
    if (index == 0) return 'GF';
    if (index < 0) return 'B${-index}';
    return 'F$index';
  }
}
