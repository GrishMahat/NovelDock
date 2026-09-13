import 'package:flutter/material.dart';

/// Root navigator key, exposed so intent/update handlers can dialog and
/// navigate without a widget context (e.g. cold-start intents, app-start
/// update check, which both run above MaterialApp in the tree).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
