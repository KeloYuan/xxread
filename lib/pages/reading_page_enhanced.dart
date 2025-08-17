import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/services/reading_stats_dao.dart';
import 'package:epubx/epubx.dart';

import '../models/book.dart';
import '../services/book_dao.dart';
import '../utils/color_extensions.dart';

// 章节数据模型
class Chapter {
  final String title;
  final int startPage;
  final int endPage;
  final String preview;

  Chapter({
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.preview,
  });
}

class ReadingPageEnhanced extends StatefulWidget {
  final Book book;
  const ReadingPageEnhanced({super.key, required this.book});

  @override
  State<ReadingPageEnhanced> createState() => _ReadingPageEnhancedState();
}

class _ReadingPageEnhancedState extends State<ReadingPageEnhanced> {
  late PageController _pageController;
  final _bookDao = BookDao();
  final _statsDao = ReadingStatsDao();
  
  List<String> _pages = [];
  String _bookContent = '';
  int _currentPageIndex = 0;
  bool _showControls = false; // 默认隐藏工具�?  Timer? _hideControlsTimer;
  DateTime? _sessionStartTime;
  

  // --- Reading Settings ---
  double _fontSize = 18.0;
  double _lineSpacing = 1.8;
  double _letterSpacing = 0.2;
  double _brightness = 0.5;
  double _pageMargin = 16.0;
  Color _backgroundColor = Colors.white;
  Color _fontColor = Colors.black87;
  bool _autoScroll = false;
  bool _keepScreenOn = false;
  String _fontFamily = 'System';

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.book.currentPage;
    _pageController = PageController(initialPage: _currentPageIndex);
    _sessionStartTime = DateTime.now();

