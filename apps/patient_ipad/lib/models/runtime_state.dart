import 'bedside_context.dart';
import 'bedside_status.dart';
import 'schedule_item.dart';

class RuntimeState {
  const RuntimeState({
    required this.status,
    this.message,
    this.context,
    this.schedule,
  });

  final BedsideStatus status;
  final String? message;
  final BedsideContext? context;
  final List<ScheduleItem>? schedule;
}
