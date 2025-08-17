import '../models/highlight.dart';
import 'database_service.dart';

class HighlightDao {
  final _dbService = DatabaseService();

  Future<int> insertHighlight(Highlight highlight) async {
    final db = await _dbService.database;
    return await db.insert('highlights', highlight.toMap());
  }

  Future<List<Highlight>> getHighlightsByBook(int bookId) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'highlights',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'pageNumber ASC, startOffset ASC',
    );
    return List.generate(maps.length, (i) => Highlight.fromMap(maps[i]));
  }

  Future<List<Highlight>> getHighlightsByPage(int bookId, int pageNumber) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'highlights',
      where: 'bookId = ? AND pageNumber = ?',
      whereArgs: [bookId, pageNumber],
      orderBy: 'startOffset ASC',
    );
    return List.generate(maps.length, (i) => Highlight.fromMap(maps[i]));
  }

  Future<void> deleteHighlight(int id) async {
    final db = await _dbService.database;
    await db.delete(
      'highlights',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Highlight>> searchHighlights(int bookId, String query) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'highlights',
      where: 'bookId = ? AND selectedText LIKE ?',
      whereArgs: [bookId, '%$query%'],
      orderBy: 'pageNumber ASC, startOffset ASC',
    );
    return List.generate(maps.length, (i) => Highlight.fromMap(maps[i]));
  }
}