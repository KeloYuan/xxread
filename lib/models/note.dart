class Note {
  final int? id;
  final int bookId;
  final int pageNumber;
  final String selectedText;
  final String noteText;
  final DateTime createDate;
  final DateTime? updateDate;

  Note({
    this.id,
    required this.bookId,
    required this.pageNumber,
    required this.selectedText,
    required this.noteText,
    DateTime? createDate,
    this.updateDate,
  }) : createDate = createDate ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'pageNumber': pageNumber,
      'selectedText': selectedText,
      'noteText': noteText,
      'createDate': createDate.millisecondsSinceEpoch,
      'updateDate': updateDate?.millisecondsSinceEpoch,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      bookId: map['bookId'],
      pageNumber: map['pageNumber'],
      selectedText: map['selectedText'],
      noteText: map['noteText'],
      createDate: DateTime.fromMillisecondsSinceEpoch(map['createDate']),
      updateDate: map['updateDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updateDate'])
          : null,
    );
  }

  Note copyWith({
    int? id,
    int? bookId,
    int? pageNumber,
    String? selectedText,
    String? noteText,
    DateTime? createDate,
    DateTime? updateDate,
  }) {
    return Note(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      pageNumber: pageNumber ?? this.pageNumber,
      selectedText: selectedText ?? this.selectedText,
      noteText: noteText ?? this.noteText,
      createDate: createDate ?? this.createDate,
      updateDate: updateDate ?? this.updateDate,
    );
  }
}