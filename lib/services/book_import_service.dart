import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xxread/services/book_dao.dart';
import 'package:epubx/epubx.dart';
import 'package:pdfx/pdfx.dart';

import '../models/book.dart';

class BookImportService {
  final _bookDao = BookDao();

  Future<Book?> importBook() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub', 'pdf', 'mobi', 'azw', 'azw3', 'fb2', 'rtf', 'doc', 'docx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.first;
        
        // 1. Get application documents directory
        final documentsDir = await getApplicationDocumentsDirectory();
        final booksDir = Directory(join(documentsDir.path, 'books'));
        if (!await booksDir.exists()) {
          await booksDir.create(recursive: true);
        }

        // 2. Save the file to disk
        final newFilePath = join(booksDir.path, pickedFile.name);
        final file = File(newFilePath);
        await file.writeAsBytes(pickedFile.bytes!);

        debugPrint('Book file saved to: $newFilePath');

        // 3. Get book metadata
        String title = pickedFile.name.replaceAll(RegExp(r'\.(txt|epub|pdf|mobi|azw|azw3|fb2|rtf|doc|docx)$'), '');
        String author = 'Unknown';
        int estimatedPages = 1;
        
        // Try to get more detailed information from the file
        try {
          final extension = pickedFile.extension?.toLowerCase();
          switch (extension) {
            case 'epub':
              final epubBook = await EpubReader.readBook(pickedFile.bytes!);
              title = epubBook.Title ?? title;
              author = epubBook.Author ?? author;
              
              // Estimate pages based on content length
              final content = await _getAllEpubContent(epubBook);
              final contentLength = content.length;
              estimatedPages = (contentLength / 1500).ceil().clamp(1, 9999); // Approx. 1500 chars per page
              break;
              
            case 'txt':
            case 'rtf':
              final content = String.fromCharCodes(pickedFile.bytes!);
              estimatedPages = (content.length / 1500).ceil().clamp(1, 9999);
              break;
              
            case 'pdf':
              // For PDF files, use PDFx to get accurate page count
              try {
                final pdfDocument = await PdfDocument.openData(pickedFile.bytes!);
                estimatedPages = pdfDocument.pagesCount;
                await pdfDocument.close();
              } catch (e) {
                debugPrint('Could not parse PDF: $e');
                // Fallback to file size estimation
                final fileSize = pickedFile.bytes!.length;
                estimatedPages = (fileSize / 50000).ceil().clamp(1, 9999); // Approx 50KB per page
              }
              break;
              
            case 'mobi':
            case 'azw':
            case 'azw3':
              // Amazon formats - basic estimation
              final fileSize = pickedFile.bytes!.length;
              estimatedPages = (fileSize / 5000).ceil().clamp(1, 9999); // Approx 5KB per page (more compressed)
              break;
              
            case 'fb2':
              // FictionBook format - XML based
              try {
                final content = String.fromCharCodes(pickedFile.bytes!);
                final textContent = _stripXmlTags(content);
                estimatedPages = (textContent.length / 1500).ceil().clamp(1, 9999);
              } catch (e) {
                final fileSize = pickedFile.bytes!.length;
                estimatedPages = (fileSize / 8000).ceil().clamp(1, 9999);
              }
              break;
              
            case 'doc':
            case 'docx':
              // Microsoft Word formats - basic estimation
              final fileSize = pickedFile.bytes!.length;
              estimatedPages = (fileSize / 30000).ceil().clamp(1, 9999); // Approx 30KB per page
              break;
              
            default:
              final fileSize = pickedFile.bytes!.length;
              estimatedPages = (fileSize / 10000).ceil().clamp(1, 9999); // Default estimation
          }
        } catch (e) {
          debugPrint('Could not get detailed info: $e');
        }
        
        // 4. Create Book object
        final book = Book(
          title: title,
          author: author,
          filePath: newFilePath,
          format: pickedFile.extension?.toUpperCase() ?? 'UNKNOWN',
          totalPages: estimatedPages,
        );

        // 5. Insert metadata into the database
        final bookId = await _bookDao.insertBook(book);
        debugPrint('Book metadata inserted with ID: $bookId, estimated pages: $estimatedPages');

        return book.copyWith(id: bookId);
      }
    } catch (e) {
      debugPrint('Import process failed: $e');
      rethrow;
    }
    return null;
  }

  // Recursively get all EPUB chapter content
  Future<String> _getAllEpubContent(EpubBook book) async {
    final buffer = StringBuffer();
    // Using book.Content is often more reliable for getting all text content
    if (book.Content != null) {
      // Iterate over all HTML files
      final htmlFiles = book.Content!.Html;
      if (htmlFiles != null) {
        for (var entry in htmlFiles.entries) {
          final htmlContent = entry.value.Content;
          if (htmlContent != null && htmlContent.isNotEmpty) {
            buffer.writeln(_stripHtml(htmlContent));
          }
        }
      }
    }
    return buffer.toString();
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripXmlTags(String xml) {
    return xml
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'&[a-zA-Z0-9#]+;'), ' ') // Remove XML entities
        .trim();
  }
}
