class BedsideContext {
  const BedsideContext({
    required this.hospital,
    required this.ward,
    required this.room,
  });

  final String hospital;
  final String ward;
  final String room;

  bool get verified =>
      hospital.isNotEmpty && ward.isNotEmpty && room.isNotEmpty;

  static const unverified = BedsideContext(hospital: '', ward: '', room: '');
}
