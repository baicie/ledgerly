import 'package:flutter/widgets.dart';

/// Width in logical pixels at or above which the layout is considered "wide"
/// (i.e. desktop / web browser / tablet landscape).
///
/// Centralizing this constant keeps `QuickEntry`, `CommandPalette` and any
/// future sheet-vs-dialog helpers in lock-step with the `ShellPage`
/// responsive breakpoint.
const double kWideBreakpoint = 900;

/// Returns `true` when [context] belongs to a layout wide enough to host
/// centered dialogs, navigation rails and command palettes.
///
/// Reads [MediaQuery.sizeOf] rather than the deprecated
/// [MediaQuery.of(context).size] so it remains cheap and safe under hot
/// rebuilds (e.g. when nested inside `Scaffold.body`).
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideBreakpoint;