import 'package:flutter/material.dart';

void main() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0);
  print(start);
  print(end);
  final range = DateTimeRange(start: start, end: end);
  print(range);
}
