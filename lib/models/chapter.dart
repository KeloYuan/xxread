class Chapter {
  final String title;
  int startPage; // Changed to non-final to allow updating after pagination
  final int endPage;
  final int level; // 章节层级，0=一级章节，等等
  final String? contentFileName; // Added for EPUB chapter mapping
  final String? anchor; // Added for EPUB chapter mapping

  Chapter({
    required this.title,
    required this.startPage,
    this.endPage = 0,
    this.level = 0,
    this.contentFileName,
    this.anchor,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'startPage': startPage,
      'endPage': endPage,
      'level': level,
      'contentFileName': contentFileName,
      'anchor': anchor,
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      title: map['title'] ?? '',
      startPage: map['startPage'] ?? 0,
      endPage: map['endPage'] ?? 0,
      level: map['level'] ?? 0,
      contentFileName: map['contentFileName'],
      anchor: map['anchor'],
    );
  }

  @override
  String toString() {
    return 'Chapter{title: $title, startPage: $startPage, endPage: $endPage, level: $level}';
  }
}
