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

  BedsideData withRuntime({required BedsideStatus status, String? message}) =>
      BedsideData(
        context: context,
        schedule: schedule,
        status: status,
        message: message ?? this.message,
      );

  static const preview = BedsideData(
    context: BedsideContext(hospital: '한마음병원', ward: '5병동', room: '501호'),
    schedule: [
      ScheduleItem(timeLabel: '오전 8:00', title: '아침 식사'),
      ScheduleItem(
        timeLabel: '오전 10:30',
        title: '회진',
        description: '담당 의료진이 병실로 방문합니다.',
        isCurrent: true,
      ),
      ScheduleItem(timeLabel: '오후 12:00', title: '점심 식사'),
      ScheduleItem(timeLabel: '오후 3:00', title: '검사 예정'),
    ],
    status: BedsideStatus.listening,
    message: '오늘은 병원에서 치료를 받으며 쉬는 날입니다.',
  );
}
