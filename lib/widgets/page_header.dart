import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Desktop content header that replaces the per-screen [AppBar] on desktop.
///
/// The desktop shell already provides a global top bar (brand, search,
/// quick actions), so screens render a quiet content header instead of a
/// second app bar: title row + optional leading back control + actions,
/// and an optional tab strip underneath.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? search;
  final List<Widget> actions;
  final TabController? tabController;
  final List<Widget> tabs;
  final EdgeInsetsGeometry padding;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.search,
    this.actions = const [],
    this.tabController,
    this.tabs = const [],
    this.padding = const EdgeInsets.fromLTRB(
      Insets.lg,
      Insets.md,
      Insets.lg,
      Insets.sm,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasTabs = tabController != null || tabs.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: Insets.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: text.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (search != null) ...[
                search!,
                const SizedBox(width: Insets.md),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(width: Insets.sm),
                ...actions,
              ],
            ],
          ),
        ),
        if (hasTabs) ...[
          TabBar(
            controller: tabController,
            isScrollable: tabs.length > 4,
            tabAlignment: tabs.length > 4 ? TabAlignment.start : null,
            tabs: tabs,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
      ],
    );
  }
}
