class Book {
  final int? id;
  final String title;
  final String author;
  final String filePath; // 存储书籍文件的路径，而不是内容
  final String format;
  final int currentPage;
  final int totalPages; // 添加总页数字段
  final DateTime importDate;

  Book({
    this.id,
    required this.title,
    this.author = '未知',
    required this.filePath,
    required this.format,
    this.currentPage = 0,
    this.totalPages = 1, // 默认总页数为1
    DateTime? importDate,
  }) : importDate = importDate ?? DateTime.now();

  // content 字段已被移除

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'filePath': filePath,
      'format': format,
      'currentPage': currentPage,
      'totalPages': totalPages,
      'importDate': importDate.millisecondsSinceEpoch,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'],
      title: map['title'],
      author: map['author'] ?? '未知',
      filePath: map['filePath'],
      format: map['format'],
      currentPage: map['currentPage'] ?? 0,
      totalPages: map['totalPages'] ?? 1,
      importDate: DateTime.fromMillisecondsSinceEpoch(map['importDate']),
    );
  }

  Book copyWith({
    int? id,
    String? title,
    String? author,
    String? filePath,
    String? format,
    int? currentPage,
    int? totalPages,
    DateTime? importDate,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      importDate: importDate ?? this.importDate,
    );
  }
}
