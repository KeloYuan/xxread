class Book {
  final int? id;
  final String title;
  final String author;
  final String filePath; // 存储书籍文件的路径，而不是内容
  final String format;
  final int currentPage;
  final int totalPages; // 添加总页数字段
  final DateTime importDate;
  // 缓存相关字段
  final String? cachedContent;
  final String? cachedPages;
  final int? fileModifiedTime;
  final String? contentHash;
  final String? tableOfContents;

  Book({
    this.id,
    required this.title,
    this.author = '未知',
    required this.filePath,
    required this.format,
    this.currentPage = 0,
    this.totalPages = 1, // 默认总页数为1
    DateTime? importDate,
    this.cachedContent,
    this.cachedPages,
    this.fileModifiedTime,
    this.contentHash,
    this.tableOfContents,
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
      'cached_content': cachedContent,
      'cached_pages': cachedPages,
      'file_modified_time': fileModifiedTime,
      'content_hash': contentHash,
      'table_of_contents': tableOfContents,
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
      cachedContent: map['cached_content'],
      cachedPages: map['cached_pages'],
      fileModifiedTime: map['file_modified_time'],
      contentHash: map['content_hash'],
      tableOfContents: map['table_of_contents'],
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
    String? cachedContent,
    String? cachedPages,
    int? fileModifiedTime,
    String? contentHash,
    String? tableOfContents,
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
      cachedContent: cachedContent ?? this.cachedContent,
      cachedPages: cachedPages ?? this.cachedPages,
      fileModifiedTime: fileModifiedTime ?? this.fileModifiedTime,
      contentHash: contentHash ?? this.contentHash,
      tableOfContents: tableOfContents ?? this.tableOfContents,
    );
  }
}
