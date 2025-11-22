// ignore_for_file: avoid_print, strict_raw_type

import 'package:command_it/command_it.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An object that can assist in representing the current state of Command while
/// testing different valueListenable of a Command. Basically a [List] with
/// initialize logic and null safe clear.
class Collector<T> {
  /// Holds a list of values being passed to this object.
  List<T>? values;

  /// Initializes [values] adds the incoming [value] to it.
  void call(T value) {
    values ??= <T>[];
    values!.add(value);
  }

  /// Check null and clear the list.
  void clear() {
    values?.clear();
  }

  void reset() {
    clear();
    values = null;
  }
}

/// A Custom Exception that overrides == operator to ease object comparison i
/// inside a [Collector].
class CustomException implements Exception {
  String message;

  CustomException(this.message);

  @override
  // ignore: hash_and_equals
  bool operator ==(Object other) =>
      other is CustomException && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'CustomException: $message';
}

void main() {
  /// Create commonly used collector for all the valueListenable in a [Command].
  /// The collectors simply collect the values emitted by the ValueListenable
  /// into a list and keep it for comparison later.
  final Collector<bool> canExecuteCollector = Collector<bool>();
  final Collector<bool> isExecutingCollector = Collector<bool>();
  final Collector<CommandResult> cmdResultCollector =
      Collector<CommandResult>();
  final Collector<CommandError> thrownExceptionCollector =
      Collector<CommandError>();
  final Collector pureResultCollector = Collector();

  /// A utility method to setup [Collector] for all the [ValueListenable] in a
  /// given command.
  void setupCollectors(Command command, {bool enablePrint = false}) {
    // Set up the collectors
    command.canRun.listen((b, _) {
      canExecuteCollector(b);
      if (enablePrint) {
        print('Can Execute $b');
      }
    });
    // Setup is Executing listener only for async commands.
    if (command is CommandAsync) {
      command.isRunning.listen((b, _) {
        isExecutingCollector(b);
        if (enablePrint) {
          print('isExecuting $b');
        }
      });
    }
    command.results.listen((cmdResult, _) {
      cmdResultCollector(cmdResult);
      if (enablePrint) {
        print('Command Result $cmdResult');
      }
    });
    command.errors.listen((cmdError, _) {
      thrownExceptionCollector(cmdError!);
      if (enablePrint) {
        print('Thrown Exceptions $cmdError');
      }
    });
    command.listen((pureResult, _) {
      pureResultCollector(pureResult);
      if (enablePrint) {
        print('Command returns $pureResult');
      }
    });
  }

  /// clear the common collectors before each test.
  setUp(() {
    canExecuteCollector.reset();
    isExecutingCollector.reset();
    cmdResultCollector.reset();
    thrownExceptionCollector.reset();
    pureResultCollector.reset();
  });

  group('Synchronous Command Testing', () {
    test('Execute simple sync action No Param No Result', () {
      int executionCount = 0;
      final command = Command.createSyncNoParamNoResult(() => executionCount++);

      expect(command.canRun.value, true);

      // Setup collectors for the command.
      setupCollectors(command);

      command.run();

      expect(command.canRun.value, true);
      expect(executionCount, 1);

      // Verify the collectors values.
      expect(pureResultCollector.values, [null]);
      expect(cmdResultCollector.values, isNull);
      expect(thrownExceptionCollector.values, isNull);
    });

    test('Execute simple sync action with canExecute restriction', () async {
      // restriction false means command can execute
      // if restriction is true, then command cannot execute.
      // We test both cases in this test
      final restriction = ValueNotifier<bool>(false);

      var executionCount = 0;
      var insteadCalledCount = 0;

      final command = Command.createSyncNoParamNoResult(
        () => executionCount++,
        restriction: restriction,
        ifRestrictedRunInstead: () {
          insteadCalledCount++;
        },
      );

      expect(command.canRun.value, true);

      // Setup Collectors
      setupCollectors(command);

      command.run();

      expect(executionCount, 1);
      expect(insteadCalledCount, 0);

      expect(command.canRun.value, true);

      restriction.value = true;

      expect(command.canRun.value, false);

      command.run();

      expect(executionCount, 1);
      expect(insteadCalledCount, 1);
    });

    test(
      'Execute simple async action with canExecute restriction with ifRestrictedInstead handler and param',
      () async {
        // restriction false means command can execute
        // if restriction is true, then command cannot execute.
        // We test both cases in this test
        final restriction = ValueNotifier<bool>(false);

        var executionCount = 0;
        int? insteadCalledParam;

        final command = Command.createAsyncNoResult<int>(
          (param) async {
            executionCount++;
          },
          restriction: restriction,
          ifRestrictedRunInstead: (param) {
            insteadCalledParam = param;
          },
        );

        expect(command.canRun.value, true);

        // Setup Collectors
        setupCollectors(command);

        command.run(42);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(executionCount, 1);
        expect(insteadCalledParam, null);

        expect(command.canRun.value, true);

        restriction.value = true;

        expect(command.canRun.value, false);

        command.run(42);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(executionCount, 1);
        expect(insteadCalledParam, 42);
      },
    );

    test('Execute simple sync action with exception', () {
      final command = Command.createSyncNoParamNoResult(
        () => throw CustomException('Intentional'),
      );

      setupCollectors(command);

      expect(command.canRun.value, true);
      expect(command.errors.value, null);

      command.run();
      expect(command.results.value.error, isA<CustomException>());
      expect(command.errors.value!.error, isA<CustomException>());

      expect(command.canRun.value, true);

      // verify Collectors.
      expect(cmdResultCollector.values, [
        CommandResult<void, void>(
          null,
          null,
          CustomException('Intentional'),
          false,
        ),
      ]);
      expect(thrownExceptionCollector.values, [
        CommandError<void>(
          command: null,
          error: CustomException('Intentional'),
        ),
      ]);
    });

    test('Execute simple sync action with parameter', () {
      int executionCount = 0;
      final command = Command.createSyncNoResult<String>((x) {
        print('action: $x');
        executionCount++;
      });
      // Setup Collectors.
      setupCollectors(command);

      expect(command.canRun.value, true);

      command.run('Parameter');
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canRun.value, true);

      // Verify Collectors
      expect(thrownExceptionCollector.values, isNull);
      expect(pureResultCollector.values, [null]);
    });

    test('Execute simple sync function without parameter', () {
      int executionCount = 0;
      final command = Command.createSyncNoParam<String>(() {
        print('action: ');
        executionCount++;
        return '4711';
      }, initialValue: '');

      expect(command.canRun.value, true);
      // Setup Collectors
      setupCollectors(command);
      command.run();

      expect(command.value, '4711');
      expect(
        command.results.value,
        const CommandResult<void, String>(null, '4711', null, false),
      );
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canRun.value, true);

      // verify collectors
      expect(thrownExceptionCollector.values, isNull);
      expect(pureResultCollector.values, ['4711']);
      expect(cmdResultCollector.values, [
        const CommandResult<void, String>(null, '4711', null, false),
      ]);
    });

    test('Execute simple sync function with parameter and result', () {
      int executionCount = 0;
      final command = Command.createSync<String, String>((s) {
        print('action: $s');
        executionCount++;
        return s + s;
      }, initialValue: '');

      expect(command.canRun.value, true);
      // Setup Collectors
      setupCollectors(command);
      command.run('4711');
      expect(command.value, '47114711');

      expect(
        command.results.value,
        const CommandResult<String, String>('4711', '47114711', null, false),
      );
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canRun.value, true);

      // verify collectors
      expect(thrownExceptionCollector.values, isNull);
      expect(pureResultCollector.values, ['47114711']);
      expect(cmdResultCollector.values, [
        const CommandResult<String?, String?>('4711', '47114711', null, false),
      ]);
    });
    test(
      'Execute simple sync function with parameter and result with nullable types',
      () {
        int executionCount = 0;
        final command = Command.createSync<String?, String?>((s) {
          print('action: $s');
          executionCount++;
          return s;
        }, initialValue: '');

        expect(command.canRun.value, true);
        // Setup Collectors
        setupCollectors(command);
        command.run(null);
        expect(command.value, null);

        expect(
          command.results.value,
          const CommandResult<String?, String?>(null, null, null, false),
        );

        expect(command.errors.value, null);
        expect(executionCount, 1);

        expect(command.canRun.value, true);

        // verify collectors
        expect(thrownExceptionCollector.values, isNull);
        expect(pureResultCollector.values, [null]);
        expect(cmdResultCollector.values, [
          const CommandResult<String?, String?>(null, null, null, false),
        ]);
      },
    );
    test('Execute simple sync function with parameter passing null', () {
      final command = Command.createSync<String, String>((s) {
        print('action: $s');
        return s;
      }, initialValue: '');

      expect(command.canRun.value, true);
      // Setup Collectors
      setupCollectors(command);
      expect(() => command.run(null), throwsA(isA<AssertionError>()));
    });
  });
  Future<String> slowAsyncFunction(String? s) async {
    print('___Start__Slow__Action__________');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('___End__Slow__Action__________');
    return s!;
  }

  group('Asynchronous Command Testing', () {
    test('Execute simple async function with no Parameter no Result', () {
      var executionCount = 0;

      final command = Command.createAsyncNoParamNoResult(
        () async {
          executionCount++;
          await slowAsyncFunction('no pram');
        },
        // restriction: setExecutionStateCommand,
      );

      // set up all the collectors for this command.
      setupCollectors(command);

      // Ensure command is not executing already.
      expect(
        command.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      // Execute command.
      fakeAsync((async) {
        command.run();

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isRunning.value, false);

        expect(executionCount, 1);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false]);

        expect(canExecuteCollector.values, [false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<void, void>(null, null, null, true),
          const CommandResult<void, void>(null, null, null, false),
        ]);
      });
    });

    // test('Handle calling noParamFunctions being called with param', () async {
    //   var executionCount = 0;

    //   final command = Command.createAsyncNoParamNoResult(
    //     () async {
    //       executionCount++;
    //       await slowAsyncFunction('no pram');
    //     },
    //     // restriction: setExecutionStateCommand,
    //   );

    //   // set up all the collectors for this command.
    //   setupCollectors(command);

    //   // Ensure command is not executing already.
    //   expect(command.isExecuting.value, false,
    //       reason: 'IsExecuting before true');

    //   // Execute command.
    //   command.run('Done');

    //   // Waiting till the async function has finished executing.
    //   await Future<void>.delayed(Duration(milliseconds: 10));

    //   expect(command.isExecuting.value, false);

    //   expect(executionCount, 1);

    //   // Expected to return false, true, false
    //   // but somehow skips the initial state which is false.
    //   expect(isExecutingCollector.values, [true, false]);

    //   expect(canExecuteCollector.values, [false, true]);

    //   expect(cmdResultCollector.values, [
    //     CommandResult<void, void>(null, null, null, true),
    //     CommandResult<void, void>(null, null, null, false),
    //   ]);
    // });

    test('Execute simple async function with No parameter', () async {
      var executionCount = 0;

      final command = Command.createAsyncNoParam<String>(() async {
        executionCount++;
        // ignore: unnecessary_await_in_return
        return await slowAsyncFunction('No Param');
      }, initialValue: 'Initial Value');

      // set up all the collectors for this command.
      setupCollectors(command);

      // Ensure command is not executing already.
      expect(
        command.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // Execute command.
        command.run();

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isRunning.value, false);

        expect(executionCount, 1);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false]);

        expect(canExecuteCollector.values, [false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<void, String>(null, null, null, true),
          const CommandResult<void, String>(null, 'No Param', null, false),
        ]);
      });
    });
    test('Execute simple async function with parameter', () async {
      var executionCount = 0;

      final command = Command.createAsyncNoResult<String>(
        (s) async {
          executionCount++;
          await slowAsyncFunction(s);
        },
        // restriction: setExecutionStateCommand,
      );

      // set up all the collectors for this command.
      setupCollectors(command);

      // Ensure command is not executing already.
      expect(
        command.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // Execute command.
        command.run('Done');

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isRunning.value, false);

        expect(executionCount, 1);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false]);

        expect(canExecuteCollector.values, [false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, void>('Done', null, null, false),
        ]);
      });
    });

    test(
      'Execute simple async function with parameter and return value',
      () async {
        var executionCount = 0;

        final command = Command.createAsync<String, String>((s) async {
          executionCount++;
          return slowAsyncFunction(s);
        }, initialValue: '');

        setupCollectors(command);

        expect(
          command.isRunning.value,
          false,
          reason: 'IsExecuting before true',
        );

        fakeAsync((async) {
          command.run('Done');

          // Waiting till the async function has finished executing.
          async.elapse(const Duration(milliseconds: 10));

          expect(command.isRunning.value, false);

          expect(executionCount, 1);

          // Expected to return false, true, false
          // but somehow skips the initial state which is false.
          expect(isExecutingCollector.values, [true, false]);

          expect(canExecuteCollector.values, [false, true]);

          expect(cmdResultCollector.values, [
            const CommandResult<String, String>('Done', null, null, true),
            const CommandResult<String, String>('Done', 'Done', null, false),
          ]);
        });
      },
    );

    test('Execute simple async function call while already running', () async {
      var executionCount = 0;

      final command = Command.createAsync<String, String>((s) async {
        executionCount++;
        return slowAsyncFunction(s);
      }, initialValue: 'Initial Value');

      setupCollectors(command);

      expect(
        command.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      expect(command.value, 'Initial Value');

      command.run('Done');
      command.run('Done2'); // should not execute

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(command.isRunning.value, false);
      expect(executionCount, 1);

      // The expectation ensures that first command execution went through and
      // second command execution didn't wen through.
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Done', null, null, true),
        const CommandResult<String, String>('Done', 'Done', null, false),
      ]);
    });

    test('Execute simple async function called twice with delay', () async {
      var executionCount = 0;

      final command = Command.createAsync<String, String>((s) async {
        executionCount++;
        return slowAsyncFunction(s);
      }, initialValue: 'Initial Value');

      setupCollectors(command);

      expect(
        command.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      command.run('Done');

      // Reuse the same command after 50 milliseconds and it should work.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      command.run('Done2');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(command.isRunning.value, false);
      expect(executionCount, 2);

      // Verify all the necessary collectors
      expect(
          canExecuteCollector.values,
          [
            false,
            true,
            false,
            true,
          ],
          reason: 'CanExecute order is wrong');
      expect(
          isExecutingCollector.values,
          [
            true,
            false,
            true,
            false,
          ],
          reason: 'IsExecuting order is wrong.');
      expect(pureResultCollector.values, ['Done', 'Done2']);
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Done', null, null, true),
        const CommandResult<String, String>('Done', 'Done', null, false),
        const CommandResult<String, String>('Done2', null, null, true),
        const CommandResult<String, String>('Done2', 'Done2', null, false),
      ]);
    });

    test(
      'Execute simple async function called twice with delay and emitLastResult=true',
      () async {
        var executionCount = 0;

        final command = Command.createAsync<String, String>(
          (s) async {
            executionCount++;
            return slowAsyncFunction(s);
          },
          initialValue: 'Initial Value',
          includeLastResultInCommandResults: true,
        );

        // Setup all collectors.
        setupCollectors(command);

        expect(
          command.isRunning.value,
          false,
          reason: 'IsExecuting before true',
        );

        command.run('Done');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        command('Done2');

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(command.isRunning.value, false);
        expect(executionCount, 2);

        // Verify all the necessary collectors
        expect(
            canExecuteCollector.values,
            [
              false,
              true,
              false,
              true,
            ],
            reason: 'CanExecute order is wrong');
        expect(
            isExecutingCollector.values,
            [
              true,
              false,
              true,
              false,
            ],
            reason: 'IsExecuting order is wrong.');
        expect(pureResultCollector.values, ['Done', 'Done2']);
        expect(cmdResultCollector.values, [
          const CommandResult<String, String>(
            'Done',
            'Initial Value',
            null,
            true,
          ),
          const CommandResult<String, String>('Done', 'Done', null, false),
          const CommandResult<String, String>('Done2', 'Done', null, true),
          const CommandResult<String, String>('Done2', 'Done2', null, false),
        ]);
      },
    );
    Future<String> slowAsyncFunctionFail(String? s) async {
      print('___Start____Action___Will throw_______');
      throw CustomException('Intentionally');
    }

    test(
      'async function with exception with firstLocalThenGlobal and listeners',
      () async {
        final command = Command.createAsync<String, String>(
          slowAsyncFunctionFail,
          initialValue: 'Initial Value',
          errorFilter: const ErrorHandlerGlobalIfNoLocal(),
        );

        setupCollectors(command);

        expect(command.canRun.value, true);
        expect(command.isRunning.value, false);

        expect(command.errors.value, isNull);
        fakeAsync((async) {
          command.run('Done');

          async.elapse(Duration.zero);

          expect(command.canRun.value, true);
          expect(command.isRunning.value, false);

          // Verify nothing came through pure results from .
          expect(pureResultCollector.values, isNull);

          expect(thrownExceptionCollector.values, [
            CommandError<String>(
              paramData: 'Done',
              error: CustomException('Intentionally'),
              command: null,
            ),
          ]);

          // Verify the results collector.
          expect(cmdResultCollector.values, [
            const CommandResult<String, String>('Done', null, null, true),
            CommandResult<String, String>(
              'Done',
              null,
              CustomException('Intentionally'),
              false,
            ),
          ]);
        });
      },
    );
  });

  group('Test Global parameters and general utilities like dipose', () {
    test('Check Command Dispose', () async {
      final command = Command.createSync<String, String?>((s) {
        return s;
      }, initialValue: 'Initial Value');
      // Setup collectors. Note: This indirectly sets listeners.
      setupCollectors(command);

      // ignore: invalid_use_of_protected_member
      expect(command.hasListeners, true);

      // execute command and ensure there is no values in any of the collectors.
      command.dispose();

      // Check valid exception is raised trying to use disposed value notifiers.
      command('Done');

      // verify collectors
      expect(canExecuteCollector.values, isNull);
      expect(cmdResultCollector.values, isNull);
      expect(pureResultCollector.values, isNull);
      expect(thrownExceptionCollector.values, isNull);
      expect(isExecutingCollector.values, isNull);
    });

    test('Check catchAlwaysDefault = false', () async {
      final command = Command.createAsync<String, String>((s) async {
        throw CustomException('Intentional');
      }, initialValue: 'Initial Value');
      Command.errorFilterDefault = PredicatesErrorFilter([
        (error, s) => ErrorReaction.throwException,
      ]);

      // Setup collectors.
      setupCollectors(command);

      command('Done');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // verify collectors

      // the canExecuteCollector should not be empty because the isExecutingCollector isn't empty.
      // maybe it is only happening inside the test environment.
      expect(canExecuteCollector.values, isNotEmpty);
      expect(isExecutingCollector.values, isNotEmpty);
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Done', null, null, true),
        CommandResult<String, String>(
          'Done',
          null,
          CustomException('Intentional'),
          false,
        ),
      ]);
      expect(pureResultCollector.values, isNull);
      expect(thrownExceptionCollector.values, [
        CommandError(paramData: 'Done', error: CustomException('Intentional')),
      ]);
      expect(isExecutingCollector.values, isNotEmpty);

      /// set default back to standard
      Command.errorFilterDefault = const ErrorHandlerGlobalIfNoLocal();
    });

    test('Test excecuteWithFuture', () async {
      final command = Command.createAsync<String, String?>((s) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return s;
      }, initialValue: 'Initial Value');

      final Stopwatch sw = Stopwatch()..start();
      final commandFuture = command.runAsync('Done');
      final result = await commandFuture.timeout(
        const Duration(milliseconds: 50),
      );
      final duration = sw.elapsedMilliseconds;
      sw.stop();

      // verify collectors
      expect(duration, greaterThan(5));
      expect(result, 'Done');
    });

    test(
      'Check globalExceptionHadnler is called in Sync/Async Command',
      () async {
        final command = Command.createSync<String, String>(
          (s) {
            throw CustomException('Intentional');
          },
          initialValue: 'Initial Value',
          debugName: 'globalHandler',
        );

        Command.globalExceptionHandler = expectAsync2((ce, s) {
          expect(ce.commandName, 'globalHandler');
          expect(ce, isA<CommandError>());
          expect(
            ce,
            CommandError<dynamic>(
              paramData: 'Done',
              error: CustomException('Intentional'),
            ),
          );
        });

        command('Done');

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final command2 = Command.createSync<String, String>(
          (s) {
            throw CustomException('Intentional');
          },
          initialValue: 'Initial Value',
          debugName: 'globalHandler',
          errorFilter: PredicatesErrorFilter([
            (error, s) => ErrorReaction.throwException,
          ]),
        );

        expectLater(() => command2('Done'), throwsA(isA<CustomException>()));
      },
    );

    test('Check logging Handler is called in Sync/Async command', () async {
      final command = Command.createSync<String, String?>(
        (s) {
          return s;
        },
        initialValue: 'Initial Value',
        debugName: 'loggingHandler',
      );
      // Set Global catchAlwaysDefault to false.
      // It defaults to true.
      Command.loggingHandler = expectAsync2((
        String? debugName,
        CommandResult cr,
      ) {
        expect(debugName, 'loggingHandler');
        expect(cr, isA<CommandResult>());
        expect(
          cr,
          const CommandResult<String, String?>('Done', 'Done', null, false),
        );
      }, count: 2);

      command('Done');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final command2 = Command.createAsync<String, String?>(
        (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return s;
        },
        initialValue: 'Initial Value',
        debugName: 'loggingHandler',
      );

      command2('Done');
    });
    tearDown(() {
      Command.loggingHandler = null;
      Command.globalExceptionHandler = null;
    });
  });
  group('Test notifyOnlyWhenValueChanges related logic', () {
    Future<String> slowAsyncFunction(String s) async {
      print('___Start__Slow__Action__________');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      print('___End__Slow__Action__________');
      return s;
    }

    test(
      "Test default notification behaviour when value doesn't change",
      () async {
        int executionCount = 0;
        final Command commandForNotificationTest =
            Command.createAsync<String, String>((s) async {
          executionCount++;
          return slowAsyncFunction(s);
        }, initialValue: 'Initial Value');
        setupCollectors(commandForNotificationTest);
        expect(
          commandForNotificationTest.isRunning.value,
          false,
          reason: 'IsExecuting before true',
        );

        fakeAsync((async) {
          // First execution
          commandForNotificationTest.run('Done');
          async.elapse(const Duration(milliseconds: 10));
          expect(commandForNotificationTest.isRunning.value, false);
          expect(executionCount, 1);

          // async.elapse(const Duration(milliseconds: 10));
          // Second execution
          commandForNotificationTest.run('Done');
          async.elapse(const Duration(milliseconds: 10));
          expect(commandForNotificationTest.isRunning.value, false);
          expect(executionCount, 2);

          // Expected to return false, true, false
          // but somehow skips the initial state which is false.
          expect(isExecutingCollector.values, [true, false, true, false]);

          expect(canExecuteCollector.values, [false, true, false, true]);

          expect(cmdResultCollector.values, [
            const CommandResult<String, void>('Done', null, null, true),
            const CommandResult<String, String>('Done', 'Done', null, false),
            const CommandResult<String, void>('Done', null, null, true),
            const CommandResult<String, String>('Done', 'Done', null, false),
          ]);

          expect(pureResultCollector.values, ['Done', 'Done']);
        });
      },
    );

    test('Test default notification behaviour when value changes', () async {
      int executionCount = 0;
      final Command commandForNotificationTest =
          Command.createAsync<String, String>((s) async {
        executionCount++;
        return slowAsyncFunction(s);
      }, initialValue: 'Initial Value');
      setupCollectors(commandForNotificationTest);
      expect(
        commandForNotificationTest.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );
      fakeAsync((async) {
        // First execution
        commandForNotificationTest.run('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.run('Done2');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 2);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false, true, false]);

        expect(canExecuteCollector.values, [false, true, false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, String>('Done', 'Done', null, false),
          const CommandResult<String, void>('Done2', null, null, true),
          const CommandResult<String, String>('Done2', 'Done2', null, false),
        ]);

        expect(pureResultCollector.values, ['Done', 'Done2']);
      });
    });

    test('Test notifyOnlyWhenValueChanges flag as true', () async {
      int executionCount = 0;
      final Command commandForNotificationTest =
          Command.createAsync<String, String>(
        (s) async {
          executionCount++;
          return slowAsyncFunction(s);
        },
        initialValue: 'Initial Value',
        notifyOnlyWhenValueChanges: true,
      );
      setupCollectors(commandForNotificationTest);
      expect(
        commandForNotificationTest.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // First execution
        commandForNotificationTest.run('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.run('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 2);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false, true, false]);

        expect(canExecuteCollector.values, [false, true, false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, String>('Done', 'Done', null, false),
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, String>('Done', 'Done', null, false),
        ]);
        // Thos is the main result evaluation. :)
        expect(pureResultCollector.values, ['Done']);
      });
    });

    test('Test notifyOnlyWhenValueChanges flag as false', () async {
      int executionCount = 0;
      final Command commandForNotificationTest =
          Command.createAsync<String, String>(
        (s) async {
          executionCount++;
          return slowAsyncFunction(s);
        },
        initialValue: 'Initial Value',
        // ignore: avoid_redundant_argument_values
        notifyOnlyWhenValueChanges: false,
      );
      setupCollectors(commandForNotificationTest);
      expect(
        commandForNotificationTest.isRunning.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // First execution
        commandForNotificationTest.run('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.run('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isRunning.value, false);
        expect(executionCount, 2);

        // Expected to return false, true, false
        // but somehow skips the initial state which is false.
        expect(isExecutingCollector.values, [true, false, true, false]);

        expect(canExecuteCollector.values, [false, true, false, true]);

        expect(cmdResultCollector.values, [
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, String>('Done', 'Done', null, false),
          const CommandResult<String, void>('Done', null, null, true),
          const CommandResult<String, String>('Done', 'Done', null, false),
        ]);

        expect(pureResultCollector.values, ['Done', 'Done']);
      });
    });
  });

  group('Test Command Builder', () {
    testWidgets('Test Command Builder', (WidgetTester tester) async {
      final testCommand = Command.createAsyncNoParam<String>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        print('Command is called');
        return 'New Value';
      }, initialValue: 'Initial Value');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CommandBuilder<void, String>(
                command: testCommand,
                onData: (context, value, _) {
                  return Text(value);
                },
                whileRunning: (_, __, ___) {
                  return const Text('Is Executing');
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.widgetWithText(Center, 'Initial Value'), findsOneWidget);
      testCommand();
      await tester.pump(const Duration(milliseconds: 500));
      // By now circular progress indicator should be visible.
      expect(find.widgetWithText(Center, 'Initial Value'), findsNothing);
      expect(find.widgetWithText(Center, 'Is Executing'), findsOneWidget);
      // Wait for command to finish async execution.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.widgetWithText(Center, 'Is Executing'), findsNothing);
      expect(find.widgetWithText(Center, 'New Value'), findsOneWidget);
    });

    testWidgets('Test Command Builder On error', (WidgetTester tester) async {
      final testCommand = Command.createAsyncNoParam<String>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        throw CustomException('Exception From Command');
      }, initialValue: 'Initial Value')
        ..errors.listen((error, _) {
          print('Error: $error');
        });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CommandBuilder<void, String>(
                command: testCommand,
                onData: (context, value, _) {
                  return Text(value);
                },
                whileRunning: (_, __, ___) {
                  return const Text('Is Executing');
                },
                onError: (_, error, __, ___) {
                  if (error is CustomException) {
                    return Text(error.message);
                  }
                  return const Text('Unknown Exception Occurred');
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.widgetWithText(Center, 'Initial Value'), findsOneWidget);
      testCommand();
      await tester.pump(const Duration(milliseconds: 500));
      // By now circular progress indicator should be visible.
      expect(find.widgetWithText(Center, 'Initial Value'), findsNothing);
      expect(find.widgetWithText(Center, 'Is Executing'), findsOneWidget);
      // Wait for command to finish async execution.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.widgetWithText(Center, 'Is Executing'), findsNothing);
      expect(
        find.widgetWithText(Center, 'Exception From Command'),
        findsOneWidget,
      );
    });
    testWidgets('Test toWidget with Data', (WidgetTester tester) async {
      final testCommand = Command.createAsyncNoParam<String>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return 'New Value';
      }, initialValue: 'Initial Value');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<CommandResult>(
              valueListenable: testCommand.results,
              builder: (_, context, __) {
                return Center(
                  child: testCommand.toWidget(
                    onResult: (value, _) {
                      return Text(value);
                    },
                    whileRunning: (_, __) {
                      return const Text('Is Executing');
                    },
                    onError: (error, __) {
                      if (error is CustomException) {
                        return Text(error.message);
                      }
                      return const Text('Unknown Exception Occurred');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.widgetWithText(Center, 'Initial Value'), findsOneWidget);
      testCommand();
      await tester.pump(const Duration(milliseconds: 500));
      // By now circular progress indicator should be visible.
      expect(find.widgetWithText(Center, 'Initial Value'), findsNothing);
      expect(find.widgetWithText(Center, 'Is Executing'), findsOneWidget);
      // Wait for command to finish async execution.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.widgetWithText(Center, 'Is Executing'), findsNothing);
      expect(find.widgetWithText(Center, 'New Value'), findsOneWidget);
    });

    testWidgets('Test toWidget with Error', (WidgetTester tester) async {
      final testCommand = Command.createAsyncNoParam<String>(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        throw CustomException('Exception From Command');
      }, initialValue: 'Initial Value')
        ..errors.listen((error, _) {
          print('Error: $error');
        });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<CommandResult>(
              valueListenable: testCommand.results,
              builder: (_, context, __) {
                return Center(
                  child: testCommand.toWidget(
                    onResult: (value, _) {
                      return Text(value);
                    },
                    whileRunning: (_, __) {
                      return const Text('Is Executing');
                    },
                    onError: (error, __) {
                      if (error is CustomException) {
                        return Text(error.message);
                      }
                      return const Text('Unknown Exception Occurred');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsOneWidget);
      expect(find.widgetWithText(Center, 'Initial Value'), findsOneWidget);
      testCommand();
      await tester.pump(const Duration(milliseconds: 500));
      // By now circular progress indicator should be visible.
      expect(find.widgetWithText(Center, 'Initial Value'), findsNothing);
      expect(find.widgetWithText(Center, 'Is Executing'), findsOneWidget);
      // Wait for command to finish async execution.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.widgetWithText(Center, 'Is Executing'), findsNothing);
      expect(
        find.widgetWithText(Center, 'Exception From Command'),
        findsOneWidget,
      );
    });

    testWidgets('Test CommandBuilder with onSuccess',
        (WidgetTester tester) async {
      final testCommand = Command.createAsyncNoParamNoResult(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandBuilder<void, void>(
              command: testCommand,
              onSuccess: (context, _) => const Text('Success!'),
            ),
          ),
        ),
      );

      testCommand.run();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Success!'), findsOneWidget);
    });

    testWidgets('Test CommandBuilder with runCommandOnFirstBuild=false',
        (WidgetTester tester) async {
      var executionCount = 0;
      final testCommand = Command.createAsyncNoParamNoResult(() async {
        executionCount++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandBuilder<void, void>(
              command: testCommand,
              runCommandOnFirstBuild: false, // Should not run
              onSuccess: (context, _) => const Text('Success!'),
              whileRunning: (context, _, __) => const Text('Loading'),
            ),
          ),
        ),
      );

      await tester.pump();

      // Command should not have executed
      expect(executionCount, 0);
      expect(find.text('Loading'), findsNothing);
    });

    testWidgets(
        'Test CommandBuilder with runCommandOnFirstBuild=true (no param)',
        (WidgetTester tester) async {
      var executionCount = 0;
      final testCommand = Command.createAsyncNoParamNoResult(() async {
        executionCount++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandBuilder<void, void>(
              command: testCommand,
              runCommandOnFirstBuild: true,
              onSuccess: (context, _) => const Text('Success!'),
              whileRunning: (context, _, __) => const Text('Loading'),
            ),
          ),
        ),
      );

      // Pump to allow initState to run and command to start
      await tester.pump(const Duration(milliseconds: 10));

      // Command should have executed once
      expect(executionCount, 1);
      expect(find.text('Loading'), findsOneWidget);

      // Wait for command to complete
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Success!'), findsOneWidget);
      expect(executionCount, 1); // Should still be 1 (not run again)
    });

    testWidgets(
        'Test CommandBuilder with runCommandOnFirstBuild=true and initialParam',
        (WidgetTester tester) async {
      String? receivedParam;
      final testCommand = Command.createAsync<String, String>(
        (param) async {
          receivedParam = param;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return 'Result: $param';
        },
        initialValue: '', // Named parameter
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandBuilder<String, String>(
              command: testCommand,
              runCommandOnFirstBuild: true,
              initialParam: 'test-param',
              onData: (context, data, _) => Text(data),
              whileRunning: (context, _, __) => const Text('Loading'),
            ),
          ),
        ),
      );

      // Pump to allow initState to run and command to start
      await tester.pump(const Duration(milliseconds: 10));

      // Command should have been called with the param
      expect(receivedParam, 'test-param');
      expect(find.text('Loading'), findsOneWidget);

      // Wait for command to complete
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Result: test-param'), findsOneWidget);
    });
  });
  group('UndoableCommand', () {
    test(
      'Execute simple async function with no Parameter no Result that throws',
      () {
        var executionCount = 0;
        var undoCount = 0;
        var undoValue = 0;
        Object? reason;

        final command = Command.createUndoableNoParamNoResult<int>(
          (undoStack) {
            executionCount++;
            undoStack.push(42);
            return Future.error(CustomException('Intentional'));
          },
          undo: (undoStack, error) => {
            reason = error,
            undoCount++,
            undoValue = undoStack.pop(),
          },
          errorFilter: ErrorFilerConstant(ErrorReaction.none),
        );

        // set up all the collectors for this command.
        setupCollectors(command);

        // Ensure command is not executing already.
        expect(
          command.isRunning.value,
          false,
          reason: 'IsExecuting before true',
        );

        // Execute command.
        fakeAsync((async) {
          command.run();

          // Waiting till the async function has finished executing.
          async.elapse(const Duration(milliseconds: 100));

          expect(command.isRunning.value, false);

          expect(executionCount, 1);

          // Expected to return false, true, false
          // but somehow skips the initial state which is false.
          expect(isExecutingCollector.values, [true, false]);

          expect(canExecuteCollector.values, [false, true]);

          expect(reason, isA<CustomException>());
          expect(undoCount, 1);
          expect(undoValue, 42);
        });
      },
    );
  });

  group('Improve Code Coverage', () {
    test('Test Data class', () {
      expect(
        const CommandResult<String, String>.blank(),
        const CommandResult<String, String>(null, null, null, false),
      );
      expect(
        CommandResult<String, String>.error(
          'param',
          CustomException('Intentional'),
          ErrorReaction.none,
          null,
        ),
        CommandResult<String, String>(
          'param',
          null,
          CustomException('Intentional'),
          false,
          errorReaction: ErrorReaction.none,
        ),
      );
      expect(
        const CommandResult<String, String>.isLoading('param'),
        const CommandResult<String, String>('param', null, null, true),
      );
      expect(
        const CommandResult<String, String>.data('param', 'result'),
        const CommandResult<String, String>('param', 'result', null, false),
      );
      expect(
        const CommandResult<String, String>.data('param', 'result').toString(),
        'ParamData param - Data: result - HasError: false - IsRunning: false',
      );
      expect(
        CommandError<String>(
          paramData: 'param',
          error: CustomException('Intentional'),
        ).toString(),
        'CustomException: Intentional - from Command: Command Property not set for param: param,\nStacktrace: null',
      );

      // Test isSuccess getter
      const successResult = CommandResult<void, String>.data(null, 'success');
      expect(successResult.isSuccess, true);

      const loadingResult = CommandResult<void, String>.isLoading();
      expect(loadingResult.isSuccess, false);

      final errorResult = CommandResult<void, String>.error(
        null,
        Exception('error'),
        ErrorReaction.none,
        null,
      );
      expect(errorResult.isSuccess, false);

      // Test hasData getter
      expect(successResult.hasData, true);
      expect(loadingResult.hasData, false);

      // Test hashCode and equality with non-const instances
      // Create separate instances (not const canonicalized) with equal values
      final result1 = CommandResult<void, String>.data(null, 'test' + 'data');
      final result2 = CommandResult<void, String>.data(null, 'testdata');

      // Verify they are different objects
      expect(identical(result1, result2), false);

      // But should be equal and have same hashCode
      expect(result1 == result2, true);
      expect(result1.hashCode, result2.hashCode);

      // Test inequality with different values
      expect(result1 == loadingResult, false);

      // Test equality with all fields (paramData, data, error, isRunning)
      final error1 = Exception('test');
      final resultWithError1 = CommandResult<String, int>(
        'param',
        42,
        error1,
        false,
      );
      final resultWithError2 = CommandResult<String, int>(
        'param',
        42,
        error1, // Same error instance
        false,
      );
      expect(resultWithError1, resultWithError2);
      expect(resultWithError1.hashCode, resultWithError2.hashCode);

      // Different error should not be equal
      final resultWithError3 = CommandResult<String, int>(
        'param',
        42,
        Exception('different'),
        false,
      );
      expect(resultWithError1 == resultWithError3, false);

      // Test isLoading with no parameter
      const loadingNoParam = CommandResult<String?, String>.isLoading();
      expect(loadingNoParam.isRunning, true);
      expect(loadingNoParam.paramData, null);

      // Test CommandResult.blank()
      const blankResult = CommandResult<String?, String>.blank();
      expect(blankResult.isRunning, false);
      expect(blankResult.hasError, false);
      expect(blankResult.data, null);
      expect(blankResult.paramData, null);
    });

    test('Test CommandError equality and hashCode', () {
      // Test equality based on paramData and error
      final exception1 = Exception('test exception');
      final error1 = CommandError<String>(
        paramData: 'testParam',
        error: exception1,
        stackTrace: StackTrace.current,
        errorReaction: ErrorReaction.localHandler,
      );

      final error2 = CommandError<String>(
        paramData: 'testParam',
        error: exception1, // Same exception instance
        stackTrace: StackTrace.current,
        errorReaction: ErrorReaction.localHandler,
      );

      // Should be equal (same paramData and error)
      expect(error1 == error2, true);
      expect(error1.hashCode, equals(error2.hashCode));

      // Different error - should not be equal
      final error3 = CommandError<String>(
        paramData: 'testParam',
        error: Exception('different'),
        errorReaction: ErrorReaction.localHandler,
      );
      expect(error1 == error3, false);

      // Different paramData - should not be equal
      final error4 = CommandError<String>(
        paramData: 'differentParam',
        error: exception1,
        errorReaction: ErrorReaction.localHandler,
      );
      expect(error1 == error4, false);
    });

    test('Test CommandError toString with originalError', () {
      // Test toString with originalError (when error handler itself throws)
      final originalError = CommandError<String>(
        paramData: 'param',
        error: Exception('Original error'),
        errorReaction: ErrorReaction.localHandler,
      );

      final errorWithOriginal = CommandError<String>(
        paramData: 'param',
        error: Exception('Handler threw'),
        stackTrace: StackTrace.current,
        errorReaction: ErrorReaction.localHandler,
        originalError: originalError,
      );

      // toString should include both the handler error and original error
      final errorString = errorWithOriginal.toString();
      expect(errorString, contains('Error handler exeption'));
      expect(errorString, contains('Handler threw'));
      expect(errorString, contains('Original error'));

      // toString without originalError should have different format
      final errorWithoutOriginal = CommandError<String>(
        paramData: 'param',
        error: Exception('Simple error'),
        stackTrace: StackTrace.current,
        errorReaction: ErrorReaction.localHandler,
      );
      expect(errorWithoutOriginal.toString(),
          isNot(contains('Error handler exeption')));
      expect(errorWithoutOriginal.toString(), contains('Simple error'));
    });
    test('Test MockCommand - execute', () {
      final mockCommand = MockCommand<void, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.queueResultsForNextExecuteCall([
        const CommandResult<void, String>.data(null, 'param'),
      ]);
      mockCommand.run();

      // verify collectors
      expect(pureResultCollector.values, ['param']);
    });
    test('Test MockCommand - startExecuting', () {
      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.startExecution('Start');

      // verify collectors
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Start', null, null, true),
      ]);
      // expect(pureResultCollector.values, [initialValue: 'Initial Value']);
      // expect(isExecutingCollector.values, [true, false]);
    });

    test('Test MockCommand - endExecutionWithData', () {
      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.endExecutionWithData('end_data');

      // verify collectors
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>(null, 'end_data', null, false),
      ]);

      // The pureresultCollector contins two values because, in the
      // initialization logic of mock command, there is a listener added to
      // commandresutls notifier which reassigns the value to the value field of
      // the notifier. Additionally in the [endExecutionWithData] there is an
      // assignment to the value which notifies the listeners. This brings the
      // results twice, when the valuenotifier is allowed to notify even if the
      // value hasn't changed.
      // Todo : Verify if this logic is valid or not.

      // expect(pureResultCollector.values, ['end_data']);
      expect(pureResultCollector.values, ['end_data', 'end_data']);
    });
    test('Test MockCommand - endExecutionNoData', () {
      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.endExecutionNoData();

      // verify collectors
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>(null, null, null, false),
      ]);
      expect(pureResultCollector.values, isNull);
      // expect(isExecutingCollector.values, [true, false]);
    });
    test('Test MockCommand - endExecutionWithError', () {
      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.endExecutionWithError('Test Mock Error');

      // verify collectors
      expect(
        mockCommand.results.value.error.toString(),
        'Exception: Test Mock Error',
      );
      expect(pureResultCollector.values, isNull);
      // expect(isExecutingCollector.values, [true, false]);
    });
    test('Test MockCommand - restriction callback', () {
      bool restrictedCallbackCalled = false;

      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial',
        restriction: ValueNotifier<bool>(true), // Restricted
        ifRestrictedRunInstead: (param) {
          restrictedCallbackCalled = true;
        },
      );

      mockCommand.run('test');

      expect(restrictedCallbackCalled, true);
      expect(mockCommand.executionCount, 0); // Should not have executed

      mockCommand.dispose();
    });

    test('Test MockCommand - includeLastResultInCommandResults with error', () {
      final mockCommand = MockCommand<void, String>(
        initialValue: 'last value',
        includeLastResultInCommandResults: true,
      );

      mockCommand.queueResultsForNextExecuteCall([
        CommandResult<void, String>.error(
          null,
          Exception('test'),
          ErrorReaction.none,
          null,
        ),
      ]);

      mockCommand.run();

      // Should include last result when error occurs
      expect(mockCommand.results.value.data, 'last value');

      mockCommand.dispose();
    });

    test('Test MockCommand - noReturnValue flag', () {
      final mockCommand = MockCommand<void, void>(
        initialValue: null,
        noReturnValue: true,
      );

      int notifyCount = 0;
      mockCommand.listen((_, __) => notifyCount++);

      mockCommand.run();

      expect(notifyCount, greaterThan(0));

      mockCommand.dispose();
    });

    test('Test MockCommand - no values queued prints message', () {
      final mockCommand = MockCommand<void, String>(
        initialValue: 'initial',
      );

      // Execute without queueing values should print message
      mockCommand.run();

      expect(mockCommand.executionCount, 1);

      mockCommand.dispose();
    });

    test('Test MockCommand - logging handler with name', () {
      final logMessages = <String?>[];
      Command.loggingHandler = (name, result) {
        logMessages.add(name);
      };

      final mockCommand = MockCommand<void, String>(
        initialValue: 'initial',
        name: 'TestMock',
      );

      mockCommand.endExecutionWithData('data');
      expect(logMessages.contains('TestMock'), true);

      logMessages.clear();
      mockCommand.endExecutionWithError('error');
      expect(logMessages.contains('TestMock'), true);

      logMessages.clear();
      mockCommand.endExecutionNoData();
      expect(logMessages.contains('TestMock'), true);

      Command.loggingHandler = null;
      mockCommand.dispose();
    });

    test('Test MockCommand - queueResultsForNextExecuteCall', () {
      final mockCommand = MockCommand<String, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      mockCommand.queueResultsForNextExecuteCall([
        const CommandResult<String, String>('Param', null, null, true),
        const CommandResult<String, String>('Param', 'Result', null, false),
      ]);
      // Ensure mock command is executable.
      expect(mockCommand.canRun.value, true);
      setupCollectors(mockCommand);

      mockCommand.run();

      // verify collectors
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Param', null, null, true),
        const CommandResult<String, String>('Param', 'Result', null, false),
      ]);
      expect(pureResultCollector.values, ['Result']);
      // expect(isExecutingCollector.values, [true, false]);
    });
  });

  group('ExecuteWithFuture Edge Cases', () {
    test('executeWithFuture called twice returns same future', () async {
      final command = Command.createAsyncNoParam<String>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return 'result';
        },
        initialValue: '',
      );

      final future1 = command.runAsync();
      final future2 = command.runAsync(); // Should return same future

      expect(identical(future1, future2), true);

      await Future<void>.delayed(const Duration(milliseconds: 150));

      command.dispose();
    });

    test('Dispose while future is pending completes it', () async {
      final command = Command.createAsyncNoParam<String?>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return 'result';
        },
        initialValue: null,
      );

      final future = command.runAsync();

      // Dispose before execution completes
      await Future<void>.delayed(const Duration(milliseconds: 50));
      command.dispose();

      // Future should complete with null after disposal
      final result = await future;
      expect(result, null);
    });
  });

  group('Command Utilities and Properties', () {
    setUp(() {
      Command.globalExceptionHandler = null;
      Command.reportAllExceptions = false;
    });

    tearDown(() {
      Command.globalExceptionHandler = null;
      Command.reportAllExceptions = false;
    });

    test('reportAllExceptions forces all errors to global handler', () async {
      Object? globalHandlerCaught;
      // ignore: unused_local_variable
      Object? localHandlerCaught;

      Command.reportAllExceptions = true;
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      final command = Command.createAsyncNoParamNoResult(
        () async {
          throw Exception('test exception');
        },
        errorFilter: const ErrorHandlerLocal(), // Should only go to local
      );

      command.errors.listen((err, _) {
        if (err != null) localHandlerCaught = err.error;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // With reportAllExceptions=true, should call global handler even with local filter
      expect(globalHandlerCaught, isA<Exception>());

      command.dispose();
    });

    test('isExecutingSync property', () async {
      final command = Command.createAsyncNoParam<String>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return 'done';
        },
        initialValue: '',
      );

      expect(command.isRunningSync.value, false);

      command.run();
      // isExecutingSync should be true immediately
      expect(command.isRunningSync.value, true);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(command.isRunningSync.value, false);

      command.dispose();
    });

    test('Deprecated thrownExceptions property', () async {
      final command = Command.createAsyncNoParamNoResult(
        () async {
          throw Exception('test error');
        },
      );

      Object? caughtError;
      // ignore: deprecated_member_use
      command.errors.listen((err, _) {
        if (err != null) caughtError = err.error;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(caughtError, isA<Exception>());

      command.dispose();
    });

    test('errorsDynamic property', () async {
      final command = Command.createAsyncNoParamNoResult(
        () async {
          throw Exception('dynamic error');
        },
      );

      Object? caughtError;
      command.errorsDynamic.listen((err, _) {
        if (err != null) caughtError = err.error;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(caughtError, isA<Exception>());

      command.dispose();
    });

    test('clearErrors() method', () async {
      final command = Command.createAsyncNoParamNoResult(
        () async {
          throw Exception('error to clear');
        },
      );

      final errorCollector = <CommandError<void>?>[];
      command.errors.listen((err, _) => errorCollector.add(err));

      // Trigger error
      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(errorCollector.last?.error, isA<Exception>());

      // Clear errors
      command.clearErrors();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Should have emitted null
      expect(errorCollector.last, null);

      command.dispose();
    });
  });

  group('Sync Command Edge Cases', () {
    test('Accessing isExecuting on sync command throws assertion', () {
      final command = Command.createSyncNoParamNoResult(() {
        // Simple action
      });

      expect(
        () => command.isRunning,
        throwsA(isA<AssertionError>()),
      );

      command.dispose();
    });

    test('Sync command with null parameter and non-nullable type', () {
      final command = Command.createSync<String, String>(
        (param) => param.toUpperCase(),
        initialValue: '',
      );

      // This should trigger the null assertion with message about null value
      expect(
        () => command.run(null),
        throwsA(isA<AssertionError>()),
      );

      command.dispose();
    });

    test('Sync command executes immediately without isExecuting state', () {
      int executionCount = 0;

      final command = Command.createSyncNoParam<int>(
        () {
          executionCount++;
          return executionCount;
        },
        initialValue: 0,
      );

      setupCollectors(command);

      // Execute
      command.run();

      // Should complete immediately
      expect(executionCount, 1);
      expect(command.value, 1);

      command.dispose();
    });
  });

  group('Chain.capture Tests', () {
    setUp(() {
      Command.globalExceptionHandler = null;
      Command.reportErrorHandlerExceptionsToGlobalHandler = true;
    });

    tearDown(() {
      Command.useChainCapture = false; // Reset to default
      Command.globalExceptionHandler = null;
    });

    test('Chain.capture enabled for no-param command (success)', () async {
      Command.useChainCapture = true;
      int executionCount = 0;

      final command = Command.createAsyncNoParam<String>(
        () async {
          executionCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'result-$executionCount';
        },
        initialValue: '',
      );

      setupCollectors(command);

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(executionCount, 1);
      expect(command.value, 'result-1');
      expect(pureResultCollector.values, ['result-1']);

      command.dispose();
    });

    test('Chain.capture enabled for no-param command (error)', () async {
      Command.useChainCapture = true;
      Object? capturedError;

      final command = Command.createAsyncNoParam<String>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw CustomException('Chain.capture error');
        },
        initialValue: '',
      );

      setupCollectors(command);
      command.errors.listen((err, _) {
        if (err != null) capturedError = err.error;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(capturedError, isA<CustomException>());
      expect((capturedError as CustomException).message, 'Chain.capture error');

      command.dispose();
    });

    test('Chain.capture enabled for command with param (success)', () async {
      Command.useChainCapture = true;
      final capturedParams = <String>[];

      final command = Command.createAsync<String, String>(
        (param) async {
          capturedParams.add(param);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'processed-$param';
        },
        initialValue: '',
      );

      setupCollectors(command);

      command.run('test1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(capturedParams, ['test1']);
      expect(command.value, 'processed-test1');
      expect(pureResultCollector.values, ['processed-test1']);

      command.dispose();
    });

    test('Chain.capture enabled for command with param (error)', () async {
      Command.useChainCapture = true;
      Object? capturedError;
      StackTrace? capturedStackTrace;

      final command = Command.createAsync<String, String>(
        (param) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw CustomException('Error for: $param');
        },
        initialValue: '',
      );

      setupCollectors(command);
      command.errors.listen((err, _) {
        if (err != null) {
          capturedError = err.error;
          capturedStackTrace = err.stackTrace;
        }
      });

      command.run('error-test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(capturedError, isA<CustomException>());
      expect(
          (capturedError as CustomException).message, 'Error for: error-test');
      expect(capturedStackTrace, isNotNull);

      command.dispose();
    });

    test('Chain.capture disabled (default behavior)', () async {
      // Verify Chain.capture is off by default
      expect(Command.useChainCapture, false);

      final command = Command.createAsyncNoParam<String>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'no-chain-capture';
        },
        initialValue: '',
      );

      setupCollectors(command);

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(command.value, 'no-chain-capture');
      expect(pureResultCollector.values, ['no-chain-capture']);

      command.dispose();
    });

    test('Chain.capture with completer already completed edge case', () async {
      Command.useChainCapture = true;
      int errorHandlerCalls = 0;

      final command = Command.createAsyncNoParam<String>(
        () async {
          // This should complete normally
          return 'completed';
        },
        initialValue: '',
      );

      command.errors.listen((err, _) {
        if (err != null) errorHandlerCalls++;
      });

      command.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(command.value, 'completed');
      expect(errorHandlerCalls, 0); // No errors expected

      command.dispose();
    });
  });
}
