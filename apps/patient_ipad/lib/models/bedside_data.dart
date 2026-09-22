import 'bedside_context.dart';
import 'bedside_status.dart';
import 'schedule_item.dart';

class BedsideData {
  const BedsideData({
    required this.context,
    required this.schedule,
    required this.status,
    this.message,
  });

  final BedsideContext context;
  final List<ScheduleItem> schedule;
  final BedsideStatus status;
  final String? message;

  BedsideData withRuntime({
    required BedsideStatus status,
    String? message,
    BedsideContext? context,
    List<ScheduleItem>? schedule,
  }) => BedsideData(
    context: context ?? this.context,
    schedule: schedule ?? this.schedule,
    status: status,
    message: message ?? this.message,
  );

  static const unverified = BedsideData(
    context: BedsideContext.unverified,
    schedule: [],
    status: BedsideStatus.waiting,
    message: '확인된 병실 안내가 아직 없습니다.',
  );
}
