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
    command.canExecute.listen((b, _) {
      canExecuteCollector(b);
      if (enablePrint) {
        print('Can Execute $b');
      }
    });
    // Setup is Executing listener only for async commands.
    if (command is CommandAsync) {
      command.isExecuting.listen((b, _) {
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

      expect(command.canExecute.value, true);

      // Setup collectors for the command.
      setupCollectors(command);

      command.execute();

      expect(command.canExecute.value, true);
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
        ifRestrictedExecuteInstead: () {
          insteadCalledCount++;
        },
      );

      expect(command.canExecute.value, true);

      // Setup Collectors
      setupCollectors(command);

      command.execute();

      expect(executionCount, 1);
      expect(insteadCalledCount, 0);

      expect(command.canExecute.value, true);

      restriction.value = true;

      expect(command.canExecute.value, false);

      command.execute();

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
          ifRestrictedExecuteInstead: (param) {
            insteadCalledParam = param;
          },
        );

        expect(command.canExecute.value, true);

        // Setup Collectors
        setupCollectors(command);

        command.execute(42);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(executionCount, 1);
        expect(insteadCalledParam, null);

        expect(command.canExecute.value, true);

        restriction.value = true;

        expect(command.canExecute.value, false);

        command.execute(42);
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

      expect(command.canExecute.value, true);
      expect(command.errors.value, null);

      command.execute();
      expect(command.results.value.error, isA<CustomException>());
      expect(command.errors.value!.error, isA<CustomException>());

      expect(command.canExecute.value, true);

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

      expect(command.canExecute.value, true);

      command.execute('Parameter');
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canExecute.value, true);

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

      expect(command.canExecute.value, true);
      // Setup Collectors
      setupCollectors(command);
      command.execute();

      expect(command.value, '4711');
      expect(
        command.results.value,
        const CommandResult<void, String>(null, '4711', null, false),
      );
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canExecute.value, true);

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

      expect(command.canExecute.value, true);
      // Setup Collectors
      setupCollectors(command);
      command.execute('4711');
      expect(command.value, '47114711');

      expect(
        command.results.value,
        const CommandResult<String, String>('4711', '47114711', null, false),
      );
      expect(command.errors.value, null);
      expect(executionCount, 1);

      expect(command.canExecute.value, true);

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

        expect(command.canExecute.value, true);
        // Setup Collectors
        setupCollectors(command);
        command.execute(null);
        expect(command.value, null);

        expect(
          command.results.value,
          const CommandResult<String?, String?>(null, null, null, false),
        );

        expect(command.errors.value, null);
        expect(executionCount, 1);

        expect(command.canExecute.value, true);

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

      expect(command.canExecute.value, true);
      // Setup Collectors
      setupCollectors(command);
      expect(() => command.execute(null), throwsA(isA<AssertionError>()));
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
        command.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      // Execute command.
      fakeAsync((async) {
        command.execute();

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isExecuting.value, false);

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
    //   command.execute('Done');

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
        command.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // Execute command.
        command.execute();

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isExecuting.value, false);

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
        command.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // Execute command.
        command.execute('Done');

        // Waiting till the async function has finished executing.
        async.elapse(const Duration(milliseconds: 10));

        expect(command.isExecuting.value, false);

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
          command.isExecuting.value,
          false,
          reason: 'IsExecuting before true',
        );

        fakeAsync((async) {
          command.execute('Done');

          // Waiting till the async function has finished executing.
          async.elapse(const Duration(milliseconds: 10));

          expect(command.isExecuting.value, false);

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
        command.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      expect(command.value, 'Initial Value');

      command.execute('Done');
      command.execute('Done2'); // should not execute

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(command.isExecuting.value, false);
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
        command.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      command.execute('Done');

      // Reuse the same command after 50 milliseconds and it should work.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      command.execute('Done2');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(command.isExecuting.value, false);
      expect(executionCount, 2);

      // Verify all the necessary collectors
      expect(canExecuteCollector.values, [
        false,
        true,
        false,
        true,
      ], reason: 'CanExecute order is wrong');
      expect(isExecutingCollector.values, [
        true,
        false,
        true,
        false,
      ], reason: 'IsExecuting order is wrong.');
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
          command.isExecuting.value,
          false,
          reason: 'IsExecuting before true',
        );

        command.execute('Done');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        command('Done2');

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(command.isExecuting.value, false);
        expect(executionCount, 2);

        // Verify all the necessary collectors
        expect(canExecuteCollector.values, [
          false,
          true,
          false,
          true,
        ], reason: 'CanExecute order is wrong');
        expect(isExecutingCollector.values, [
          true,
          false,
          true,
          false,
        ], reason: 'IsExecuting order is wrong.');
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

        expect(command.canExecute.value, true);
        expect(command.isExecuting.value, false);

        expect(command.errors.value, isNull);
        fakeAsync((async) {
          command.execute('Done');

          async.elapse(Duration.zero);

          expect(command.canExecute.value, true);
          expect(command.isExecuting.value, false);

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
      final commandFuture = command.executeWithFuture('Done');
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
          commandForNotificationTest.isExecuting.value,
          false,
          reason: 'IsExecuting before true',
        );

        fakeAsync((async) {
          // First execution
          commandForNotificationTest.execute('Done');
          async.elapse(const Duration(milliseconds: 10));
          expect(commandForNotificationTest.isExecuting.value, false);
          expect(executionCount, 1);

          // async.elapse(const Duration(milliseconds: 10));
          // Second execution
          commandForNotificationTest.execute('Done');
          async.elapse(const Duration(milliseconds: 10));
          expect(commandForNotificationTest.isExecuting.value, false);
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
        commandForNotificationTest.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );
      fakeAsync((async) {
        // First execution
        commandForNotificationTest.execute('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.execute('Done2');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
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
        commandForNotificationTest.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // First execution
        commandForNotificationTest.execute('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.execute('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
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
        commandForNotificationTest.isExecuting.value,
        false,
        reason: 'IsExecuting before true',
      );

      fakeAsync((async) {
        // First execution
        commandForNotificationTest.execute('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
        expect(executionCount, 1);

        // Second execution
        commandForNotificationTest.execute('Done');
        async.elapse(const Duration(milliseconds: 10));
        expect(commandForNotificationTest.isExecuting.value, false);
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
                whileExecuting: (_, __, ___) {
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
                whileExecuting: (_, __, ___) {
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
                    whileExecuting: (_, __) {
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
                    whileExecuting: (_, __) {
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
          undo:
              (undoStack, error) => {
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
          command.isExecuting.value,
          false,
          reason: 'IsExecuting before true',
        );

        // Execute command.
        fakeAsync((async) {
          command.execute();

          // Waiting till the async function has finished executing.
          async.elapse(const Duration(milliseconds: 100));

          expect(command.isExecuting.value, false);

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
        'ParamData param - Data: result - HasError: false - IsExecuting: false',
      );
      expect(
        CommandError<String>(
          paramData: 'param',
          error: CustomException('Intentional'),
        ).toString(),
        'CustomException: Intentional - from Command: Command Property not set for param: param,\nStacktrace: null',
      );
    });
    test('Test MockCommand - execute', () {
      final mockCommand = MockCommand<void, String>(
        initialValue: 'Initial Value',
        restriction: ValueNotifier<bool>(false),
        name: 'MockingJay',
      );
      // Ensure mock command is executable.
      expect(mockCommand.canExecute.value, true);
      setupCollectors(mockCommand);

      mockCommand.queueResultsForNextExecuteCall([
        const CommandResult<void, String>.data(null, 'param'),
      ]);
      mockCommand.execute();

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
      expect(mockCommand.canExecute.value, true);
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
      expect(mockCommand.canExecute.value, true);
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
      expect(mockCommand.canExecute.value, true);
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
      expect(mockCommand.canExecute.value, true);
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
      expect(mockCommand.canExecute.value, true);
      setupCollectors(mockCommand);

      mockCommand.execute();

      // verify collectors
      expect(cmdResultCollector.values, [
        const CommandResult<String, String>('Param', null, null, true),
        const CommandResult<String, String>('Param', 'Result', null, false),
      ]);
      expect(pureResultCollector.values, ['Result']);
      // expect(isExecutingCollector.values, [true, false]);
    });
  });
}
