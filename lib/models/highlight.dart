import 'package:flutter/material.dart';

class Highlight {
  final int? id;
  final int bookId;
  final int pageNumber;
  final String selectedText;
  final int startOffset;
  final int endOffset;
  final Color color;
  final DateTime createDate;

  Highlight({
    this.id,
    required this.bookId,
    required this.pageNumber,
    required this.selectedText,
    required this.startOffset,
    required this.endOffset,
    required this.color,
    DateTime? createDate,
  }) : createDate = createDate ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'pageNumber': pageNumber,
      'selectedText': selectedText,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'colorValue': color.toARGB32(),
      'createDate': createDate.millisecondsSinceEpoch,
    };
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    return Highlight(
      id: map['id'],
      bookId: map['bookId'],
      pageNumber: map['pageNumber'],
      selectedText: map['selectedText'],
      startOffset: map['startOffset'],
      endOffset: map['endOffset'],
      color: Color(map['colorValue']),
      createDate: DateTime.fromMillisecondsSinceEpoch(map['createDate']),
    );
  }

  // 预定义的荧光笔颜色
  static const List<Color> highlightColors = [
    Color(0xFFFFEB3B), // 黄色
    Color(0xFF4CAF50), // 绿色
    Color(0xFF2196F3), // 蓝色
    Color(0xFFF44336), // 红色
    Color(0xFF9C27B0), // 紫色
    Color(0xFFFF9800), // 橙色
  ];

  static String getColorName(Color color) {
    switch (color.toARGB32()) {
      case 0xFFFFEB3B:
        return '黄色';
      case 0xFF4CAF50:
        return '绿色';
      case 0xFF2196F3:
        return '蓝色';
      case 0xFFF44336:
        return '红色';
      case 0xFF9C27B0:
        return '紫色';
      case 0xFFFF9800:
        return '橙色';
      default:
        return '自定义';
    }
  }
}