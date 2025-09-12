import 'database_service.dart';

class ReadingStatsDao {
  final dbService = DatabaseService();

  Future<void> insertReadingTime(DateTime date, int durationInSeconds) async {
    final db = await dbService.database;
    final dateString = date.toIso8601String().split('T').first;

    // Check if a record for this date already exists
    final existing = await db.query(
      'reading_stats',
      where: 'date = ?',
      whereArgs: [dateString],
    );

    if (existing.isNotEmpty) {
      // Update existing record
      final newDuration = (existing.first['durationInSeconds'] as int) + durationInSeconds;
      await db.update(
        'reading_stats',
        {'durationInSeconds': newDuration},
        where: 'date = ?',
        whereArgs: [dateString],
      );
    } else {
      // Insert new record
      await db.insert('reading_stats', {
        'date': dateString,
        'durationInSeconds': durationInSeconds,
      });
    }
  }

  Future<Map<String, int>> getSummaryStats() async {
    final db = await dbService.database;
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    // Total
    final totalResult = await db.rawQuery('SELECT SUM(durationInSeconds) as total FROM reading_stats');
    final totalDuration = (totalResult.first['total'] as int?) ?? 0;

    // Today
    final todayResult = await db.query(
      'reading_stats',
      columns: ['durationInSeconds'],
      where: 'date = ?',
      whereArgs: [today.toIso8601String().split('T').first],
    );
    final todayDuration = todayResult.isNotEmpty ? (todayResult.first['durationInSeconds'] as int) : 0;

    // This week
    final weekResult = await db.rawQuery(
      'SELECT SUM(durationInSeconds) as total FROM reading_stats WHERE date >= ?',
      [weekStart.toIso8601String().split('T').first]
    );
    final weekDuration = (weekResult.first['total'] as int?) ?? 0;

    return {
      'total': totalDuration,
      'today': todayDuration,
      'week': weekDuration,
    };
  }

  Future<List<Map<String, dynamic>>> getWeeklyChartData() async {
    final db = await dbService.database;
    final List<Map<String, dynamic>> chartData = [];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateString = date.toIso8601String().split('T').first;
      final result = await db.query(
        'reading_stats',
        columns: ['durationInSeconds'],
        where: 'date = ?',
        whereArgs: [dateString],
      );
      final duration = result.isNotEmpty ? (result.first['durationInSeconds'] as int) : 0;
      chartData.add({
        'day': date.weekday,
        'duration': duration,
      });
    }
    return chartData;
  }

  Future<Map<String, dynamic>> getAchievementStats() async {
    final db = await dbService.database;
    final today = DateTime.now();
    
    // 获取连续阅读天数
    int consecutiveDays = 0;
    for (int i = 0; i < 30; i++) {
      final date = today.subtract(Duration(days: i));
      final dateString = date.toIso8601String().split('T').first;
      final result = await db.query(
        'reading_stats',
        where: 'date = ? AND durationInSeconds > 0',
        whereArgs: [dateString],
      );
      if (result.isNotEmpty) {
        consecutiveDays++;
      } else {
        break;
      }
    }
    
    // 获取单次最长阅读时间（分钟）
    final maxSessionResult = await db.rawQuery(
      'SELECT MAX(durationInSeconds) as maxDuration FROM reading_stats'
    );
    final maxDuration = (maxSessionResult.first['maxDuration'] as int?) ?? 0;
    
    return {
      'consecutiveDays': consecutiveDays,
      'maxSessionMinutes': (maxDuration / 60).round(),
    };
  }

  // 获取指定日期范围内的每日统计数据
  Future<List<Map<String, dynamic>>> getDailyStatsRange(DateTime startDate, DateTime endDate) async {
    final db = await dbService.database;
    
    final startDateStr = startDate.toIso8601String().split('T').first;
    final endDateStr = endDate.toIso8601String().split('T').first;
    
    final result = await db.query(
      'reading_stats',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDateStr, endDateStr],
      orderBy: 'date ASC',
    );
    
    // 转换为统一格式，添加缺失的字段
    return result.map((row) => {
      'date': row['date'],
      'duration': row['durationInSeconds'], // 保持秒为单位，在上层转换
      'pages': 0, // 由于当前数据库结构中没有页数记录，暂时设为0
      'books_read': 0, // 由于当前数据库结构中没有完成书籍记录，暂时设为0
    }).toList();
  }
}