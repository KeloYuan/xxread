import 'package:flutter/material.dart';

import '../services/book_import_service.dart';
import 'reading_page_enhanced.dart';

class ImportBookPage extends StatefulWidget {
  const ImportBookPage({super.key});

  @override
  State<ImportBookPage> createState() => _ImportBookPageState();
}

class _ImportBookPageState extends State<ImportBookPage> {
  bool _isLoading = false;

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final book = await BookImportService().importBook();
      
      if (book != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ReadingPageEnhanced(book: book),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入书籍'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.file_upload_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              '选择电子书文件',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '支持 TXT、EPUB 格式',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickFile,
              icon: _isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
              label: Text(_isLoading ? '导入中...' : '选择文件'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}