import 'package:flutter/material.dart';

class GenderMarkData {
  const GenderMarkData({required this.symbol, required this.color});

  final String symbol;
  final Color color;
}

GenderMarkData? genderMark(String? value) {
  return switch (_nonEmpty(value)?.toLowerCase()) {
    'male' ||
    'm' ||
    'man' => const GenderMarkData(symbol: '♂', color: Color(0xFF5AA7FF)),
    'female' ||
    'f' ||
    'woman' => const GenderMarkData(symbol: '♀', color: Color(0xFFFF6F8F)),
    _ => null,
  };
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
