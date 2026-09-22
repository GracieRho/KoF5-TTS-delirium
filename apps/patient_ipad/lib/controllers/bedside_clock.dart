import 'dart:async';

import 'package:flutter/foundation.dart';

class BedsideClock extends ValueNotifier<DateTime> {
  BedsideClock({DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super((now ?? DateTime.now)()) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => value = _now());
  }

  final DateTime Function() _now;
  late final Timer _timer;

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
