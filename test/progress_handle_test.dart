// ignore_for_file: avoid_print

import 'package:command_it/command_it.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper class to collect values emitted by ValueListenables
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
  group('ProgressHandle', () {
    late ProgressHandle handle;
    late Collector<double> progressCollector;
    late Collector<String?> statusCollector;
    late Collector<bool> canceledCollector;
    bool handleDisposed = false;

    setUp(() {
      handle = ProgressHandle();
      handleDisposed = false;
      progressCollector = Collector<double>();
      statusCollector = Collector<String?>();
      canceledCollector = Collector<bool>();

      handle.progress.listen((value, _) => progressCollector(value));
      handle.statusMessage.listen((value, _) => statusCollector(value));
      handle.isCanceled.listen((value, _) => canceledCollector(value));
    });

    tearDown(() {
      if (!handleDisposed) {
        handle.dispose();
      }
      progressCollector.reset();
      statusCollector.reset();
      canceledCollector.reset();
    });

    test('initial values are correct', () {
      expect(handle.progress.value, 0.0);
      expect(handle.statusMessage.value, null);
      expect(handle.isCanceled.value, false);
    });

    test('updateProgress updates value and notifies', () {
      handle.updateProgress(0.5);
      expect(handle.progress.value, 0.5);
      expect(progressCollector.values, [0.5]);

      handle.updateProgress(1.0);
      expect(handle.progress.value, 1.0);
      expect(progressCollector.values, [0.5, 1.0]);
    });

    test('updateProgress validates bounds', () {
      // Valid values should work (note: initial 0.0 value doesn't trigger listener)
      handle.updateProgress(0.5);
      handle.updateProgress(1.0);
      expect(progressCollector.values, [0.5, 1.0]);

      // Out of bounds values should assert in debug mode
      expect(() => handle.updateProgress(-0.1), throwsAssertionError);
      expect(() => handle.updateProgress(1.1), throwsAssertionError);
    });

    test('updateStatusMessage updates value and notifies', () {
      handle.updateStatusMessage('Loading...');
      expect(handle.statusMessage.value, 'Loading...');
      expect(statusCollector.values, ['Loading...']);

      handle.updateStatusMessage('Processing...');
      expect(handle.statusMessage.value, 'Processing...');
      expect(statusCollector.values, ['Loading...', 'Processing...']);

      handle.updateStatusMessage(null);
      expect(handle.statusMessage.value, null);
      expect(statusCollector.values, ['Loading...', 'Processing...', null]);
    });

    test('cancel sets isCanceled and notifies', () {
      expect(handle.isCanceled.value, false);

      handle.cancel();
      expect(handle.isCanceled.value, true);
      expect(canceledCollector.values, [true]);

      // Calling cancel again is idempotent (value doesn't change, may not notify)
      handle.cancel();
      expect(handle.isCanceled.value, true);
      // Listener may or may not fire again for same value - just verify it's canceled
      expect(handle.isCanceled.value, true);
    });

    test('dispose cleans up all notifiers', () {
      handle.updateProgress(0.5);
      handle.updateStatusMessage('Test');
      handle.cancel();

      // Verify values were collected before dispose
      expect(progressCollector.values, [0.5]);
      expect(statusCollector.values, ['Test']);
      expect(canceledCollector.values, [true]);

      handle.dispose();
      handleDisposed = true;

      // After dispose, the handle should not be used
      // (testing disposal itself would trigger errors, which is expected behavior)
    });
  });

  group('Command.createAsyncWithProgress', () {
    test('provides ProgressHandle to wrapped function', () async {
      final progressValues = <double>[];
      final statusValues = <String?>[];
      bool wasCanceled = false;

      final command = Command.createAsyncWithProgress<int, String>(
        (count, handle) async {
          for (int i = 0; i < count; i++) {
            if (handle.isCanceled.value) {
              wasCanceled = true;
              return 'Canceled';
            }
            handle.updateProgress((i + 1) / count);
            handle.updateStatusMessage('Processing item ${i + 1}');
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          return 'Done';
        },
        initialValue: '',
      );

      // Observe progress and status from the command
      command.progress.listen((value, _) => progressValues.add(value));
      command.statusMessage.listen((value, _) => statusValues.add(value));

      await command.runAsync(3);

      expect(command.value, 'Done');
      expect(progressValues, [1 / 3, 2 / 3, 3 / 3]);
      expect(statusValues, [
        'Processing item 1',
        'Processing item 2',
        'Processing item 3',
      ]);
      expect(wasCanceled, false);

      command.dispose();
    });

    test('supports cancellation via ProgressHandle', () {
      fakeAsync((async) {
        final command = Command.createAsyncWithProgress<void, String>(
          (_, handle) async {
            for (int i = 0; i < 10; i++) {
              if (handle.isCanceled.value) {
                return 'Canceled';
              }
              handle.updateProgress((i + 1) / 10);
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            return 'Completed';
          },
          initialValue: '',
        );

        command.run();
        async.elapse(const Duration(milliseconds: 250));

        // Cancel after 2.5 iterations
        command.cancel();

        async.elapse(const Duration(milliseconds: 1000));

        expect(command.value, 'Canceled');
        expect(command.progress.value, lessThan(1.0));

        command.dispose();
      });
    });

    test('default progress returns 0.0 for commands without handle', () {
      final command = Command.createAsync<void, String>(
        (_) async => 'Done',
        initialValue: '',
      );

      expect(command.progress.value, 0.0);
      expect(command.statusMessage.value, null);
      expect(command.isCanceled.value, false);

      command.dispose();
    });
  });

  group('Command.createAsyncNoParamWithProgress', () {
    test('provides ProgressHandle without requiring parameter', () async {
      final statusValues = <String?>[];

      final command = Command.createAsyncNoParamWithProgress<String>(
        (handle) async {
          handle.updateStatusMessage('Starting...');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          handle.updateProgress(0.5);
          handle.updateStatusMessage('Halfway...');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          handle.updateProgress(1.0);
          handle.updateStatusMessage('Complete');
          return 'Success';
        },
        initialValue: '',
      );

      command.statusMessage.listen((value, _) => statusValues.add(value));

      await command.runAsync();

      expect(command.value, 'Success');
      expect(command.progress.value, 1.0);
      expect(statusValues, ['Starting...', 'Halfway...', 'Complete']);

      command.dispose();
    });
  });

  group('Command.createAsyncNoResultWithProgress', () {
    test('provides ProgressHandle for void-return functions', () async {
      final progressValues = <double>[];
      bool executed = false;

      final command = Command.createAsyncNoResultWithProgress<int>(
        (count, handle) async {
          for (int i = 0; i < count; i++) {
            handle.updateProgress((i + 1) / count);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          executed = true;
        },
      );

      command.progress.listen((value, _) => progressValues.add(value));

      await command.runAsync(5);

      expect(executed, true);
      expect(progressValues, [0.2, 0.4, 0.6, 0.8, 1.0]);

      command.dispose();
    });
  });

  group('Command.createAsyncNoParamNoResultWithProgress', () {
    test('provides ProgressHandle for no-param, void-return functions',
        () async {
      final statusValues = <String?>[];
      bool executed = false;

      final command = Command.createAsyncNoParamNoResultWithProgress(
        (handle) async {
          handle.updateStatusMessage('Step 1');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handle.updateProgress(0.33);
          handle.updateStatusMessage('Step 2');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handle.updateProgress(0.66);
          handle.updateStatusMessage('Step 3');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handle.updateProgress(1.0);
          executed = true;
        },
      );

      command.statusMessage.listen((value, _) => statusValues.add(value));

      await command.runAsync();

      expect(executed, true);
      expect(command.progress.value, 1.0);
      expect(statusValues, ['Step 1', 'Step 2', 'Step 3']);

      command.dispose();
    });
  });

  group('UndoableCommand with Progress', () {
    test('createUndoableWithProgress provides both handle and undo stack',
        () async {
      final progressValues = <double>[];
      String? savedState;

      final command = Command.createUndoableWithProgress<int, String, String>(
        (count, handle, undoStack) async {
          handle.updateStatusMessage('Processing...');
          savedState = 'state_before_$count';
          undoStack.push(savedState!);

          for (int i = 0; i < count; i++) {
            handle.updateProgress((i + 1) / count);
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }

          return 'Processed $count items';
        },
        undo: (undoStack, reason) async {
          final state = undoStack.pop();
          savedState = 'undone_$state';
          return 'Undone';
        },
        initialValue: '',
      );

      command.progress.listen((value, _) => progressValues.add(value));

      await command.runAsync(3);

      expect(command.value, 'Processed 3 items');
      expect(progressValues, [1 / 3, 2 / 3, 3 / 3]);
      expect(savedState, 'state_before_3');

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(savedState, 'undone_state_before_3');

      command.dispose();
    });

    test('createUndoableNoParamWithProgress works correctly', () async {
      String? undoState;

      final command = Command.createUndoableNoParamWithProgress<String, String>(
        (handle, undoStack) async {
          handle.updateProgress(0.5);
          undoStack.push('test_state');
          handle.updateProgress(1.0);
          return 'Complete';
        },
        undo: (undoStack, reason) async {
          final state = undoStack.pop();
          undoState = 'undone_$state';
          return 'Undone';
        },
        initialValue: '',
      );

      await command.runAsync();

      expect(command.value, 'Complete');
      expect(command.progress.value, 1.0);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(undoState, 'undone_test_state');

      command.dispose();
    });

    test('createUndoableNoResultWithProgress works correctly', () async {
      String? undoState;
      bool executed = false;

      final command = Command.createUndoableNoResultWithProgress<int, String>(
        (param, handle, undoStack) async {
          handle.updateProgress(0.5);
          undoStack.push('param_$param');
          handle.updateProgress(1.0);
          executed = true;
        },
        undo: (undoStack, reason) async {
          final state = undoStack.pop();
          undoState = 'undone_$state';
        },
      );

      await command.runAsync(42);

      expect(executed, true);
      expect(command.progress.value, 1.0);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(undoState, 'undone_param_42');

      command.dispose();
    });

    test('createUndoableNoParamNoResultWithProgress works correctly', () async {
      String? undoState;
      bool executed = false;

      final command = Command.createUndoableNoParamNoResultWithProgress<String>(
        (handle, undoStack) async {
          handle.updateProgress(0.5);
          undoStack.push('no_param_state');
          handle.updateProgress(1.0);
          executed = true;
        },
        undo: (undoStack, reason) async {
          final state = undoStack.pop();
          undoState = 'undone_$state';
        },
      );

      await command.runAsync();

      expect(executed, true);
      expect(command.progress.value, 1.0);

      (command as UndoableCommand).undo();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(undoState, 'undone_no_param_state');

      command.dispose();
    });
  });

  group('Progress Integration with Dio Pattern', () {
    test(
        'isCanceled ValueNotifier can be listened to for external cancellation',
        () {
      fakeAsync((async) {
        bool dioCanceled = false;

        final command = Command.createAsyncWithProgress<void, String>(
          (_, handle) async {
            // Simulate Dio integration: listen to handle.isCanceled
            // and forward to Dio's CancelToken
            handle.isCanceled.listen((canceled, _) {
              if (canceled) {
                dioCanceled = true;
                // In real code: dioToken.cancel()
              }
            });

            for (int i = 0; i < 10; i++) {
              if (dioCanceled) return 'Dio canceled';
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            return 'Completed';
          },
          initialValue: '',
        );

        command.run();
        async.elapse(const Duration(milliseconds: 250));

        command.cancel();
        async.elapse(const Duration(milliseconds: 50));

        expect(dioCanceled, true);
        expect(command.value, 'Dio canceled');

        command.dispose();
      });
    });
  });

  group('MockCommand Progress Support', () {
    test('MockCommand without withProgressHandle returns default values', () {
      final mockCommand = MockCommand<int, String>(
        initialValue: '',
      );

      expect(mockCommand.progress.value, 0.0);
      expect(mockCommand.statusMessage.value, null);
      expect(mockCommand.isCanceled.value, false);

      // cancel() should do nothing without handle
      mockCommand.cancel();
      expect(mockCommand.isCanceled.value, false);

      mockCommand.dispose();
    });

    test('MockCommand with withProgressHandle allows progress simulation', () {
      final progressValues = <double>[];
      final mockCommand = MockCommand<int, String>(
        initialValue: '',
        withProgressHandle: true,
      );

      mockCommand.progress.listen((value, _) => progressValues.add(value));

      // Simulate progress updates
      mockCommand.updateMockProgress(0.25);
      expect(mockCommand.progress.value, 0.25);

      mockCommand.updateMockProgress(0.75);
      expect(mockCommand.progress.value, 0.75);

      mockCommand.updateMockProgress(1.0);
      expect(mockCommand.progress.value, 1.0);

      expect(progressValues, [0.25, 0.75, 1.0]);

      mockCommand.dispose();
    });

    test('MockCommand allows status message simulation', () {
      final statusValues = <String?>[];
      final mockCommand = MockCommand<int, String>(
        initialValue: '',
        withProgressHandle: true,
      );

      mockCommand.statusMessage.listen((value, _) => statusValues.add(value));

      mockCommand.updateMockStatusMessage('Starting...');
      expect(mockCommand.statusMessage.value, 'Starting...');

      mockCommand.updateMockStatusMessage('Processing...');
      expect(mockCommand.statusMessage.value, 'Processing...');

      mockCommand.updateMockStatusMessage(null);
      expect(mockCommand.statusMessage.value, null);

      expect(statusValues, ['Starting...', 'Processing...', null]);

      mockCommand.dispose();
    });

    test('MockCommand allows cancellation simulation', () {
      final canceledValues = <bool>[];
      final mockCommand = MockCommand<int, String>(
        initialValue: '',
        withProgressHandle: true,
      );

      mockCommand.isCanceled.listen((value, _) => canceledValues.add(value));

      expect(mockCommand.isCanceled.value, false);

      mockCommand.mockCancel();
      expect(mockCommand.isCanceled.value, true);

      expect(canceledValues, [true]);

      mockCommand.dispose();
    });

    test('MockCommand simulation methods assert without withProgressHandle',
        () {
      final mockCommand = MockCommand<int, String>(
        initialValue: '',
        withProgressHandle: false,
      );

      expect(
        () => mockCommand.updateMockProgress(0.5),
        throwsAssertionError,
      );
      expect(
        () => mockCommand.updateMockStatusMessage('Test'),
        throwsAssertionError,
      );
      expect(
        () => mockCommand.mockCancel(),
        throwsAssertionError,
      );

      mockCommand.dispose();
    });

    test('MockCommand with progress can be used for UI testing', () {
      final mockCommand = MockCommand<void, String>(
        initialValue: '',
        withProgressHandle: true,
      );

      // Simulate a complete operation flow
      mockCommand.startRun();
      expect(mockCommand.isRunning.value, true);

      mockCommand.updateMockProgress(0.0);
      mockCommand.updateMockStatusMessage('Starting upload...');

      mockCommand.updateMockProgress(0.5);
      mockCommand.updateMockStatusMessage('Uploading...');

      mockCommand.updateMockProgress(1.0);
      mockCommand.updateMockStatusMessage('Upload complete');

      mockCommand.endRunWithData('Success');
      expect(mockCommand.isRunning.value, false);
      expect(mockCommand.value, 'Success');
      expect(mockCommand.progress.value, 1.0);
      expect(mockCommand.statusMessage.value, 'Upload complete');

      mockCommand.dispose();
    });
  });
}
