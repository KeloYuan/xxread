import 'package:flutter/material.dart';
import '../models/highlight.dart';

class TextSelectionToolbar extends StatelessWidget {
  final String selectedText;
  final VoidCallback onHighlight;
  final VoidCallback onNote;
  final VoidCallback onCopy;
  final VoidCallback onCancel;
  final List<Color> highlightColors;

  const TextSelectionToolbar({
    super.key,
    required this.selectedText,
    required this.onHighlight,
    required this.onNote,
    required this.onCopy,
    required this.onCancel,
    this.highlightColors = Highlight.highlightColors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选中的文本预览
            Container(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 60),
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selectedText.length > 50 
                    ? '${selectedText.substring(0, 50)}...'
                    : selectedText,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // 操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolbarButton(
                  icon: Icons.highlight,
                  label: '高亮',
                  onTap: onHighlight,
                ),
                const SizedBox(width: 8),
                _ToolbarButton(
                  icon: Icons.note_add,
                  label: '笔记',
                  onTap: onNote,
                ),
                const SizedBox(width: 8),
                _ToolbarButton(
                  icon: Icons.copy,
                  label: '复制',
                  onTap: onCopy,
                ),
                const SizedBox(width: 8),
                _ToolbarButton(
                  icon: Icons.close,
                  label: '取消',
                  onTap: onCancel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class HighlightColorPicker extends StatelessWidget {
  final List<Color> colors;
  final Color? selectedColor;
  final Function(Color) onColorSelected;

  const HighlightColorPicker({
    super.key,
    this.colors = Highlight.highlightColors,
    this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '选择高亮颜色',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((color) => GestureDetector(
                onTap: () => onColorSelected(color),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selectedColor == color
                        ? Border.all(color: Colors.black, width: 2)
                        : Border.all(color: Colors.grey.shade300),
                  ),
                  child: selectedColor == color
                      ? const Icon(Icons.check, color: Colors.black, size: 20)
                      : null,
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}