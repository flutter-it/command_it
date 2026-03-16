import 'package:command_it/command_it.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: deprecated_member_use_from_same_package

/// Tests for deprecated ExecuteInsteadHandler typedef and ifRestrictedExecuteInstead parameters
/// to ensure they still work during the deprecation period and maintain test coverage.
void main() {
  group('Deprecated ExecuteInsteadHandler typedef', () {
    test('ExecuteInsteadHandler typedef still works', () {
      // Test that the deprecated typedef is still functional
      ExecuteInsteadHandler<int> handler = (param) {
        expect(param, 42);
      };

      handler(42);
    });

    test('ExecuteInsteadHandler is compatible with RunInsteadHandler', () {
      // Test type compatibility
      RunInsteadHandler<String> newHandler = (param) {};
      ExecuteInsteadHandler<String> oldHandler = newHandler;

      expect(oldHandler, isNotNull);
    });
  });

  group('Deprecated ifRestrictedExecuteInstead in factory methods', () {
    late ValueNotifier<bool> restriction;

    setUp(() {
      restriction = ValueNotifier<bool>(true); // restricted
    });

    tearDown(() {
      restriction.dispose();
    });

    test('createSyncNoParamNoResult with deprecated ifRestrictedExecuteInstead',
        () {
      var insteadCalled = false;
      final cmd = Command.createSyncNoParamNoResult(
        () {},
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createSyncNoResult with deprecated ifRestrictedExecuteInstead', () {
      var insteadCalled = false;
      final cmd = Command.createSyncNoResult<int>(
        (param) {},
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createSyncNoParam with deprecated ifRestrictedExecuteInstead', () {
      var insteadCalled = false;
      final cmd = Command.createSyncNoParam<int>(
        () => 123,
        initialValue: 0,
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createSync with deprecated ifRestrictedExecuteInstead', () {
      var insteadCalled = false;
      final cmd = Command.createSync<int, String>(
        (param) => 'result',
        initialValue: 'initial',
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test(
        'createAsyncNoParamNoResult with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createAsyncNoParamNoResult(
        () async {},
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createAsyncNoResult with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createAsyncNoResult<int>(
        (param) async {},
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createAsyncNoParam with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createAsyncNoParam<int>(
        () async => 123,
        initialValue: 0,
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createAsync with deprecated ifRestrictedExecuteInstead', () async {
      var insteadCalled = false;
      final cmd = Command.createAsync<int, String>(
        (param) async => 'result',
        initialValue: 'initial',
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test(
        'createUndoableNoParamNoResult with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          stack.push('state');
        },
        undo: (stack, reason) async {
          stack.pop();
        },
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createUndoableNoResult with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createUndoableNoResult<int, String>(
        (param, stack) async {
          stack.push('state');
        },
        undo: (stack, reason) async {
          stack.pop();
        },
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createUndoableNoParam with deprecated ifRestrictedExecuteInstead',
        () async {
      var insteadCalled = false;
      final cmd = Command.createUndoableNoParam<int, String>(
        (stack) async {
          stack.push('state');
          return 123;
        },
        initialValue: 0,
        undo: (stack, reason) async {
          stack.pop();
          return 0;
        },
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          insteadCalled = true;
        },
      );

      cmd.run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });

    test('createUndoable with deprecated ifRestrictedExecuteInstead', () async {
      var insteadCalled = false;
      final cmd = Command.createUndoable<int, String, String>(
        (param, stack) async {
          stack.push('state');
          return 'result';
        },
        initialValue: 'initial',
        undo: (stack, reason) async {
          stack.pop();
          return 'initial';
        },
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          insteadCalled = true;
          expect(param, 42);
        },
      );

      cmd.run(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(insteadCalled, true);
      cmd.dispose();
    });
  });

  group('Assert that both old and new parameters cannot be provided', () {
    test('createSyncNoParamNoResult throws when both provided', () {
      expect(
        () => Command.createSyncNoParamNoResult(
          () {},
          ifRestrictedRunInstead: () {},
          ifRestrictedExecuteInstead: () {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('createSyncNoResult throws when both provided', () {
      expect(
        () => Command.createSyncNoResult<int>(
          (param) {},
          ifRestrictedRunInstead: (param) {},
          ifRestrictedExecuteInstead: (param) {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('createAsync throws when both provided', () {
      expect(
        () => Command.createAsync<int, String>(
          (param) async => 'result',
          initialValue: 'initial',
          ifRestrictedRunInstead: (param) {},
          ifRestrictedExecuteInstead: (param) {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Deprecated parameter works when new parameter is null', () {
    test('createSyncNoParamNoResult uses deprecated parameter when new is null',
        () {
      var called = false;
      final restriction = ValueNotifier<bool>(true);
      final cmd = Command.createSyncNoParamNoResult(
        () {},
        restriction: restriction,
        ifRestrictedExecuteInstead: () {
          called = true;
        },
      );

      cmd.run();
      expect(called, true);
      cmd.dispose();
      restriction.dispose();
    });

    test('createAsync uses deprecated parameter when new is null', () async {
      var called = false;
      final restriction = ValueNotifier<bool>(true);
      final cmd = Command.createAsync<int, String>(
        (param) async => 'result',
        initialValue: 'initial',
        restriction: restriction,
        ifRestrictedExecuteInstead: (param) {
          called = true;
        },
      );

      cmd.run(42);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(called, true);
      cmd.dispose();
      restriction.dispose();
    });
  });
}
