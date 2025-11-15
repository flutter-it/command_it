// ignore_for_file: avoid_print

import 'package:command_it/command_it.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collector utility from flutter_command_test.dart
class Collector<T> {
  List<T>? values;

  void call(T value) {
    values ??= <T>[];
    values!.add(value);
  }

  void clear() {
    values?.clear();
  }

  void reset() {
    clear();
    values = null;
  }
}

void main() {
  setUp(() {
    Command.globalExceptionHandler = null;
    Command.reportErrorHandlerExceptionsToGlobalHandler = true;
  });

  tearDown(() {
    Command.globalExceptionHandler = null;
  });

  group('UndoableCommand Factory Functions', () {
    test('createUndoableNoParamNoResult', () async {
      int executionCount = 0;
      int undoCount = 0;
      final undoStack = <String>[];

      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          executionCount++;
          stack.push('execution-$executionCount');
          undoStack.add('execution-$executionCount');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        undo: (stack, reason) async {
          undoCount++;
          final state = stack.pop();
          undoStack.removeLast();
          expect(state, 'execution-$executionCount');
        },
      );

      // Execute twice
      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executionCount, 1);
      expect(undoStack.length, 1);

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executionCount, 2);
      expect(undoStack.length, 2);

      // Undo
      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(undoCount, 1);
      expect(undoStack.length, 1);

      command.dispose();
    });

    test('createUndoableNoResult', () async {
      int executionCount = 0;
      final capturedParams = <String>[];

      final command = Command.createUndoableNoResult<String, int>(
        (param, stack) async {
          executionCount++;
          capturedParams.add(param);
          stack.push(executionCount);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        undo: (stack, reason) async {
          final count = stack.pop();
          executionCount--;
          capturedParams.removeLast();
          expect(count, executionCount + 1);
        },
      );

      command.run('test1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(capturedParams, ['test1']);

      command.run('test2');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(capturedParams, ['test1', 'test2']);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(capturedParams, ['test1']);

      command.dispose();
    });

    test('createUndoableNoParam', () async {
      int value = 0;

      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          value += 10;
          stack.push(value);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return value;
        },
        undo: (stack, reason) async {
          final oldValue = stack.pop();
          value = oldValue - 10;
          return value;
        },
        initialValue: 0,
      );

      final collector = Collector<int>();
      command.listen((val, _) => collector(val));

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 10);
      expect(value, 10);

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 20);
      expect(value, 20);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 10);
      expect(value, 10);

      command.dispose();
    });

    test('createUndoable', () async {
      int counter = 0;
      final previousValues = <int>[];

      final command = Command.createUndoable<String, int, int>(
        (param, stack) async {
          counter += int.parse(param);
          previousValues.add(counter);
          stack.push(counter);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return counter;
        },
        undo: (stack, reason) async {
          stack.pop();
          previousValues.removeLast();
          counter = previousValues.isEmpty ? 0 : previousValues.last;
          return counter;
        },
        initialValue: 0,
      );

      command.run('5');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 5);

      command.run('10');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 15);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(command.value, 5);

      command.dispose();
    });
  });

  group('UndoStack', () {
    test('isEmpty and isNotEmpty', () {
      final stack = UndoStack<String>();
      expect(stack.isEmpty, true);
      expect(stack.isNotEmpty, false);

      stack.push('item1');
      expect(stack.isEmpty, false);
      expect(stack.isNotEmpty, true);

      stack.push('item2');
      expect(stack.isEmpty, false);
      expect(stack.isNotEmpty, true);

      stack.pop();
      stack.pop();
      expect(stack.isEmpty, true);
      expect(stack.isNotEmpty, false);
    });

    test('toString', () {
      final stack = UndoStack<int>();
      expect(stack.toString(), '[]');

      stack.push(1);
      stack.push(2);
      expect(stack.toString(), '[1, 2]');
    });
  });

  group('UndoException', () {
    test('toString', () {
      final exception = UndoException('test error');
      expect(exception.toString(), 'test error');
    });

    test('wraps original error', () {
      final originalError = Exception('original');
      final undoException = UndoException(originalError);
      expect(undoException.error, originalError);
      expect(undoException.toString(), "Exception: original");
    });
  });

  group('Manual undo()', () {
    test('manual undo without error', () async {
      final states = <String>[];
      bool undoCalled = false;

      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          states.add('executed');
          stack.push('state');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        undo: (stack, reason) async {
          undoCalled = true;
          states.add('undone');
          stack.pop();
        },
      );

      // Listen to results to track undo completion (undo emits CommandResult with error field set)
      final resultCollector = Collector<CommandResult<void, void>>();
      command.results.listen((result, _) => resultCollector(result));

      // Also listen to errors in case undo triggers error path
      final errorCollector = Collector<CommandError<void>>();
      command.errors.listen((err, _) {
        if (err != null) errorCollector(err);
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(states, ['executed']);
      expect(command.isRunning.value, false,
          reason: 'Command should not be executing');

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(undoCalled, true, reason: 'Undo function should have been called');
      expect(states, ['executed', 'undone']);

      command.dispose();
    });

    test('undo runs after execution completes', () async {
      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          stack.push('state');
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
        undo: (stack, reason) async {
          stack.pop();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
      );

      final isExecutingCollector = Collector<bool>();
      command.isRunning.listen((val, _) => isExecutingCollector(val));

      // Start execution
      command.run();
      // Wait for execution to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now call undo - should run since execution is finished
      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // isExecuting should be: true (execute start), false (execute end),
      // true (undo start), false (undo end)
      expect(isExecutingCollector.values, [true, false, true, false]);

      command.dispose();
    });
  });

  group('undoOnExecutionFailure', () {
    test('undoOnExecutionFailure = true (default)', () async {
      int undoCalls = 0;
      Object? undoReason;

      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          stack.push('state');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw Exception('execution failed');
        },
        undo: (stack, reason) async {
          undoCalls++;
          undoReason = reason;
          stack.pop();
        },
        undoOnExecutionFailure: true,
      );

      final errorCollector = Collector<CommandError<void>>();
      command.errors.listen((err, _) => errorCollector(err!));

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Undo should have been called automatically
      expect(undoCalls, 1);
      expect(undoReason, isA<Exception>());
      expect(errorCollector.values?.length, 1);

      command.dispose();
    });

    test('undoOnExecutionFailure = false', () async {
      int undoCalls = 0;

      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          stack.push('state');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw Exception('execution failed');
        },
        undo: (stack, reason) async {
          undoCalls++;
          stack.pop();
        },
        undoOnExecutionFailure: false,
      );

      final errorCollector = Collector<CommandError<void>>();
      command.errors.listen((err, _) => errorCollector(err!));

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Undo should NOT have been called
      expect(undoCalls, 0);
      expect(errorCollector.values?.length, 1);

      command.dispose();
    });
  });

  group('Undoable Command with restrictions', () {
    test('restriction prevents execution and undo', () async {
      final restriction = ValueNotifier<bool>(false);
      int executionCount = 0;

      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          executionCount++;
          stack.push('state');
        },
        undo: (stack, reason) async {
          stack.pop();
        },
        restriction: restriction,
      );

      // Should execute
      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executionCount, 1);

      // Restrict
      restriction.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Should not execute
      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(executionCount, 1);

      command.dispose();
    });

    test('ifRestrictedRunInstead callback', () async {
      final restriction = ValueNotifier<bool>(true);
      int normalExecutions = 0;
      int alternateExecutions = 0;

      final command = Command.createUndoableNoResult<String, int>(
        (param, stack) async {
          normalExecutions++;
          stack.push(normalExecutions);
        },
        undo: (stack, reason) async {
          stack.pop();
        },
        restriction: restriction,
        ifRestrictedRunInstead: (param) {
          alternateExecutions++;
        },
      );

      command.run('test');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(normalExecutions, 0);
      expect(alternateExecutions, 1);

      command.dispose();
    });
  });

  group('Undoable Command error scenarios', () {
    test('error in undo function', () async {
      final command = Command.createUndoableNoParamNoResult<String>(
        (stack) async {
          stack.push('state');
        },
        undo: (stack, reason) async {
          stack.pop();
          throw Exception('undo failed');
        },
      );

      final errorCollector = Collector<CommandError<void>>();
      command.errors.listen((err, _) => errorCollector(err!));

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Should have error wrapped in UndoException
      expect(errorCollector.values?.length, 1);
      expect(errorCollector.values![0].error, isA<UndoException>());

      command.dispose();
    });
  });

  group('Undoable Command with Chain.capture', () {
    setUp(() {
      Command.useChainCapture = false;
      Command.loggingHandler = null;
    });

    tearDown(() {
      Command.useChainCapture = false;
      Command.loggingHandler = null;
    });

    test('Undo with Chain.capture enabled', () async {
      Command.useChainCapture = true;
      int value = 0;

      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          value += 10;
          stack.push(value);
          return value;
        },
        undo: (stack, reason) async {
          final oldValue = stack.pop();
          value = oldValue - 10;
          return value;
        },
        initialValue: 0,
      );

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(value, 10);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(value, 0);

      command.dispose();
    });

    test('Undo with Chain.capture and error', () async {
      Command.useChainCapture = true;
      Object? capturedError;

      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          stack.push(42);
          return 42;
        },
        undo: (stack, reason) async {
          stack.pop();
          throw Exception('Undo failed');
        },
        initialValue: 0,
      );

      command.errors.listen((err, _) {
        if (err != null) capturedError = err.error;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(capturedError, isA<UndoException>());

      command.dispose();
    });

    test('Undo with logging handler and command name', () async {
      final logMessages = <String>[];
      Command.loggingHandler = (name, result) {
        if (name != null) logMessages.add(name);
      };

      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          stack.push(100);
          return 100;
        },
        undo: (stack, reason) async {
          stack.pop();
          return 0;
        },
        initialValue: 0,
        debugName: 'TestUndoCommand',
      );

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(logMessages.any((msg) => msg.contains('undo')), true);
      expect(logMessages.any((msg) => msg.contains('TestUndoCommand')), true);

      command.dispose();
    });
  });

  group('Undoable Command with includeLastResultInCommandResults', () {
    test('includeLastResultInCommandResults = true', () async {
      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          stack.push(42);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 42;
        },
        undo: (stack, reason) async {
          stack.pop();
          return 0;
        },
        initialValue: 0,
        includeLastResultInCommandResults: true,
      );

      final resultCollector = Collector<CommandResult<void, int>>();
      command.results.listen((result, _) => resultCollector(result));

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // When executing, should include last result
      final results = resultCollector.values!;
      expect(results.length, greaterThan(1));

      // First result should have isExecuting = true and include last data
      final executingResult = results.firstWhere((r) => r.isRunning);
      expect(executingResult.data, 0); // Last result included

      command.dispose();
    });
  });

  group('Undoable Command with synchronous undo', () {
    test('Synchronous undo with Chain.capture', () async {
      Command.useChainCapture = true;
      int value = 0;

      final command = Command.createUndoableNoParam<int, int>(
        (stack) async {
          value += 10;
          stack.push(value);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return value;
        },
        // Synchronous undo function (returns TResult instead of Future<TResult>)
        undo: (stack, reason) {
          final oldValue = stack.pop();
          value = oldValue - 10;
          return value; // Synchronous return
        },
        initialValue: 0,
      );

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(value, 10);
      expect(command.value, 10);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(value, 0);
      expect(command.value, 0);

      command.dispose();
      Command.useChainCapture = false;
    });
  });
}
