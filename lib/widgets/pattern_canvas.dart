// PatternCanvas was renamed to AidaWidget in step 8 of the canvas refactor.
// This file is a temporary re-export kept during the transition.
// All callers should be updated to import aida_widget.dart directly.
export 'aida_widget.dart' show AidaWidget;

// Alias so existing code compiles without changes until step 9 cleans up callers.
import 'aida_widget.dart';
typedef PatternCanvas = AidaWidget;
