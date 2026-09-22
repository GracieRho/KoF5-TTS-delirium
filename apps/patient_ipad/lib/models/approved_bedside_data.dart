import 'bedside_context.dart';
import 'schedule_item.dart';

class ApprovedBedsideData {
  const ApprovedBedsideData({required this.context, required this.schedule});

  final BedsideContext context;
  final List<ScheduleItem> schedule;
}
