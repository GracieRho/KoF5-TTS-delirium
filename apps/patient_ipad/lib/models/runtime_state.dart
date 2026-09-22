import 'bedside_status.dart';

class RuntimeState {
  const RuntimeState({required this.status, this.message});

  final BedsideStatus status;
  final String? message;
}
