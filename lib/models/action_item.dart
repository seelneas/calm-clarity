class ActionItem {
  final String id;
  final String entryId;
  final String description;
  final bool isCompleted;
  final DateTime? dueDate;

  ActionItem({
    required this.id,
    required this.entryId,
    required this.description,
    this.isCompleted = false,
    this.dueDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entryId': entryId,
      'description': description,
      'isCompleted': isCompleted ? 1 : 0,
      'dueDate': dueDate?.toIso8601String(),
    };
  }

  factory ActionItem.fromMap(Map<String, dynamic> map) {
    return ActionItem(
      id: map['id'],
      entryId: map['entryId'],
      description: map['description'],
      isCompleted: map['isCompleted'] == 1,
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
    );
  }
}
