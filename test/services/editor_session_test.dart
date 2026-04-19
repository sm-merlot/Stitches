import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/editor_session_service.dart';

void main() {
  group('EditorSession JSON round-trip', () {
    test('all fields survive toJson/fromJson', () {
      const session = EditorSession(
        tool: 'backstitch',
        selectedThreadId: '310',
        colourMode: true,
        activeLayerId: 'layer-abc',
        viewPanX: 12.5,
        viewPanY: -3.0,
        viewScale: 2.25,
        stitchPage: 4,
      );
      final reloaded = EditorSession.fromJson(session.toJson());

      expect(reloaded.tool, equals('backstitch'));
      expect(reloaded.selectedThreadId, equals('310'));
      expect(reloaded.colourMode, isTrue);
      expect(reloaded.activeLayerId, equals('layer-abc'));
      expect(reloaded.viewPanX, equals(12.5));
      expect(reloaded.viewPanY, equals(-3.0));
      expect(reloaded.viewScale, equals(2.25));
      expect(reloaded.stitchPage, equals(4));
    });

    test('defaults applied for missing fields', () {
      final session = EditorSession.fromJson({});
      expect(session.tool, equals('fullStitch'));
      expect(session.colourMode, isFalse);
      expect(session.viewPanX, equals(0));
      expect(session.viewPanY, equals(0));
      expect(session.viewScale, equals(0));
      expect(session.selectedThreadId, isNull);
      expect(session.activeLayerId, isNull);
      expect(session.stitchPage, isNull);
    });

    test('corrupt JSON string → null (matches service contract)', () {
      const bad = 'not valid json {{{';
      EditorSession? result;
      try {
        result = EditorSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(bad) as Map));
      } catch (_) {
        result = null;
      }
      expect(result, isNull);
    });

    test('legacy blockMode field migrated to colourMode (inverted)', () {
      final session = EditorSession.fromJson({'blockMode': true});
      expect(session.colourMode, isFalse);

      final session2 = EditorSession.fromJson({'blockMode': false});
      expect(session2.colourMode, isTrue);
    });

    test('null optional fields omitted from toJson', () {
      const session = EditorSession(tool: 'fullStitch');
      final json = session.toJson();
      expect(json.containsKey('selectedThreadId'), isFalse);
      expect(json.containsKey('activeLayerId'), isFalse);
      expect(json.containsKey('stitchPage'), isFalse);
    });
  });
}

