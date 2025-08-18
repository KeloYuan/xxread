import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../utils/color_extensions.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _fontSize = 18.0;
  double _lineSpacing = 1.8;
  double _letterSpacing = 0.2;
  double _pageMargin = 16.0;
  bool _enableAnimations = true;
  bool _enableAutoSave = true;
  bool _keepScreenOn = false;
  String _fontFamily = 'System';
  int _autoSaveInterval = 30;

  final List<String> _fontFamilies = [
    'System',
    'Serif',
    'Sans-serif',
    'Monospace',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      _lineSpacing = prefs.getDouble('lineSpacing') ?? 1.8;
      _letterSpacing = prefs.getDouble('letterSpacing') ?? 0.2;
      _pageMargin = prefs.getDouble('pageMargin') ?? 16.0;
      _enableAnimations = prefs.getBool('enableAnimations') ?? true;
      _enableAutoSave = prefs.getBool('enableAutoSave') ?? true;
      _keepScreenOn = prefs.getBool('keepScreenOn') ?? false;
      _fontFamily = prefs.getString('fontFamily') ?? 'System';
      _autoSaveInterval = prefs.getInt('autoSaveInterval') ?? 30;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setDouble('lineSpacing', _lineSpacing);
    await prefs.setDouble('letterSpacing', _letterSpacing);
    await prefs.setDouble('pageMargin', _pageMargin);
    await prefs.setBool('enableAnimations', _enableAnimations);
    await prefs.setBool('enableAutoSave', _enableAutoSave);
    await prefs.setBool('keepScreenOn', _keepScreenOn);
    await prefs.setString('fontFamily', _fontFamily);
    await prefs.setInt('autoSaveInterval', _autoSaveInterval);
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
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
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withOpacityValues(0.1),
              Theme.of(context).colorScheme.secondaryContainer.withOpacityValues(0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              _buildSectionCard(
                title: '外观设置',
                icon: Icons.palette_outlined,
                children: [
                  _buildThemeToggle(themeNotifier, isDarkMode),
                  _buildAnimationToggle(),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionCard(
                title: '阅读设置',
                icon: Icons.auto_stories_outlined,
                children: [
                  _buildSliderSetting(
                    title: '字体大小',
                    subtitle: '${_fontSize.round()} pt',
                    value: _fontSize,
                    min: 12.0,
                    max: 32.0,
                    divisions: 20,
                    onChanged: (value) => setState(() => _fontSize = value),
                    icon: Icons.format_size,
                  ),
                  _buildSliderSetting(
                    title: '行间距',
                    subtitle: _lineSpacing.toStringAsFixed(1),
                    value: _lineSpacing,
                    min: 1.0,
                    max: 3.0,
                    divisions: 20,
                    onChanged: (value) => setState(() => _lineSpacing = value),
                    icon: Icons.format_line_spacing,
                  ),
                  _buildSliderSetting(
                    title: '字符间距',
                    subtitle: _letterSpacing.toStringAsFixed(1),
                    value: _letterSpacing,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    onChanged: (value) => setState(() => _letterSpacing = value),
                    icon: Icons.text_fields,
                  ),
                  _buildSliderSetting(
                    title: '页面边距',
                    subtitle: '${_pageMargin.round()} px',
                    value: _pageMargin,
                    min: 8.0,
                    max: 32.0,
                    divisions: 24,
                    onChanged: (value) => setState(() => _pageMargin = value),
                    icon: Icons.format_indent_increase,
                  ),
                  _buildFontFamilySelector(),
                ],
              ),
              const SizedBox(height: 20),
              _buildSectionCard(
                title: '系统设置',
                icon: Icons.settings_outlined,
                children: [
                  _buildSwitchSetting(
                    title: '保持屏幕常亮',
                    subtitle: '阅读时防止屏幕自动关闭',
                    value: _keepScreenOn,
                    onChanged: (value) => setState(() => _keepScreenOn = value),
                    icon: Icons.stay_current_portrait,
                  ),
                  _buildSwitchSetting(
                    title: '自动保存',
                    subtitle: '自动保存阅读进度',
                    value: _enableAutoSave,
                    onChanged: (value) => setState(() => _enableAutoSave = value),
                    icon: Icons.save_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildAboutCard(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacityValues(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeToggle(ThemeNotifier themeNotifier, bool isDarkMode) {
    return _buildSwitchSetting(
      title: '夜间模式',
      subtitle: isDarkMode ? '当前为夜间模式' : '当前为日间模式',
      value: isDarkMode,
      onChanged: (value) => themeNotifier.toggleTheme(value),
      icon: isDarkMode ? Icons.dark_mode : Icons.light_mode,
    );
  }

  Widget _buildAnimationToggle() {
    return _buildSwitchSetting(
      title: '动画效果',
      subtitle: '开启页面切换动画',
      value: _enableAnimations,
      onChanged: (value) => setState(() => _enableAnimations = value),
      icon: Icons.animation,
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            onChanged(!value);
            _saveSettings();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withOpacityValues(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacityValues(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: (newValue) {
                    onChanged(newValue);
                    _saveSettings();
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withOpacityValues(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Theme.of(context).colorScheme.outline.withOpacityValues(0.3),
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(context).colorScheme.primary.withOpacityValues(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: (value) => _saveSettings(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontFamilySelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withOpacityValues(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.font_download,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字体样式',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _fontFamily,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _fontFamilies.map((font) {
              final isSelected = _fontFamily == font;
              return GestureDetector(
                onTap: () {
                  setState(() => _fontFamily = font);
                  _saveSettings();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline.withOpacityValues(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline.withOpacityValues(0.3),
                    ),
                  ),
                  child: Text(
                    font,
                    style: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary.withOpacityValues(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '关于应用',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer.withOpacityValues(0.3),
                      Theme.of(context).colorScheme.secondaryContainer.withOpacityValues(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacityValues(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_stories,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '小元读书',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.0.0',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacityValues(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '一款简洁高效的电子书阅读应用，支持多种格式和个性化设置，助您畅享阅读时光。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacityValues(0.8),
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
  }
}