import 'package:flutter/material.dart';

/// Display mode for library and search results.
enum DisplayMode {
  grid,
  list,
  compact;

  DisplayMode get next {
    switch (this) {
      case DisplayMode.grid:
        return DisplayMode.list;
      case DisplayMode.list:
        return DisplayMode.compact;
      case DisplayMode.compact:
        return DisplayMode.grid;
    }
  }

  IconData get icon {
    switch (this) {
      case DisplayMode.grid:
        return Icons.grid_view;
      case DisplayMode.list:
        return Icons.view_list;
      case DisplayMode.compact:
        return Icons.view_headline;
    }
  }
}
