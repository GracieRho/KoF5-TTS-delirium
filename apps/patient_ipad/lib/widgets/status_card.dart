import 'package:flutter/material.dart';

import '../models/bedside_status.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({required this.status, super.key});

  final BedsideStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(status.description, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
