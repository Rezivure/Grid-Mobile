class SharingWindow {
  final String label;
  final List<int> days; // e.g. 0 for Mon, 1 for Tue, ...
  final bool isAllDay;
  final String? startTime; // "09:00"
  final String? endTime;   // "17:00"
  final bool isActive;     // <--- new field

  SharingWindow({
    required this.label,
    required this.days,
    required this.isAllDay,
    required this.isActive,
    this.startTime,
    this.endTime,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'days': days,
    'isAllDay': isAllDay,
    'startTime': startTime,
    'endTime': endTime,
    'isActive': isActive,
  };

  factory SharingWindow.fromJson(Map<String, dynamic> json) => SharingWindow(
    label: json['label'] as String,
    days: (json['days'] as List<dynamic>).map((e) => e as int).toList(),
    isAllDay: json['isAllDay'] as bool,
    startTime: json['startTime'] as String?,
    endTime: json['endTime'] as String?,
    isActive: json['isActive'] == null
        ? true
        : json['isActive'] as bool,
  );
}
