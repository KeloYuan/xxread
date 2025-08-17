import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../services/book_dao.dart';
import '../services/reading_stats_dao.dart';

class ReadingPageEnhanced extends StatefulWidget {
  final Book book;
  const ReadingPageEnhanced({super.key, required this.book});

  @override
  State<ReadingPageEnhanced> createState() => _ReadingPageEnhancedState();
}

class _ReadingPageEnhancedState extends State<ReadingPageEnhanced> {
  // --- DAOs & Controllers ---
  late final PageController _pageController;
  final _bookDao = BookDao();
  final _statsDao = ReadingStatsDao();

  // --- Content & Pages ---
  List<String> _pages = [];
  String _bookContent = '';
  int _currentPageIndex = 0;

  // --- UI State ---
  bool _showControls = false; // 默认隐藏工具栏
  Timer? _hideControlsTimer;
  DateTime? _sessionStartTime;

  // --- Reading Settings ---
  double _fontSize = 18.0;
  double _lineSpacing = 1.8;
  double _letterSpacing = 0.2;
  double _pageMargin = 16.0;
  Color _backgroundColor = Colors.white;
  Color _fontColor = Colors.black87;
  bool _autoScroll = false;
  bool _keepScreenOn = false;
  String _fontFamily = 'System';

  // --- UI Text Prefix ---
  static const String _kLoadingPrefix = '📚';
  static const String _kErrorPrefix = '❌';

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.book.currentPage;
    _pageController = PageController(initialPage: _currentPageIndex);
    _sessionStartTime = DateTime.now();