    // 默认进入沉浸式阅读模�?    _setImmersiveMode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeReading();
      // 不自动开启隐藏计时器，因为默认是隐藏状�?    });
  }

  Future<void> _initializeReading() async {
    try {
      // 显示加载状�?      if (mounted) {
        setState(() => _pages = ['📚 正在加载书籍...']);
      }
      
      await _loadSettings();
      await _loadBookContent();
      
      // 确保内容加载成功后再进行分页
      if (_bookContent.isNotEmpty) {
        // 使用延迟执行确保UI稳定
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (mounted) {
          _splitIntoPages();
        }
        
        // 确保分页成功
        if (_pages.isEmpty || _pages.first.startsWith('📚') || _pages.first.startsWith('�?)) {
          throw Exception("分页失败，无法生成有效页�?);
        }
        
        if (mounted) {
          setState(() {});
        }
      } else {
        throw Exception("书籍内容为空，无法加�?);
      }
    } catch (e) {
      debugPrint('书籍初始化失�? $e');
      if (mounted) {
        setState(() => _pages = ['�?书籍加载失败: $e\n\n请检查文件是否存在或格式是否正确']);
      }
    }
  }

  Future<void> _loadBookContent() async {
    final file = File(widget.book.filePath);
    if (!await file.exists()) {
      throw Exception("文件不存�? ${widget.book.filePath}");
    }

    final fileExtension = widget.book.format.toLowerCase();
    
    try {
      if (fileExtension == 'epub') {
        // 使用 isolate 在后台解�?EPUB 文件
        debugPrint('开始解析EPUB文件: ${widget.book.filePath}');
        _bookContent = await _parseEpubInIsolate(widget.book.filePath);
        debugPrint('EPUB解析完成，内容长�? ${_bookContent.length}');
      } else if (fileExtension == 'txt') {
        // 尝试多种编码读取 TXT 文件
        debugPrint('开始读取TXT文件: ${widget.book.filePath}');
        try {
          _bookContent = await file.readAsString();
        } catch (e) {
          debugPrint('UTF-8编码读取失败，尝试其他编�? $e');
          // 如果 UTF-8 失败，尝试其他编�?          final bytes = await file.readAsBytes();
          // 尝试Latin1编码作为备选方�?          _bookContent = String.fromCharCodes(bytes);
        }
        debugPrint('TXT读取完成，内容长�? ${_bookContent.length}');
      } else {
        // 默认按文本文件处�?        debugPrint('按默认文本格式处�? ${widget.book.filePath}');
        _bookContent = await file.readAsString();
      }
      
      if (_bookContent.isEmpty) {
        throw Exception("文件内容为空或读取失�?);
      }
      
      // 清理内容中的特殊字符
      _bookContent = _bookContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
          
      if (_bookContent.length < 10) {
        throw Exception("文件内容过短，可能不是有效的书籍文件");
      }
      
    } catch (e) {
      debugPrint('文件读取异常: $e');
      throw Exception("文件读取失败: $e");
    }
  }

  // �?isolate 中解�?EPUB 文件
  static Future<String> _parseEpubInIsolate(String filePath) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_epubParsingIsolate, {
      'sendPort': receivePort.sendPort,
      'filePath': filePath,
    });
    
    final result = await receivePort.first;
    if (result is String) {
      return result;
    } else {
      throw Exception(result.toString());
    }
  }

  // isolate 中运行的 EPUB 解析函数
  static void _epubParsingIsolate(Map<String, dynamic> params) async {
    final sendPort = params['sendPort'] as SendPort;
    final filePath = params['filePath'] as String;
    
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        sendPort.send('EPUB文件不存�? $filePath');
        return;
      }
      
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        sendPort.send('EPUB文件为空: $filePath');
        return;
      }
      
      final epubBook = await EpubReader.readBook(bytes);
      
      if (epubBook.Chapters == null || epubBook.Chapters!.isEmpty) {
        sendPort.send('EPUB文件无有效章�? $filePath');
        return;
      }
      
      final buffer = StringBuffer();
      final chapters = epubBook.Chapters!;
      
      for (final chapter in chapters) {
        final htmlContent = chapter.HtmlContent;
        if (htmlContent != null && htmlContent.isNotEmpty) {
          final cleanText = _stripHtmlTagsStatic(htmlContent);
          if (cleanText.trim().isNotEmpty) {
            if (buffer.isNotEmpty) {
              buffer.writeln('\n${'─' * 20}\n');
            }
            buffer.writeln(cleanText.trim());
          }
        }
      }
      
      if (buffer.isEmpty) {
        sendPort.send('EPUB解析后内容为�? $filePath');
      } else {
        final result = buffer.toString().trim();
        sendPort.send(result);
      }
    } catch (e) {
      sendPort.send('EPUB解析失败: $e');
    }
  }

  // 静态版本的 HTML 标签清理函数（用�?isolate�?  static String _stripHtmlTagsStatic(String htmlString) {
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
    debugPrint('开始真实分页处�?..');
    
    if (_bookContent.isEmpty) {
      _pages = ['内容为空'];
      debugPrint('内容为空，分页终�?);
      return;
    }

    try {
      _pages.clear();
      
      // 获取屏幕尺寸和可用高�?      final screenSize = MediaQuery.of(context).size;
      final double availableWidth = screenSize.width - 48; // 减去左右边距
      final double availableHeight = screenSize.height - 
          MediaQuery.of(context).padding.top - 
          MediaQuery.of(context).padding.bottom - 120; // 减去状态栏和控件高�?      
      // 创建 TextPainter 来计算真实的文本排版
      final textStyle = TextStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        height: _lineSpacing,
        color: _fontColor,
        letterSpacing: _letterSpacing,
      );
      
      // 清理和预处理内容
      final cleanContent = _bookContent
          .replaceAll(RegExp(r'\r\n|\r'), '\n')
          .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n') // 去除多余空行
          .trim();
      
      debugPrint('处理内容长度: ${cleanContent.length}');
      
      // 将内容按段落分割
      final paragraphs = cleanContent.split('\n');
      final List<String> processedParagraphs = [];
      
      for (final paragraph in paragraphs) {
        final trimmedParagraph = paragraph.trim();
        if (trimmedParagraph.isNotEmpty) {
          processedParagraphs.add(trimmedParagraph);
        } else {
          // 保留空行作为段落分隔�?          if (processedParagraphs.isNotEmpty && processedParagraphs.last.isNotEmpty) {
            processedParagraphs.add('');
          }
        }
      }
      
      debugPrint('预处理段落数�? ${processedParagraphs.length}');
      
      // 使用 TextPainter 进行真实分页
      final List<String> currentPageContent = [];
      
      for (int i = 0; i < processedParagraphs.length; i++) {
        final paragraph = processedParagraphs[i];
        
        // 创建测试内容
        final testContent = [...currentPageContent, paragraph].join('\n\n');
        
        // 使用 TextPainter 计算高度
        final textPainter = TextPainter(
          text: TextSpan(text: testContent, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: availableWidth);
        
        final textHeight = textPainter.size.height;
        
        // 检查是否超出页面高�?        if (textHeight > availableHeight && currentPageContent.isNotEmpty) {
          // 当前页已满，保存页面
          final pageText = currentPageContent.join('\n\n').trim();
          if (pageText.isNotEmpty) {
            _pages.add(pageText);
          }
          
          // 开始新�?          currentPageContent.clear();
          currentPageContent.add(paragraph);
        } else {
          // 添加到当前页
          currentPageContent.add(paragraph);
        }
        
        // 处理超长段落的分�?        if (textHeight > availableHeight && currentPageContent.length == 1) {
          final longParagraph = currentPageContent[0];
          if (longParagraph.isNotEmpty) {
            // 将超长段落按句子分割
            final sentences = longParagraph.split(RegExp(r'[。！�?；\.\!\?]'));
            currentPageContent.clear();
            
            for (final sentence in sentences) {
              if (sentence.trim().isEmpty) continue;
              
              final sentenceWithPunct = sentence.trim() + (sentences.indexOf(sentence) < sentences.length - 1 ? '�? : '');
              final testSentenceContent = [...currentPageContent, sentenceWithPunct].join('');
              
              final sentencePainter = TextPainter(
                text: TextSpan(text: testSentenceContent, style: textStyle),
                textDirection: TextDirection.ltr,
                maxLines: null,
              )..layout(maxWidth: availableWidth);
              
              if (sentencePainter.size.height > availableHeight && currentPageContent.isNotEmpty) {
                final pageText = currentPageContent.join('').trim();
                if (pageText.isNotEmpty) {
                  _pages.add(pageText);
                }
                currentPageContent.clear();
              }
              
              currentPageContent.add(sentenceWithPunct);
            }
          }
        }
      }
      
      // 添加最后一�?      if (currentPageContent.isNotEmpty) {
        final lastPageText = currentPageContent.join('\n\n').trim();
        if (lastPageText.isNotEmpty) {
          _pages.add(lastPageText);
        }
      }
      
      // 确保至少有一�?      if (_pages.isEmpty) {
        _pages = [cleanContent.isNotEmpty ? cleanContent : '内容加载完成但无法显�?];
      }

      debugPrint('真实分页完成: 总共 ${_pages.length} 页，平均每页�?${(cleanContent.length / _pages.length).toInt()} 字符');
      debugPrint('原始内容长度: ${_bookContent.length} 字符');

      // 确保页面索引有效
      if (_currentPageIndex >= _pages.length) {
        _currentPageIndex = _pages.isNotEmpty ? _pages.length - 1 : 0;
        debugPrint('调整页面索引�? $_currentPageIndex');
      }
      
      // 异步更新书籍的总页�?      if (_pages.length != widget.book.totalPages) {
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
      _pages = ['�?分页失败: $e'];
    }
  }

  // --- Settings Persistence ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      _lineSpacing = prefs.getDouble('lineSpacing') ?? 1.8;
      _letterSpacing = prefs.getDouble('letterSpacing') ?? 0.2;
      _brightness = prefs.getDouble('brightness') ?? 0.5;
      _pageMargin = prefs.getDouble('pageMargin') ?? 16.0;
      _autoScroll = prefs.getBool('autoScroll') ?? false;
      _keepScreenOn = prefs.getBool('keepScreenOn') ?? false;
      _fontFamily = prefs.getString('fontFamily') ?? 'System';
      
      // 优化暗色模式设置
      final isDarkMode = prefs.getBool('isDarkMode') ?? (Theme.of(context).brightness == Brightness.dark);
      if (isDarkMode) {
        _backgroundColor = const Color(0xFF121212); // 更深的背景色
        _fontColor = const Color(0xFFE8E8E8); // 更柔和的字体�?      } else {
        _backgroundColor = const Color(0xFFFFFBF0); // 暖白色背�?        _fontColor = const Color(0xFF2C2C2C); // 柔和的黑�?      }
    });
  }

  Future<void> _saveSetting(Function(SharedPreferences) saver) async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    saver(prefs);
    
    // 延迟执行重新分页，避免在UI更新期间执行
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
      // 隐藏状态栏和导航栏，进入完全沉浸式模式
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
    } else {
      // 显示状态栏和导航栏
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    
    // 设置沉浸式模�?    _setImmersiveMode();
    
    if (_showControls) {
      _startHideControlsTimer();
      // 添加进入动画
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    } else {
      _hideControlsTimer?.cancel();
      // 延迟隐藏系统UI，给动画时间完成
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
      // 延迟隐藏系统UI，给动画时间完成
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
    
    // 忽略顶部和底部安全区域的点击（如果工具栏显示时）
    if (_showControls && 
        (tapPosition.dy < 150 || tapPosition.dy > screenHeight - 200)) {
      return;
    }
    
    // 将屏幕分为三个区域：左侧1/3、中�?/3、右�?/3
    final leftBoundary = screenWidth / 3;
    final rightBoundary = screenWidth * 2 / 3;
    
    if (tapPosition.dx < leftBoundary) {
      // 左侧区域 - 上一�?      _goToPreviousPage();
    } else if (tapPosition.dx > rightBoundary) {
      // 右侧区域 - 下一�?      _goToNextPage();
    } else {
      // 中间区域 - 切换工具�?      _toggleControls();
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      // 添加触觉反馈
      HapticFeedback.lightImpact();
    }
  }

  void _goToNextPage() {
    if (_currentPageIndex < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      // 添加触觉反馈
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          // 阅读内容区域
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
          // 工具栏覆盖层
          if (_showControls) _buildControlsOverlay(),
          // 页面指示�?          _buildPageIndicators(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    // 检查是否正在加载或出现错误
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
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 检查是否为加载或错误状�?    if (_pages.first.startsWith('📚 正在加载') || _pages.first.startsWith('�?)) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_pages.first.startsWith('📚')) 
                const CircularProgressIndicator()
              else
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red.shade300,
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _pages.first,
                  style: TextStyle(
                    fontSize: 16,
                    color: _pages.first.startsWith('�?) ? Colors.red : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_pages.first.startsWith('�?))
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                    onPressed: () {
                      // 重试加载
                      _initializeReading();
                    },
                    child: const Text('重试'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 正常显示内容 - 简化布局避免复杂嵌套
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
      // 向右滑动 - 上一�?      if (_currentPageIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    } else if (velocity < -threshold) {
      // 向左滑动 - 下一�?      if (_currentPageIndex < _pages.length - 1) {
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
            color: _fontColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _fontColor.withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: Text(
            '${_currentPageIndex + 1} / ${_pages.length}',
            style: TextStyle(
              color: _fontColor.withOpacity(0.7),
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
    // 移除中间的线，不再显示页面指示器
    return Container();
  }

  Widget _buildPageWidget(int index) {
    // 安全检�?    if (index < 0 || index >= _pages.length) {
      return Container(
        color: _backgroundColor,
        child: Center(
          child: Text(
            '页面索引错误: $index',
            style: TextStyle(
              fontSize: 16,
              color: _fontColor,
            ),
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
            style: TextStyle(
              fontSize: 16,
              color: _fontColor.withValues(alpha: 0.5),
            ),
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
              // 底部页码显示区域
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
      curve: _showControls 
          ? Curves.easeOutExpo 
          : Curves.easeInExpo,
      top: _showControls ? 0 : -120,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: _showControls ? 1.0 : 0.0,
        curve: _showControls 
            ? Curves.easeOut 
            : Curves.easeIn,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 500),
          scale: _showControls ? 1.0 : 0.94,
          curve: _showControls 
              ? Curves.elasticOut 
              : Curves.easeInBack,
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
                      Colors.black.withOpacity(0.7),
                      Colors.black.withOpacity(0.5),
                      Colors.black.withOpacity(0.2),
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
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                borderRadius: BorderRadius.circular(16),
                                splashColor: Colors.white.withOpacity(0.1),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
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
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                        color: Colors.black26,
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.book.author,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                    letterSpacing: 0.2,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                        color: Colors.black26,
                                      ),
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
                                  Colors.white.withOpacity(0.2),
                                  Colors.white.withOpacity(0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              '${_currentPageIndex + 1}/${_pages.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 2,
                                    color: Colors.black26,
                                  ),
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
      curve: _showControls 
          ? Curves.easeOutExpo 
          : Curves.easeInExpo,
      bottom: _showControls ? 0 : -250,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: _showControls ? 1.0 : 0.0,
        curve: _showControls 
            ? Curves.easeOut 
            : Curves.easeIn,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 600),
          scale: _showControls ? 1.0 : 0.9,
          curve: _showControls 
              ? Curves.elasticOut 
              : Curves.easeInBack,
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
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.6),
                      Colors.black.withOpacity(0.3),
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
                            Colors.black.withOpacity(0.5),
                            Colors.black.withOpacity(0.7),
                            Colors.black.withOpacity(0.9),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(36),
                          topRight: Radius.circular(36),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.2,
                          ),
                          left: BorderSide(
                            color: Colors.white.withOpacity(0.15),
                            width: 0.6,
                          ),
                          right: BorderSide(
                            color: Colors.white.withOpacity(0.15),
                            width: 0.6,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 拖拽指示�?                          Container(
                            width: 60,
                            height: 5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.6),
                                  Colors.white.withOpacity(0.4),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
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
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ModernToolbarButton(
            icon: Icons.format_list_bulleted_rounded,
            label: '目录',
            onTap: _showTableOfContents,
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withOpacity(0.15),
          ),
          _ModernToolbarButton(
            icon: Icons.tune_rounded,
            label: '设置',
            onTap: _showSettingsPanel,
            isActive: false,
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withOpacity(0.15),
          ),
          _ModernToolbarButton(
            icon: Icons.bookmark_add_rounded,
            label: '书签',
            onTap: _showBookmarks,
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withOpacity(0.15),
          ),
          _ModernToolbarButton(
            icon: _autoScroll ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
            label: _autoScroll ? '暂停' : '播放',
            onTap: _toggleAutoScroll,
            isActive: _autoScroll,
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withOpacity(0.15),
          ),
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
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _pages.isNotEmpty ? '�?${_currentPageIndex + 1} �? : '�?0 �?,
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
                    color: Colors.white.withOpacity(0.2),
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
                inactiveTrackColor: Colors.white.withOpacity(0.25),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withOpacity(0.15),
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                valueIndicatorColor: Colors.white,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Slider(
                value: _pages.isNotEmpty 
                    ? _currentPageIndex.toDouble().clamp(0, (_pages.length - 1).toDouble())
                    : 0.0,
                min: 0,
                max: (_pages.isNotEmpty ? _pages.length - 1 : 0).toDouble(),
                divisions: _pages.isNotEmpty ? _pages.length - 1 : null,
                label: _pages.isNotEmpty ? '${_currentPageIndex + 1}' : '0',
                onChanged: _pages.isNotEmpty 
                    ? (value) => setState(() => _currentPageIndex = value.toInt())
                    : null,
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
                  '总进�?,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  _pages.isNotEmpty ? '�?${_pages.length} �? : '�?0 �?,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
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

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // 标题栏
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                '阅读设置',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.white.withOpacity(0.7),
                                    size: 20,
                                  ),
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
                              top: BorderSide(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.white.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    '完成',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
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
      // 设置完成后重新分页
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${value.toStringAsFixed(1)}$unit',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
            inactiveTrackColor: Colors.white.withOpacity(0.3),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withOpacity(0.1),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withOpacity(0.3),
            inactiveTrackColor: Colors.white.withOpacity(0.1),
            inactiveThumbColor: Colors.white.withOpacity(0.5),
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
        const Text(
          '主题色彩',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: themes.map((theme) {
            final isSelected = _backgroundColor == theme['bg'] as Color &&
                _fontColor == theme['text'] as Color;
            
            return GestureDetector(
              onTap: () {
                setModalState(() {
                  _backgroundColor = theme['bg'] as Color;
                  _fontColor = theme['text'] as Color;
                });
                setState(() {});
                _saveSetting((p) {
                  p.setInt('backgroundColor', (_backgroundColor as Color).value);
                  p.setInt('fontColor', (_fontColor as Color).value);
                });
              },
              child: Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: theme['bg'] as Color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ] : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Aa',
                      style: TextStyle(
                        color: theme['text'] as Color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      theme['name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          child: const Text(
                            '阅读设置',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                _buildSettingSlider(
                                  label: '字号',
                                  value: _fontSize,
                                  min: 12,
                                  max: 30,
                                  onChanged: (v) {
                                    setModalState(() => _fontSize = v);
                                    setState(() {});
                                    _saveSetting((p) => p.setDouble('fontSize', v));
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSettingSlider(
                                  label: '行距',
                                  value: _lineSpacing,
                                  min: 1.0,
                                  max: 3.0,
                                  onChanged: (v) {
                                    setModalState(() => _lineSpacing = v);
                                    setState(() {});
                                    _saveSetting((p) => p.setDouble('lineSpacing', v));
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSettingSlider(
                                  label: '字间距',
                                  value: _letterSpacing,
                                  min: 0.0,
                                  max: 2.0,
                                  onChanged: (v) {
                                    setModalState(() => _letterSpacing = v);
                                    setState(() {});
                                    _saveSetting((p) => p.setDouble('letterSpacing', v));
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildSettingSlider(
                                  label: '页面边距',
                                  value: _pageMargin,
                                  min: 8,
                                  max: 32,
                                  onChanged: (v) {
                                    setModalState(() => _pageMargin = v);
                                    setState(() {});
                                    _saveSetting((p) => p.setDouble('pageMargin', v));
                                  },
                                ),
                                const SizedBox(height: 24),
                                _buildColorThemeSelector(setModalState),
                                const SizedBox(height: 24),
                                SwitchListTile(
                                  title: const Text('保持屏幕常亮', style: TextStyle(color: Colors.white)),
                                  value: _keepScreenOn,
                                  onChanged: (value) {
                                    setModalState(() => _keepScreenOn = value);
                                    setState(() {});
                                    _saveSetting((p) => p.setBool('keepScreenOn', value));
                                  },
                                  activeColor: Colors.white,
                                ),
                                SwitchListTile(
                                  title: const Text('自动滚动', style: TextStyle(color: Colors.white)),
                                  value: _autoScroll,
                                  onChanged: (value) {
                                    setModalState(() => _autoScroll = value);
                                    setState(() {});
                                    _saveSetting((p) => p.setBool('autoScroll', value));
                                  },
                                  activeColor: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(24),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('完成'),
                            ),
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildSettingSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
            inactiveTrackColor: Colors.white.withOpacity(0.3),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withOpacity(0.1),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
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
        const Text(
          '主题色彩',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: themes.map((theme) {
            final isSelected = _backgroundColor == theme['bg'] as Color &&
                _fontColor == theme['text'] as Color;
            
            return GestureDetector(
              onTap: () {
                setModalState(() {
                  _backgroundColor = theme['bg'] as Color;
                  _fontColor = theme['text'] as Color;
                });
                setState(() {});
                _saveSetting((p) {
                  p.setInt('backgroundColor', (_backgroundColor as Color).value);
                  p.setInt('fontColor', (_fontColor as Color).value);
                });
              },
              child: Container(
                width: 60,
                height: 48,
                decoration: BoxDecoration(
                  color: theme['bg'] as Color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Aa',
                      style: TextStyle(
                        color: theme['text'] as Color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      theme['name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

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
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  child: const Text(
                    '目录',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                            color: isCurrentPage 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.1),
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
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
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
            color: Colors.black.withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '书签',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              const Text(
                '暂无书签',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
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
            color: Colors.black.withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '更多选项',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
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

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _pageController.dispose();
    
    // 恢复系统UI显示
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
          color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
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
