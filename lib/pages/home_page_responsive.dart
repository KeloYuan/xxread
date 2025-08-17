import 'package:flutter/material.dart';
import 'dart:ui';

import 'home_content_enhanced.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'import_book_page.dart';
import '../utils/responsive_helper.dart';
import '../utils/color_extensions.dart';

class HomePageResponsive extends StatefulWidget {
  const HomePageResponsive({super.key});

  @override
  State<HomePageResponsive> createState() => _HomePageResponsiveState();
}

class _HomePageResponsiveState extends State<HomePageResponsive> {
  int _selectedIndex = 0;

  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: '首页',
      page: const HomeContentEnhanced(),
    ),
    NavigationItem(
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books,
      label: '书库',
      page: const LibraryPage(),
    ),
    NavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
      page: const SettingsPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final navigationType = ResponsiveHelper.getNavigationType(context);
    
    switch (navigationType) {
      case NavigationType.rail:
        return _buildNavigationRail();
      case NavigationType.bottom:
        return _buildBottomNavigation();
    }
  }

  // 桌面端：侧边导航栏
  Widget _buildNavigationRail() {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
        child: Row(
          children: [
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: ResponsiveHelper.isDesktop(context) ? 250 : 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    extended: ResponsiveHelper.isDesktop(context),
                    labelType: ResponsiveHelper.isDesktop(context) 
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    backgroundColor: Colors.transparent,
                    indicatorColor: Theme.of(context).colorScheme.primary.withOpacityValues(0.2),
                    selectedIconTheme: IconThemeData(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    unselectedIconTheme: IconThemeData(
                      color: Theme.of(context).colorScheme.onSurface.withOpacityValues(0.6),
                    ),
                    selectedLabelTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    destinations: _navigationItems.map((item) => 
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: Text(item.label),
                      ),
                    ).toList(),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _navigationItems[_selectedIndex].page,
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedIndex < 2 ? Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacityValues(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: FloatingActionButton.extended(
              onPressed: () => _navigateToImport(),
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacityValues(0.9),
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            ),
          ),
        ),
      ) : null,
    );
  }

  // 手机端：底部导航栏
  Widget _buildBottomNavigation() {
    return Scaffold(
      extendBodyBehindAppBar: true,
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
        child: IndexedStack(
          index: _selectedIndex,
          children: _navigationItems.map((item) => item.page).toList(),
        ),
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacityValues(0.8),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacityValues(0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              backgroundColor: Colors.transparent,
              indicatorColor: Theme.of(context).colorScheme.primary.withOpacityValues(0.2),
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              destinations: _navigationItems.map((item) => 
                NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
              ).toList(),
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedIndex < 2 ? Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacityValues(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: FloatingActionButton.extended(
              onPressed: () => _navigateToImport(),
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacityValues(0.9),
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            ),
          ),
        ),
      ) : null,
    );
  }

  void _navigateToImport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ImportBookPage()),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;

  NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.page,
  });
}