    // 进入沉浸式模式
    _setImmersiveMode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeReading();
    });
  }

  Future<void> _initializeReading() async {
    try {
      if (mounted) {
        setState(() => _pages = ['$_kLoadingPrefix 正在加载书籍...']);
      }

      await _loadSettings();
      await _loadBookContent();

      if (_bookContent.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          _splitIntoPages();
        }

        if (_pages.isEmpty || _pages.first.startsWith(_kLoadingPrefix)) {
          throw Exception('分页失败，无法生成有效页面');
        }

        if (mounted) setState(() {});
      } else {
        throw Exception('书籍内容为空，无法加载');
      }
    } catch (e) {
      debugPrint('书籍初始化失败: $e');
      if (mounted) {
        setState(() => _pages = ['$_kErrorPrefix 书籍加载失败: $e\n\n请检查文件是否存在或格式是否正确']);
      }
    }
  }

  Future<void> _loadBookContent() async {
    final file = File(widget.book.filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: ${widget.book.filePath}');
    }

    final fileExtension = widget.book.format.toLowerCase();

    try {
      if (fileExtension == 'epub') {
        debugPrint('开始解析 EPUB: ${widget.book.filePath}');
        _bookContent = await _parseEpubInIsolate(widget.book.filePath);
        debugPrint('EPUB 解析完成，长度: ${_bookContent.length}');
      } else if (fileExtension == 'txt') {
        debugPrint('开始读取 TXT: ${widget.book.filePath}');
        try {
          _bookContent = await file.readAsString();
        } catch (e) {
          debugPrint('按 UTF-8 失败，尝试按字节解码: $e');
          final bytes = await file.readAsBytes();
          _bookContent = String.fromCharCodes(bytes);
        }
        debugPrint('TXT 读取完成，长度: ${_bookContent.length}');
      } else {
        debugPrint('按文本读取: ${widget.book.filePath}');
        _bookContent = await file.readAsString();
      }

      if (_bookContent.isEmpty) {
        throw Exception('文件内容为空或读取失败');
      }

      // 预处理文本
      _bookContent = _bookContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();

      if (_bookContent.length < 10) {
        throw Exception('文件内容过短，可能不是有效的书籍文件');
      }
    } catch (e) {
      debugPrint('文件读取异常: $e');
      rethrow;
    }
  }

  // 在 isolate 中解析 EPUB
  static Future<String> _parseEpubInIsolate(String filePath) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_epubParsingIsolate, {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
    });

    final result = await receivePort.first;
    if (result is String) return result;
    throw Exception(result.toString());
  }

  static void _epubParsingIsolate(Map<String, dynamic> params) async {
    final sendPort = params['sendPort'] as SendPort;
    final filePath = params['filePath'] as String;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        sendPort.send('EPUB 文件不存在: $filePath');
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        sendPort.send('EPUB 文件为空: $filePath');
        return;
      }

      final epubBook = await EpubReader.readBook(bytes);
      if (epubBook.Chapters == null || epubBook.Chapters!.isEmpty) {
        sendPort.send('EPUB 文件无有效章节: $filePath');
        return;
      }

      final buffer = StringBuffer();
      final chapters = epubBook.Chapters!;
      for (final chapter in chapters) {
        final htmlContent = chapter.HtmlContent;
        if (htmlContent != null && htmlContent.isNotEmpty) {
          final cleanText = _stripHtmlTagsStatic(htmlContent);
          if (cleanText.trim().isNotEmpty) {
            if (buffer.isNotEmpty) buffer.writeln('\n${'─' * 20}\n');
            buffer.writeln(cleanText.trim());
          }
        }
      }

      if (buffer.isEmpty) {
        sendPort.send('EPUB 解析后内容为空: $filePath');
      } else {
        sendPort.send(buffer.toString().trim());
      }
    } catch (e) {
      sendPort.send('EPUB 解析失败: $e');
    }
  }

  static String _stripHtmlTagsStatic(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  void _splitIntoPages() {
    debugPrint('开始真实分页处理...');

    if (_bookContent.isEmpty) {
      _pages = ['内容为空'];
      debugPrint('内容为空，分页终止');
      return;
    }

    try {
      _pages.clear();

      final screenSize = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      final double availableWidth = screenSize.width - (_pageMargin * 2);
      final double availableHeight = screenSize.height - padding.top - padding.bottom - 120;

      final textStyle = TextStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily == 'System' ? null : _fontFamily,
        height: _lineSpacing,
        color: _fontColor,
        letterSpacing: _letterSpacing,
      );

      final cleanContent = _bookContent
          .replaceAll(RegExp(r'\r\n|\r'), '\n')
          .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
          .trim();

      final paragraphs = cleanContent.split('\n');
      final List<String> processedParagraphs = [];
      for (final paragraph in paragraphs) {
        final trimmed = paragraph.trim();
        if (trimmed.isNotEmpty) {
          processedParagraphs.add(trimmed);
        } else {
          if (processedParagraphs.isNotEmpty && processedParagraphs.last.isNotEmpty) {
            processedParagraphs.add('');
          }
        }
      }

      final List<String> currentPageContent = [];

      for (int i = 0; i < processedParagraphs.length; i++) {
        final paragraph = processedParagraphs[i];
        final testContent = [...currentPageContent, paragraph].join('\n\n');

        final painter = TextPainter(
          text: TextSpan(text: testContent, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: availableWidth);

        final textHeight = painter.size.height;

        if (textHeight > availableHeight && currentPageContent.isNotEmpty) {
          final pageText = currentPageContent.join('\n\n').trim();
          if (pageText.isNotEmpty) _pages.add(pageText);
          currentPageContent.clear();
          currentPageContent.add(paragraph);
        } else {
          currentPageContent.add(paragraph);
        }

        // 处理超长段落：按句子智能拆分（保留标点）
        final painterForSingle = TextPainter(
          text: TextSpan(text: currentPageContent.join('\n\n'), style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: availableWidth);

        if (painterForSingle.size.height > availableHeight && currentPageContent.length == 1) {
          final longParagraph = currentPageContent[0];
          currentPageContent.clear();

          // 使用正则将文本拆分为“句子+可能的终止标点”
          final sentenceMatches = RegExp(r'[^。！？；.!?]+[。！？；.!?]?\s*')
              .allMatches(longParagraph)
              .map((m) => m.group(0)!)
              .toList();

          for (final part in sentenceMatches) {
            final test = [...currentPageContent, part].join('');
            final p = TextPainter(
              text: TextSpan(text: test, style: textStyle),
              textDirection: TextDirection.ltr,
              maxLines: null,
            )..layout(maxWidth: availableWidth);

            if (p.size.height > availableHeight && currentPageContent.isNotEmpty) {
              final pageText = currentPageContent.join('').trim();
              if (pageText.isNotEmpty) _pages.add(pageText);
              currentPageContent.clear();
            }
            currentPageContent.add(part);
          }
        }
      }

      if (currentPageContent.isNotEmpty) {
        final last = currentPageContent.join('\n\n').trim();
        if (last.isNotEmpty) _pages.add(last);
      }

      if (_pages.isEmpty) {
        _pages = [cleanContent.isNotEmpty ? cleanContent : '内容加载完成但无法显示'];
      }

      debugPrint('真实分页完成: 总共 ${_pages.length} 页，平均每页 ${(cleanContent.length / _pages.length).toStringAsFixed(0)} 字符');

      if (_currentPageIndex >= _pages.length) {
        _currentPageIndex = _pages.isNotEmpty ? _pages.length - 1 : 0;
      }

      if (_pages.length != widget.book.totalPages) {
        Future.microtask(() {
          try {
            _bookDao.updateBookTotalPages(widget.book.id!, _pages.length);
          } catch (e) {
            debugPrint('更新书籍页数失败: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('分页过程出错: $e');
      _pages = ['$_kErrorPrefix 分页失败: $e'];
    }
  }

  // --- Settings Persistence ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      _lineSpacing = prefs.getDouble('lineSpacing') ?? 1.8;
      _letterSpacing = prefs.getDouble('letterSpacing') ?? 0.2;
      _pageMargin = prefs.getDouble('pageMargin') ?? 16.0;
      _autoScroll = prefs.getBool('autoScroll') ?? false;
      _keepScreenOn = prefs.getBool('keepScreenOn') ?? false;
      _fontFamily = prefs.getString('fontFamily') ?? 'System';

      final isDarkMode = prefs.getBool('isDarkMode') ?? (Theme.of(context).brightness == Brightness.dark);
      if (isDarkMode) {
        _backgroundColor = const Color(0xFF121212);
        _fontColor = const Color(0xFFE8E8E8);
      } else {
        _backgroundColor = const Color(0xFFFFFBF0);
        _fontColor = const Color(0xFF2C2C2C);
      }
    });
  }

  Future<void> _saveSetting(Function(SharedPreferences) saver) async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    saver(prefs);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _splitIntoPages();
        setState(() {});
      }
    });
  }

  // --- UI Controls ---
  void _setImmersiveMode() {
    if (!_showControls) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _setImmersiveMode();

    if (_showControls) {
      _startHideControlsTimer();
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    } else {
      _hideControlsTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_showControls) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          );
        }
      });
    }
  }

  void _hideControls() {
    if (_showControls) {
      setState(() => _showControls = false);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!_showControls) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
            overlays: [],
          );
        }
      });
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), _hideControls);
  }

  void _onPageTurn() {
    if (!mounted) return;
    _hideControls();
    try {
      _bookDao.updateBookProgress(widget.book.id!, _currentPageIndex);
    } catch (e) {
      debugPrint('更新阅读进度失败: $e');
    }
  }

  void _handleTap(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final tapPosition = details.globalPosition;

    if (_showControls && (tapPosition.dy < 150 || tapPosition.dy > screenHeight - 200)) {
      return;
    }

    final leftBoundary = screenWidth / 3;
    final rightBoundary = screenWidth * 2 / 3;

    if (tapPosition.dx < leftBoundary) {
      _goToPreviousPage();
    } else if (tapPosition.dx > rightBoundary) {
      _goToNextPage();
    } else {
      _toggleControls();
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      HapticFeedback.lightImpact();
    }
  }

  void _goToNextPage() {
    if (_currentPageIndex < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTapUp: _handleTap,
              onHorizontalDragEnd: _handleHorizontalDragEnd,
              child: Container(
                color: Colors.transparent,
                child: _buildMainContent(),
              ),
            ),
          ),
          if (_showControls) _buildControlsOverlay(),
          _buildPageIndicators(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_pages.isEmpty) {
      return Container(
        color: _backgroundColor,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                '正在初始化阅读器...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final first = _pages.first;
    if (first.startsWith(_kLoadingPrefix) || first.startsWith(_kErrorPrefix)) {
      final isError = first.startsWith(_kErrorPrefix);
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isError) const CircularProgressIndicator() else Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  first,
                  style: TextStyle(fontSize: 16, color: isError ? Colors.red : Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                    onPressed: _initializeReading,
                    child: const Text('重试'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: _backgroundColor,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _pages.length,
        itemBuilder: (context, index) => _buildPageWidget(index),
        onPageChanged: (index) {
          if (mounted) {
            setState(() => _currentPageIndex = index);
            _onPageTurn();
          }
        },
        physics: const ClampingScrollPhysics(),
      ),
    );
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const threshold = 500.0;

    if (velocity > threshold) {
      if (_currentPageIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    } else if (velocity < -threshold) {
      if (_currentPageIndex < _pages.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Widget _buildPageNumber() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          constraints: const BoxConstraints(minWidth: 70),
          decoration: BoxDecoration(
            color: _fontColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _fontColor.withValues(alpha: 0.15), width: 0.5),
          ),
          child: Text(
            '${_currentPageIndex + 1} / ${_pages.length}',
            style: TextStyle(
              color: _fontColor.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Container();
  }

  Widget _buildPageWidget(int index) {
    if (index < 0 || index >= _pages.length) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Text(
            '页面索引错误: $index',
            style: TextStyle(fontSize: 16, color: _fontColor),
          ),
        ),
      );
    }

    final pageContent = _pages[index];
    if (pageContent.isEmpty) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Text(
            '页面内容为空',
            style: TextStyle(fontSize: 16, color: _fontColor.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    return Container(
      color: _backgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _pageMargin),
          child: Column(
            children: [
              const SizedBox(height: 30),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Text(
                    pageContent,
                    style: TextStyle(
                      fontSize: _fontSize,
                      height: _lineSpacing,
                      letterSpacing: _letterSpacing,
                      color: _fontColor,
                      fontFamily: _fontFamily == 'System' ? null : _fontFamily,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                ),
              ),
              if (!_showControls)
                Container(
                  height: 70,
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _buildPageNumber(),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Stack(
      children: [
        _buildTopBar(),
        _buildBottomToolbar(),
      ],
    );
  }

  Widget _buildTopBar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: _showControls ? Curves.easeOutExpo : Curves.easeInExpo,
      top: _showControls ? 0 : -120,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: _showControls ? 1.0 : 0.0,
        curve: _showControls ? Curves.easeOut : Curves.easeIn,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 500),
          scale: _showControls ? 1.0 : 0.94,
          curve: _showControls ? Curves.elasticOut : Curves.easeInBack,
          child: Transform.translate(
            offset: Offset(0, _showControls ? 0 : -20),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 16,
                        right: 16,
                        bottom: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(16),
                                splashColor: Colors.white.withValues(alpha: 0.1),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.arrow_back_ios_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.book.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                    shadows: [
                                      Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black26),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.book.author,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    letterSpacing: 0.2,
                                    shadows: const [
                                      Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black26),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.2),
                                  Colors.white.withValues(alpha: 0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.6),
                            ),
                            child: Text(
                              '${_currentPageIndex + 1}/${_pages.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                shadows: [
                                  Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black26),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildBottomToolbar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 700),
      curve: _showControls ? Curves.easeOutExpo : Curves.easeInExpo,
      bottom: _showControls ? 0 : -250,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: _showControls ? 1.0 : 0.0,
        curve: _showControls ? Curves.easeOut : Curves.easeIn,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 600),
          scale: _showControls ? 1.0 : 0.9,
          curve: _showControls ? Curves.elasticOut : Curves.easeInBack,
          child: Transform.translate(
            offset: Offset(0, _showControls ? 0 : 30),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(36),
                    topRight: Radius.circular(36),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 20,
                        top: 28,
                        left: 28,
                        right: 28,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.5),
                            Colors.black.withValues(alpha: 0.7),
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(36),
                          topRight: Radius.circular(36),
                        ),
                        border: Border(
                          top: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.2),
                          left: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.6),
                          right: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.6),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.6),
                                  Colors.white.withValues(alpha: 0.4),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          _buildProgressSlider(),
                          const SizedBox(height: 28),
                          _buildToolbarButtons(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildToolbarButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ModernToolbarButton(
            icon: Icons.format_list_bulleted_rounded,
            label: '目录',
            onTap: _showTableOfContents,
          ),
          Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.15)),
          _ModernToolbarButton(
            icon: Icons.tune_rounded,
            label: '设置',
            onTap: _showSettingsPanel,
            isActive: false,
          ),
          Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.15)),
          _ModernToolbarButton(
            icon: Icons.bookmark_add_rounded,
            label: '书签',
            onTap: _showBookmarks,
          ),
          Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.15)),
          _ModernToolbarButton(
            icon: _autoScroll ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
            label: _autoScroll ? '暂停' : '播放',
            onTap: _toggleAutoScroll,
            isActive: _autoScroll,
          ),
          Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.15)),
          _ModernToolbarButton(
            icon: Icons.more_horiz_rounded,
            label: '更多',
            onTap: _showMoreOptions,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSlider() {
    final progress = _pages.isNotEmpty ? (_currentPageIndex + 1) / _pages.length : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _pages.isNotEmpty ? '第 ${_currentPageIndex + 1} 页' : '第 0 页',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withValues(alpha: 0.15),
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                valueIndicatorColor: Colors.white,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Slider(
                value: _pages.isNotEmpty ? _currentPageIndex.toDouble().clamp(0, (_pages.length - 1).toDouble()) : 0.0,
                min: 0,
                max: (_pages.isNotEmpty ? _pages.length - 1 : 0).toDouble(),
                divisions: _pages.isNotEmpty ? _pages.length - 1 : null,
                label: _pages.isNotEmpty ? '${_currentPageIndex + 1}' : '0',
                onChanged: _pages.isNotEmpty ? (value) => setState(() => _currentPageIndex = value.toInt()) : null,
                onChangeEnd: _pages.isNotEmpty
                    ? (value) {
                        _pageController.animateToPage(
                          value.toInt(),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                        );
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总进度',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  _pages.isNotEmpty ? '共 ${_pages.length} 页' : '共 0 页',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Settings Panel ---
  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
                    ),
                    child: Column(
                      children: [
                        // 标题栏
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 12),
                              const Text(
                                '阅读设置',
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: IconButton(
                                  icon: Icon(Icons.refresh_rounded, color: Colors.white.withValues(alpha: 0.7), size: 20),
                                  onPressed: () {
                                    _resetSettings();
                                    setModalState(() {});
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 设置内容
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSettingSection(
                                  title: '文字设置',
                                  icon: Icons.text_fields_rounded,
                                  children: [
                                    _buildSettingSlider(
                                      label: '字号',
                                      value: _fontSize,
                                      min: 12,
                                      max: 30,
                                      divisions: 18,
                                      unit: 'pt',
                                      onChanged: (v) {
                                        setModalState(() => _fontSize = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('fontSize', v));
                                      },
                                    ),
                                    _buildSettingSlider(
                                      label: '行距',
                                      value: _lineSpacing,
                                      min: 1.0,
                                      max: 3.0,
                                      divisions: 20,
                                      unit: 'x',
                                      onChanged: (v) {
                                        setModalState(() => _lineSpacing = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('lineSpacing', v));
                                      },
                                    ),
                                    _buildSettingSlider(
                                      label: '字间距',
                                      value: _letterSpacing,
                                      min: 0.0,
                                      max: 2.0,
                                      divisions: 20,
                                      unit: 'pt',
                                      onChanged: (v) {
                                        setModalState(() => _letterSpacing = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('letterSpacing', v));
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildSettingSection(
                                  title: '页面设置',
                                  icon: Icons.article_rounded,
                                  children: [
                                    _buildSettingSlider(
                                      label: '页面边距',
                                      value: _pageMargin,
                                      min: 8,
                                      max: 32,
                                      divisions: 12,
                                      unit: 'px',
                                      onChanged: (v) {
                                        setModalState(() => _pageMargin = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('pageMargin', v));
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildSettingSection(
                                  title: '主题设置',
                                  icon: Icons.palette_rounded,
                                  children: [
                                    _buildColorThemeSelector(setModalState),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildSettingSection(
                                  title: '阅读体验',
                                  icon: Icons.auto_stories_rounded,
                                  children: [
                                    _buildSwitchSetting(
                                      label: '保持屏幕常亮',
                                      value: _keepScreenOn,
                                      onChanged: (v) {
                                        setModalState(() => _keepScreenOn = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setBool('keepScreenOn', v));
                                      },
                                    ),
                                    _buildSwitchSetting(
                                      label: '自动滚动',
                                      value: _autoScroll,
                                      onChanged: (v) {
                                        setModalState(() => _autoScroll = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setBool('autoScroll', v));
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 底部按钮
                        Container(
                          padding: EdgeInsets.only(
                            left: 24,
                            right: 24,
                            bottom: MediaQuery.of(context).padding.bottom + 20,
                            top: 16,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    '完成',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
      },
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _splitIntoPages();
          setState(() {});
        }
      });
    });
  }

  Widget _buildSettingSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
              ),
              const SizedBox(width: 12),
              const SizedBox.shrink(),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    String unit = '',
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(
                '${value.toStringAsFixed(1)}$unit',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withValues(alpha: 0.3),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            inactiveThumbColor: Colors.white.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildColorThemeSelector(StateSetter setModalState) {
    final themes = [
      {'name': '护眼绿', 'bg': const Color(0xFFCCE8CC), 'text': const Color(0xFF2D5016)},
      {'name': '羊皮纸', 'bg': const Color(0xFFFBF5E6), 'text': const Color(0xFF5C4A37)},
      {'name': '夜间黑', 'bg': const Color(0xFF1E1E1E), 'text': const Color(0xFFE0E0E0)},
      {'name': '纯净白', 'bg': Colors.white, 'text': Colors.black87},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('主题色彩', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: themes.map((theme) {
            final isSelected = _backgroundColor == theme['bg'] as Color && _fontColor == theme['text'] as Color;
            return GestureDetector(
              onTap: () {
                setModalState(() {
                  _backgroundColor = theme['bg'] as Color;
                  _fontColor = theme['text'] as Color;
                });
                setState(() {});
                _saveSetting((p) {
                  p.setInt('backgroundColor', (_backgroundColor).value);
                  p.setInt('fontColor', (_fontColor).value);
                });
              },
              child: Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: theme['bg'] as Color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Aa', style: TextStyle(color: theme['text'] as Color, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(theme['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- TOC / Bookmarks / More ---
  void _showTableOfContents() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTableOfContentsPanel(),
    );
  }

  void _showBookmarks() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBookmarksPanel(),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildMoreOptionsPanel(),
    );
  }

  void _toggleAutoScroll() {
    setState(() {
      _autoScroll = !_autoScroll;
    });
    _saveSetting((p) => p.setBool('autoScroll', _autoScroll));
    // TODO: 实现自动滚动逻辑
  }

  Widget _buildTableOfContentsPanel() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  child: const Text('目录', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      final isCurrentPage = index == _currentPageIndex;
                      return ListTile(
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCurrentPage ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: isCurrentPage ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          '第 ${index + 1} 页',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: isCurrentPage ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _getPagePreview(index),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _goToPage(index);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarksPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('书签', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 20),
              Text('暂无书签', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOptionsPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('更多选项', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.search, color: Colors.white),
                title: const Text('搜索', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 搜索功能
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('分享', style: TextStyle(color: Colors.white)),
                onTap: () {
                  // TODO: 分享功能
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getPagePreview(int pageIndex) {
    if (pageIndex >= _pages.length) return '';
    final content = _pages[pageIndex];
    final preview = content.length > 50 ? content.substring(0, 50) + '...' : content;
    return preview.replaceAll('\n', ' ');
  }

  void _goToPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < _pages.length) {
      setState(() {
        _currentPageIndex = pageIndex;
      });
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _resetSettings() {
    _fontSize = 18.0;
    _lineSpacing = 1.8;
    _letterSpacing = 0.2;
    _pageMargin = 16.0;
    _autoScroll = false;
    _keepScreenOn = false;
    _fontFamily = 'System';
    _backgroundColor = const Color(0xFFFFFBF0);
    _fontColor = const Color(0xFF2C2C2C);
    _saveSetting((p) async {
      await p.remove('fontSize');
      await p.remove('lineSpacing');
      await p.remove('letterSpacing');
      await p.remove('pageMargin');
      await p.remove('autoScroll');
      await p.remove('keepScreenOn');
      await p.remove('fontFamily');
      await p.remove('backgroundColor');
      await p.remove('fontColor');
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _pageController.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );

    if (_sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!);
      if (duration.inSeconds > 10) {
        _statsDao.insertReadingTime(DateTime.now(), duration.inSeconds);
      }
    }
    super.dispose();
  }
}

// 现代化工具栏按钮
class _ModernToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ModernToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
