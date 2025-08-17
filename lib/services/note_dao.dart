import '../models/note.dart';
import 'database_service.dart';

class NoteDao {
  final _dbService = DatabaseService();

  Future<int> insertNote(Note note) async {
    final db = await _dbService.database;
    return await db.insert('notes', note.toMap());
  }

  Future<List<Note>> getNotesByBook(int bookId) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'createDate DESC',
    );
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  Future<List<Note>> getNotesByPage(int bookId, int pageNumber) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'bookId = ? AND pageNumber = ?',
      whereArgs: [bookId, pageNumber],
      orderBy: 'createDate DESC',
    );
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  Future<void> updateNote(Note note) async {
    final db = await _dbService.database;
    await db.update(
      'notes',
      note.copyWith(updateDate: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await _dbService.database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Note>> searchNotes(int bookId, String query) async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'bookId = ? AND (selectedText LIKE ? OR noteText LIKE ?)',
      whereArgs: [bookId, '%$query%', '%$query%'],
      orderBy: 'createDate DESC',
    );
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }
}