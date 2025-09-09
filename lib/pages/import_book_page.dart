import 'dart:ui';
import 'package:flutter/material.dart';

import '../services/book_import_service.dart';
import '../utils/color_extensions.dart';
import '../utils/glass_config.dart';
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          '导入书籍',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: GlassEffectConfig.createProgressiveAppBar(
          context: context,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            stops: const [0.0, 0.4, 0.8, 1.0],
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacityValues(0.18),
              Theme.of(context).colorScheme.surface.withOpacityValues(0.95),
              Theme.of(context).colorScheme.secondaryContainer.withOpacityValues(0.12),
              Theme.of(context).colorScheme.tertiaryContainer.withOpacityValues(0.08),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 使用渐进模糊效果的卡片包装内容
              Padding(
                padding: const EdgeInsets.all(32),
                child: GlassEffectConfig.createProgressiveCard(
                  context: context,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacityValues(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.file_upload_outlined,
                              size: 60,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '选择电子书文件',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '支持 TXT、EPUB 格式',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacityValues(0.7),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}