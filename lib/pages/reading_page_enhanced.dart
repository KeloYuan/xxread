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
import '../widgets/custom_slider_components.dart';
import '../utils/responsive_helper.dart';

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
  double _horizontalPadding = 16.0;  // 新增：左右留白距离
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

        if (mounted) {
          setState(() {});
          // 初始加载完成后，短暂显示工具栏提示用户
          _showControlsInitially();
        }
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
  
  void _showControlsInitially() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_showControls) {
        setState(() => _showControls = true);
        _startHideControlsTimer();
      }
    });
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
    debugPrint('🔄 开始标准化分页处理...');

    if (_bookContent.isEmpty) {
      _pages = ['内容为空'];
      debugPrint('内容为空，分页终止');
      return;
    }

    _pages.clear();

    // 使用标准化分页算法，避免设备差异
    _standardizedPagination(_bookContent);

    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.isNotEmpty ? _pages.length - 1 : 0;
    }

    // 更新数据库页数
    if (_pages.length != widget.book.totalPages) {
      Future.microtask(() {
        try {
          _bookDao.updateBookTotalPages(widget.book.id!, _pages.length);
        } catch (e) {
          debugPrint('更新书籍页数失败: $e');
        }
      });
    }
  }

  // 标准化分页算法 - 统一不同设备的分页结果
  void _standardizedPagination(String content) {
    debugPrint('📱 开始标准化分页...');
    
    // 获取设备信息
    final screenSize = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    
    debugPrint('📱 设备信息: 屏幕${screenSize.width}x${screenSize.height}, DPR$devicePixelRatio');
    
    // 标准化字符数计算 - 基于逻辑像素而非物理像素
    final logicalWidth = screenSize.width;
    final logicalHeight = screenSize.height;
    
    // 基于逻辑尺寸计算每页字符数
    int charsPerPage;
    if (logicalWidth > 600) {
      // 平板或横屏
      charsPerPage = 800;
    } else if (logicalHeight > 700) {
      // 长屏手机
      charsPerPage = 600;
    } else {
      // 标准手机
      charsPerPage = 500;
    }
    
    // 根据字体大小调整
    final fontScale = _fontSize / 18.0; // 18为基准字体大小
    charsPerPage = (charsPerPage / fontScale).round();
    
    // 确保在合理范围内
    charsPerPage = charsPerPage.clamp(400, 1000);
    
    debugPrint('📊 标准化分页: 每页$charsPerPage字符 (逻辑尺寸${logicalWidth}x$logicalHeight)');
    
    // 执行分页
    for (int i = 0; i < content.length; i += charsPerPage) {
      final end = (i + charsPerPage < content.length) ? i + charsPerPage : content.length;
      _pages.add(content.substring(i, end));
    }
    
    debugPrint('✅ 标准化分页完成: 总共 ${_pages.length} 页');
    
    // 验证分页结果
    final avgCharsPerPage = content.length / _pages.length;
    debugPrint('📈 平均每页: ${avgCharsPerPage.toStringAsFixed(0)} 字符');
    
    if (_pages.length < 10 && content.length > 5000) {
      debugPrint('⚠️ 页数可能过少，使用保险分页');
      _ultimateFallbackPagination(content);
    }
  }


  // 最后保险分页方法 - 使用固定字符数分页
  void _ultimateFallbackPagination(String content) {
    _pages.clear();
    
    const int fixedCharsPerPage = 800; // 降低字符数，增加页数
    
    debugPrint('🆘 执行最后保险分页，固定每页$fixedCharsPerPage字符');
    
    for (int i = 0; i < content.length; i += fixedCharsPerPage) {
      final end = (i + fixedCharsPerPage < content.length) ? i + fixedCharsPerPage : content.length;
      _pages.add(content.substring(i, end));
    }
    
    debugPrint('🆘 最后保险分页完成: 总共 ${_pages.length} 页');
    
    // 最后的合理性检查
    if (_pages.length > 10000) {
      debugPrint('❌ 分页仍然异常，内容可能有问题');
      _pages = ['$_kErrorPrefix 分页完全失败\n\n内容长度: ${content.length}\n页数: ${_pages.length}\n\n请检查文件格式'];
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
      _horizontalPadding = prefs.getDouble('horizontalPadding') ?? 16.0;
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
    
    // 不立即隐藏控件，让用户有时间看到页面变化
    if (_showControls) {
      _startHideControlsTimer(); // 重新开始计时而不是立即隐藏
    }
    
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

    // 检查是否应该显示双页布局
    final shouldShowDoublePage = ResponsiveHelper.shouldShowDoublePage(context);
    
    if (shouldShowDoublePage) {
      return _buildDoublePageView();
    } else {
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
    final shouldShowDoublePage = ResponsiveHelper.shouldShowDoublePage(context);
    final displayText = shouldShowDoublePage && _currentPageIndex + 1 < _pages.length
        ? '${_currentPageIndex + 1}-${_currentPageIndex + 2} / ${_pages.length}'
        : '${_currentPageIndex + 1} / ${_pages.length}';
    
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
            displayText,
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
    if (_showControls) return Container();
    
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: _buildPageNumber(),
    );
  }

  // 双页布局视图 - 简化版，只有中间分隔线
  Widget _buildDoublePageView() {
    return Container(
      color: _backgroundColor,
      child: PageView.builder(
        controller: _pageController,
        itemCount: (_pages.length / 2).ceil(),
        itemBuilder: (context, index) {
          final leftPageIndex = index * 2;
          final rightPageIndex = leftPageIndex + 1;
          
          return Row(
            children: [
              // 左页
              Expanded(
                child: leftPageIndex < _pages.length 
                  ? _buildPageWidget(leftPageIndex, isDoublePage: true)
                  : Container(color: _backgroundColor),
              ),
              // 中间分隔线
              Container(
                width: 1,
                height: double.infinity,
                color: _fontColor.withValues(alpha: 0.2),
              ),
              // 右页
              Expanded(
                child: rightPageIndex < _pages.length 
                  ? _buildPageWidget(rightPageIndex, isDoublePage: true)
                  : Container(color: _backgroundColor),
              ),
            ],
          );
        },
        onPageChanged: (index) {
          if (mounted) {
            final newPageIndex = index * 2;
            setState(() => _currentPageIndex = newPageIndex);
            _onPageTurn();
          }
        },
        physics: const ClampingScrollPhysics(),
      ),
    );
  }

  Widget _buildPageWidget(int index, {bool isDoublePage = false}) {
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

    // 根据是否为双页布局调整边距和间距
    final horizontalPadding = isDoublePage 
        ? _horizontalPadding * 0.5  // 双页时减少内边距
        : _horizontalPadding;
    final topPadding = isDoublePage ? 10.0 : 20.0;
    final bottomPadding = isDoublePage ? 60.0 : 80.0;
    
    return Container(
      color: _backgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              SizedBox(height: topPadding),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(bottom: bottomPadding),
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
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double topBarHeight = statusBarHeight + 60;
    
    // 根据背景颜色动态调整工具栏颜色
    final isLightBackground = _backgroundColor.computeLuminance() > 0.5;
    final toolbarBgColor = isLightBackground 
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.black.withValues(alpha: 0.9);
    final textColor = isLightBackground ? Colors.black87 : Colors.white;
    final iconBgColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.grey.withValues(alpha: 0.3);
    final borderColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.grey.withValues(alpha: 0.3);
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutExpo,
      top: _showControls ? 0 : -topBarHeight,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _showControls ? 1.0 : 0.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 400),
          scale: _showControls ? 1.0 : 0.9,
          curve: Curves.easeOutBack,
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Container(
              padding: EdgeInsets.only(
                top: statusBarHeight + 8,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                color: toolbarBgColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: textColor,
                        size: 20,
                      ),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.book.title,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.book.author,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.4), 
                        width: 1
                      ),
                    ),
                    child: Text(
                      '${_currentPageIndex + 1}/${_pages.length}',
                      style: TextStyle(
                        color: isLightBackground ? Colors.blue[700] : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottomToolbarHeight = 140 + bottomPadding;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // 根据背景颜色动态调整工具栏颜色
    final isLightBackground = _backgroundColor.computeLuminance() > 0.5;
    final toolbarBgColor = isLightBackground 
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.black.withValues(alpha: 0.9);
    final handleColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.4)
        : Colors.grey.withValues(alpha: 0.5);
    final borderColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.grey.withValues(alpha: 0.3);
    
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: _showControls ? Curves.easeOutBack : Curves.easeInBack,
      // 从下方弹出动画：隐藏时在屏幕底部外，显示时滑动到顶部
      bottom: _showControls ? screenHeight - bottomToolbarHeight - 100 : -bottomToolbarHeight,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: _showControls ? 1.0 : 0.0,
        curve: Curves.easeInOut,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 500),
          scale: _showControls ? 1.0 : 0.8,
          curve: Curves.elasticOut,
          child: Transform.translate(
            offset: Offset(0, _showControls ? 0 : 100),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: bottomPadding + 16,
                  top: 20,
                  left: 20,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  color: toolbarBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildProgressSlider(),
                    const SizedBox(height: 16),
                    _buildToolbarButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarButtons() {
    // 根据背景颜色动态调整按钮样式
    final isLightBackground = _backgroundColor.computeLuminance() > 0.5;
    final buttonBgColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.1)
        : Colors.grey.withValues(alpha: 0.2);
    final borderColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.grey.withValues(alpha: 0.3);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: buttonBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SimpleToolbarButton(
            icon: Icons.format_list_bulleted_rounded,
            label: '目录',
            onTap: _showTableOfContents,
            isLightBackground: isLightBackground,
          ),
          _buildDivider(),
          _SimpleToolbarButton(
            icon: Icons.tune_rounded,
            label: '设置',
            onTap: _showSettingsPanel,
            isLightBackground: isLightBackground,
          ),
          _buildDivider(),
          _SimpleToolbarButton(
            icon: Icons.bookmark_add_rounded,
            label: '书签',
            onTap: _showBookmarks,
            isLightBackground: isLightBackground,
          ),
          _buildDivider(),
          _SimpleToolbarButton(
            icon: Icons.more_horiz_rounded,
            label: '更多',
            onTap: _showMoreOptions,
            isLightBackground: isLightBackground,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    final isLightBackground = _backgroundColor.computeLuminance() > 0.5;
    final dividerColor = isLightBackground 
        ? Colors.grey.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.3);
    return Container(
      width: 1, 
      height: 20, 
      color: dividerColor,
    );
  }

  Widget _buildProgressSlider() {
    final progress = _pages.isNotEmpty ? (_currentPageIndex + 1) / _pages.length : 0.0;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // 主题颜色
    final containerBgColor = isDarkMode 
        ? Colors.grey[850]!.withValues(alpha: 0.8)
        : Colors.grey[100]!.withValues(alpha: 0.9);
    final containerBorderColor = isDarkMode 
        ? Colors.grey[700]!.withValues(alpha: 0.6)
        : Colors.grey[300]!.withValues(alpha: 0.8);
    final textColor = isDarkMode ? Colors.white : Colors.grey[800]!;
    final progressBadgeColor = isDarkMode 
        ? Colors.blue[600]!.withValues(alpha: 0.8)
        : Colors.blue[500]!.withValues(alpha: 0.9);
    
    // 滑块颜色
    final activeTrackColor = isDarkMode ? Colors.blue[400]! : Colors.blue[500]!;
    final inactiveTrackColor = isDarkMode 
        ? Colors.grey[600]!.withValues(alpha: 0.5)
        : Colors.grey[300]!.withValues(alpha: 0.8);
    final thumbColor = isDarkMode ? Colors.blue[300]! : Colors.blue[600]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: containerBgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: containerBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _pages.isNotEmpty ? '第 ${_currentPageIndex + 1} 页' : '第 0 页',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: progressBadgeColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: progressBadgeColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8, // 增加轨道高度
                thumbShape: CustomSliderThumbShape(
                  enabledThumbRadius: 14,
                  thumbColor: thumbColor,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: activeTrackColor,
                inactiveTrackColor: inactiveTrackColor,
                overlayColor: activeTrackColor.withValues(alpha: 0.2),
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                valueIndicatorColor: thumbColor,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                trackShape: CustomSliderTrackShape(),
              ),
              child: Slider(
                value: _pages.isNotEmpty ? _currentPageIndex.toDouble().clamp(0, (_pages.length - 1).toDouble()) : 0.0,
                min: 0,
                max: (_pages.isNotEmpty ? _pages.length - 1 : 0).toDouble(),
                divisions: _pages.isNotEmpty ? _pages.length - 1 : null,
                label: _pages.isNotEmpty ? '第 ${_currentPageIndex + 1} 页' : '第 0 页',
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '总进度',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  _pages.isNotEmpty ? '共 ${_pages.length} 页' : '共 0 页',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.9),
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
      barrierColor: Colors.black.withValues(alpha: 0.6),
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            final panelBgColor = isDarkMode 
                ? Colors.grey[900]!.withValues(alpha: 0.98)
                : Colors.grey[50]!.withValues(alpha: 0.98);
            final panelBorderColor = isDarkMode 
                ? Colors.grey[700]!.withValues(alpha: 0.6)
                : Colors.grey[300]!.withValues(alpha: 0.8);
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: MediaQuery.of(context).size.height * 0.85,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      color: panelBgColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      border: Border.all(color: panelBorderColor, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 拖拽指示器
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isDarkMode 
                                    ? Colors.grey[600] 
                                    : Colors.grey[400],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        // 标题栏
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDarkMode 
                                    ? Colors.grey[700]!.withValues(alpha: 0.5)
                                    : Colors.grey[300]!.withValues(alpha: 0.8), 
                                width: 1
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDarkMode 
                                      ? Colors.blue[600]!.withValues(alpha: 0.2)
                                      : Colors.blue[100]!.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.tune_rounded, 
                                  color: isDarkMode ? Colors.blue[300] : Colors.blue[600], 
                                  size: 24
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '阅读设置',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.white : Colors.grey[800], 
                                  fontSize: 22, 
                                  fontWeight: FontWeight.w700, 
                                  letterSpacing: 0.5
                                ),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDarkMode 
                                      ? Colors.grey[700]!.withValues(alpha: 0.5)
                                      : Colors.grey[200]!.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.refresh_rounded, 
                                    color: isDarkMode 
                                        ? Colors.grey[300] 
                                        : Colors.grey[600], 
                                    size: 20
                                  ),
                                  onPressed: () {
                                    _resetSettings();
                                    setModalState(() {});
                                    setState(() {});
                                  },
                                  tooltip: '重置设置',
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 设置内容
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSettingSection(
                                  title: '文字设置',
                                  icon: Icons.text_fields_rounded,
                                  isDarkMode: isDarkMode,
                                  children: [
                                    _buildEnhancedSettingSlider(
                                      label: '字号',
                                      value: _fontSize,
                                      min: 12,
                                      max: 30,
                                      divisions: 18,
                                      unit: 'pt',
                                      icon: Icons.format_size,
                                      isDarkMode: isDarkMode,
                                      onChanged: (v) {
                                        setModalState(() => _fontSize = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('fontSize', v));
                                      },
                                    ),
                                    _buildEnhancedSettingSlider(
                                      label: '行距',
                                      value: _lineSpacing,
                                      min: 1.0,
                                      max: 3.0,
                                      divisions: 20,
                                      unit: 'x',
                                      icon: Icons.format_line_spacing,
                                      isDarkMode: isDarkMode,
                                      onChanged: (v) {
                                        setModalState(() => _lineSpacing = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('lineSpacing', v));
                                      },
                                    ),
                                    _buildEnhancedSettingSlider(
                                      label: '字间距',
                                      value: _letterSpacing,
                                      min: 0.0,
                                      max: 2.0,
                                      divisions: 20,
                                      unit: 'pt',
                                      icon: Icons.text_fields,
                                      isDarkMode: isDarkMode,
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
                                  isDarkMode: isDarkMode,
                                  children: [
                                    _buildEnhancedSettingSlider(
                                      label: '页面边距',
                                      value: _pageMargin,
                                      min: 8,
                                      max: 32,
                                      divisions: 12,
                                      unit: 'px',
                                      icon: Icons.crop_free,
                                      isDarkMode: isDarkMode,
                                      onChanged: (v) {
                                        setModalState(() => _pageMargin = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('pageMargin', v));
                                      },
                                    ),
                                    _buildEnhancedSettingSlider(
                                      label: '左右留白',
                                      value: _horizontalPadding,
                                      min: 8,
                                      max: 48,
                                      divisions: 20,
                                      unit: 'px',
                                      icon: Icons.horizontal_distribute,
                                      isDarkMode: isDarkMode,
                                      onChanged: (v) {
                                        setModalState(() => _horizontalPadding = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setDouble('horizontalPadding', v));
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildSettingSection(
                                  title: '主题设置',
                                  icon: Icons.palette_rounded,
                                  isDarkMode: isDarkMode,
                                  children: [
                                    _buildEnhancedColorThemeSelector(setModalState, isDarkMode),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildSettingSection(
                                  title: '阅读体验',
                                  icon: Icons.auto_stories_rounded,
                                  isDarkMode: isDarkMode,
                                  children: [
                                    _buildSwitchSetting(
                                      label: '保持屏幕常亮',
                                      value: _keepScreenOn,
                                      icon: Icons.screen_lock_portrait,
                                      isDarkMode: isDarkMode,
                                      onChanged: (v) {
                                        setModalState(() => _keepScreenOn = v);
                                        setState(() {});
                                        _saveSetting((p) => p.setBool('keepScreenOn', v));
                                      },
                                    ),
                                    _buildSwitchSetting(
                                      label: '自动滚动',
                                      value: _autoScroll,
                                      icon: Icons.auto_mode,
                                      isDarkMode: isDarkMode,
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
                                color: isDarkMode 
                                    ? Colors.grey[700]!.withValues(alpha: 0.5)
                                    : Colors.grey[300]!.withValues(alpha: 0.8), 
                                width: 1
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDarkMode 
                                        ? Colors.blue[600]
                                        : Colors.blue[500],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        '完成设置',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
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
    bool isDarkMode = true,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.grey[800]!;
    final sectionBgColor = isDarkMode 
        ? Colors.grey[850]!.withValues(alpha: 0.6)
        : Colors.grey[50]!.withValues(alpha: 0.9);
    final sectionBorderColor = isDarkMode 
        ? Colors.grey[700]!.withValues(alpha: 0.5)
        : Colors.grey[300]!.withValues(alpha: 0.8);
    final iconBgColor = isDarkMode 
        ? Colors.blue[600]!.withValues(alpha: 0.3)
        : Colors.blue[100]!.withValues(alpha: 0.8);
    final iconColor = isDarkMode ? Colors.blue[300] : Colors.blue[600];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sectionBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sectionBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEnhancedSettingSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    String unit = '',
    required IconData icon,
    required bool isDarkMode,
    required ValueChanged<double> onChanged,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.grey[800]!;
    final activeColor = isDarkMode ? Colors.blue[400]! : Colors.blue[500]!;
    final inactiveColor = isDarkMode 
        ? Colors.grey[600]!.withValues(alpha: 0.5)
        : Colors.grey[300]!.withValues(alpha: 0.8);
    final badgeColor = isDarkMode 
        ? Colors.blue[600]!.withValues(alpha: 0.3)
        : Colors.blue[100]!.withValues(alpha: 0.8);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? Colors.grey[800]!.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode 
              ? Colors.grey[700]!.withValues(alpha: 0.5)
              : Colors.grey[300]!.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isDarkMode ? Colors.blue[300] : Colors.blue[600],
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)}$unit',
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 13,
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
              thumbShape: CustomSliderThumbShape(
                enabledThumbRadius: 12,
                thumbColor: activeColor,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              activeTrackColor: activeColor,
              inactiveTrackColor: inactiveColor,
              overlayColor: activeColor.withValues(alpha: 0.1),
              trackShape: CustomSliderTrackShape(),
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
      ),
    );
  }

  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    bool isDarkMode = true,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.grey[800]!;
    final activeColor = isDarkMode ? Colors.blue[400]! : Colors.blue[500]!;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? Colors.grey[800]!.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode 
              ? Colors.grey[700]!.withValues(alpha: 0.5)
              : Colors.grey[300]!.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: activeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: activeColor,
            inactiveTrackColor: isDarkMode 
                ? Colors.grey[600]!.withValues(alpha: 0.5)
                : Colors.grey[300]!.withValues(alpha: 0.8),
            inactiveThumbColor: isDarkMode 
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedColorThemeSelector(StateSetter setModalState, bool isDarkMode) {
    final themes = [
      {'name': '护眼绿', 'bg': const Color(0xFFCCE8CC), 'text': const Color(0xFF2D5016), 'icon': Icons.eco},
      {'name': '羊皮纸', 'bg': const Color(0xFFFBF5E6), 'text': const Color(0xFF5C4A37), 'icon': Icons.article},
      {'name': '夜间黑', 'bg': const Color(0xFF1E1E1E), 'text': const Color(0xFFE0E0E0), 'icon': Icons.dark_mode},
      {'name': '纯净白', 'bg': Colors.white, 'text': Colors.black87, 'icon': Icons.light_mode},
    ];

    final textColor = isDarkMode ? Colors.white : Colors.grey[800]!;
    final selectedBorderColor = isDarkMode ? Colors.blue[400]! : Colors.blue[500]!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.palette_rounded,
              color: isDarkMode ? Colors.blue[300] : Colors.blue[600],
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '主题色彩',
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: themes.length,
          itemBuilder: (context, index) {
            final theme = themes[index];
            final isSelected = _backgroundColor == theme['bg'] as Color && _fontColor == theme['text'] as Color;
            
            return GestureDetector(
              onTap: () {
                setModalState(() {
                  _backgroundColor = theme['bg'] as Color;
                  _fontColor = theme['text'] as Color;
                });
                setState(() {});
                _saveSetting((p) {
                  p.setInt('backgroundColor', (_backgroundColor).toARGB32());
                  p.setInt('fontColor', (_fontColor).toARGB32());
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: theme['bg'] as Color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected 
                        ? selectedBorderColor
                        : (isDarkMode 
                            ? Colors.grey[600]!.withValues(alpha: 0.5)
                            : Colors.grey[300]!.withValues(alpha: 0.8)),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: selectedBorderColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (theme['text'] as Color).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          theme['icon'] as IconData,
                          color: theme['text'] as Color,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Aa',
                              style: TextStyle(
                                color: theme['text'] as Color,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              theme['name'] as String,
                              style: TextStyle(
                                color: (theme['text'] as Color).withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: selectedBorderColor,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
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

  Timer? _autoScrollTimer;
  
  void _toggleAutoScroll() {
    setState(() {
      _autoScroll = !_autoScroll;
    });
    _saveSetting((p) => p.setBool('autoScroll', _autoScroll));
    
    if (_autoScroll) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }
  
  void _startAutoScroll() {
    _stopAutoScroll(); // 确保之前的定时器被清除
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPageIndex < _pages.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // 到达最后一页，停止自动滚动
        _toggleAutoScroll();
      }
    });
  }
  
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
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
                  _showSearchDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('分享', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _shareCurrentPage();
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
    final preview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
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
    _horizontalPadding = 16.0;
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
      await p.remove('horizontalPadding');
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
    _autoScrollTimer?.cancel();
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
  
  void _showSearchDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) {
        String searchQuery = '';
        return AlertDialog(
          backgroundColor: Colors.black.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('搜索内容', style: TextStyle(color: Colors.white)),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '输入要搜索的内容...',
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
            onChanged: (value) => searchQuery = value,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (searchQuery.isNotEmpty) {
                  _searchInBook(searchQuery);
                }
              },
              child: const Text('搜索', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
  
  void _searchInBook(String query) {
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].toLowerCase().contains(query.toLowerCase())) {
        _pageController.animateToPage(
          i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('在第 ${i + 1} 页找到："$query"'),
            backgroundColor: Colors.black.withValues(alpha: 0.8),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('未找到："$query"'),
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _shareCurrentPage() {
    if (_pages.isNotEmpty && _currentPageIndex < _pages.length) {
      final currentPageContent = _pages[_currentPageIndex];
      final bookInfo = '《${widget.book.title}》- ${widget.book.author}';
      final shareText = '$bookInfo\n\n第${_currentPageIndex + 1}页:\n\n$currentPageContent';
      
      // 复制到剪贴板
      Clipboard.setData(ClipboardData(text: shareText));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前页面内容已复制到剪贴板'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// 简单工具栏按钮
class _SimpleToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLightBackground;

  const _SimpleToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLightBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isLightBackground ? Colors.black87 : Colors.white;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: iconColor, 
              size: 18
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: iconColor,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
