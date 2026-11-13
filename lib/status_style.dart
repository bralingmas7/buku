import 'package:flutter/material.dart';

import 'models.dart';

const kHijau = Color(0xFF2E7D32);
const kKuning = Color(0xFFF9A825);
const kMerah = Color(0xFFC62828);
const kAbu = Color(0xFF757575);

Color statusColor(DebtStatus s) {
  switch (s) {
    case DebtStatus.lunas:
      return kAbu;
    case DebtStatus.lancar:
      return kHijau;
    case DebtStatus.mendekati:
      return kKuning;
    case DebtStatus.telat:
      return kMerah;
  }
}
