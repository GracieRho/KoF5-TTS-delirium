class ScheduleItem {
  const ScheduleItem({
    required this.timeLabel,
    required this.title,
    this.description,
    this.isCurrent = false,
  });

  final String timeLabel;
  final String title;
  final String? description;
  final bool isCurrent;
}
