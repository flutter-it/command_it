import 'dart:async';

import 'package:command_it/command_it.dart';
import 'package:test/test.dart';

enum TestType { error, exception, assertion }

Future<void> asyncFunction1(TestType testType) async {
  switch (testType) {
    case TestType.error:
      await asyncFunctionError();
      break;
    case TestType.exception:
      await asyncFunctionExeption();
      break;
    case TestType.assertion:
      await asyncFunctionAssertion();
      break;
  }
}

Future<void> asyncFunctionError() async {
  throw Error();
}

Future<void> asyncFunctionExeption() async {
  throw Exception('Exception');
}

Future<bool> asyncFunctionBoolExeption() async {
  throw Exception('Exception');
}

Future<void> asyncFunctionAssertion() async {
  assert(false, 'assertion');

  await Future<void>.delayed(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    // Reset global state before each test
    Command.globalExceptionHandler = null;
    Command.reportErrorHandlerExceptionsToGlobalHandler = true;
    // ignore: deprecated_member_use_from_same_package
    Command.debugErrorsThrowAlways = false;
  });

  tearDown(() {
    // Clean up global state after each test
    Command.globalExceptionHandler = null;
    // ignore: deprecated_member_use_from_same_package
    Command.debugErrorsThrowAlways = false;
  });

  group('ErrorFilterTests', () {
    test('PredicateFilterTest', () {
      final filter = PredicatesErrorFilter([
        (error, stacktrace) => errorFilter<Error>(error, ErrorReaction.none),
        (error, stacktrace) => errorFilter<Exception>(
              error,
              ErrorReaction.firstLocalThenGlobalHandler,
            ),
      ]);

      expect(filter.filter(Error(), StackTrace.current), ErrorReaction.none);
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.firstLocalThenGlobalHandler,
      );
      expect(
        filter.filter('this is not in the filer', StackTrace.current),
        ErrorReaction.defaulErrorFilter,
      );
    });
    test('ExemptionFilterTest', () {
      final filter = ErrorFilterExcemption<Error>(ErrorReaction.none);

      expect(filter.filter(Error(), StackTrace.current), ErrorReaction.none);
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.defaulErrorFilter,
      );
      expect(
        filter.filter('this is not in the filer', StackTrace.current),
        ErrorReaction.defaulErrorFilter,
      );
    });
    test('ErrorFilerConstant', () {
      const filter = ErrorFilerConstant(ErrorReaction.localHandler);

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.localHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.localHandler,
      );
      expect(
        filter.filter('any error', StackTrace.current),
        ErrorReaction.localHandler,
      );
    });
    test('ErrorHandlerGlobalIfNoLocal', () {
      const filter = ErrorHandlerGlobalIfNoLocal();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.firstLocalThenGlobalHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.firstLocalThenGlobalHandler,
      );
    });
    test('ErrorHandlerLocal', () {
      const filter = ErrorHandlerLocal();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.localHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.localHandler,
      );
    });
    test('ErrorHandlerLocalAndGlobal', () {
      const filter = ErrorHandlerLocalAndGlobal();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.localAndGlobalHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.localAndGlobalHandler,
      );
    });

    // Tests for new ErrorFilter classes
    test('GlobalIfNoLocalErrorFilter', () {
      const filter = GlobalIfNoLocalErrorFilter();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.firstLocalThenGlobalHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.firstLocalThenGlobalHandler,
      );
    });

    test('GlobalErrorFilter', () {
      const filter = GlobalErrorFilter();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.globalHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.globalHandler,
      );
    });

    test('LocalErrorFilter', () {
      const filter = LocalErrorFilter();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.localHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.localHandler,
      );
    });

    test('LocalAndGlobalErrorFilter', () {
      const filter = LocalAndGlobalErrorFilter();

      expect(
        filter.filter(Error(), StackTrace.current),
        ErrorReaction.localAndGlobalHandler,
      );
      expect(
        filter.filter(Exception(), StackTrace.current),
        ErrorReaction.localAndGlobalHandler,
      );
    });
  });
  group('ErrorRection.none', () {
    test(
      'throws an assertion although there is a filter for it (as intended))',
      () async {
        Object? globalHandlerCaught;
        Object? localHandlerCaught;

        final testCommand = Command.createAsyncNoParamNoResult(
          () => asyncFunction1(TestType.assertion),
          errorFilter: PredicatesErrorFilter([
            (error, stacktrace) =>
                errorFilter<AssertionError>(error, ErrorReaction.none),
          ]),
        );
        testCommand.errors.listen((error, _) => localHandlerCaught = error);
        Command.globalExceptionHandler =
            (error, _) => globalHandlerCaught = error.error;

        expectLater(
          () => testCommand.run(),
          throwsA(isA<AssertionError>()),
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(localHandlerCaught, null);
        expect(globalHandlerCaught, null);
      },
    );
    test('Assertion is handled like any other error', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      Command.assertionsAlwaysThrow = false;
      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.assertion),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<AssertionError>(error, ErrorReaction.none),
        ]),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });

    test('throws an Error - ErrorReaction.none', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.error),
        errorFilter: const TableErrorFilter({Error: ErrorReaction.none}),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });

    test('throws exception - ErrorReaction.none', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: const TableErrorFilter({Exception: ErrorReaction.none}),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
  });
  group('different filters -', () {
    test('throwExection', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.throwException),
        ]),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
    test('globalHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.globalHandler),
        ]),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, isA<Exception>());
    });
    test('localHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.localHandler),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('localAndGlobalHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.localAndGlobalHandler,
              ),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, isA<Exception>());
    });
    test('globalIfNoLocalHandler no local handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.firstLocalThenGlobalHandler,
              ),
        ]),
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, isA<Exception>());
    });
    test('globalIfNoLocalHandler - local handler @errors', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.firstLocalThenGlobalHandler,
              ),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('globalIfNoLocalHandler - local handler @results ', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParam<bool>(
        () => asyncFunctionBoolExeption(),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.firstLocalThenGlobalHandler,
              ),
        ]),
        initialValue: true,
      );
      testCommand.results.listen((result, _) {
        if (result.hasError) {
          localHandlerCaught = result.error;
        }
      });
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('globalIfNoLocalHandler - no handler', () async {
      Command.globalExceptionHandler = null;
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.firstLocalThenGlobalHandler,
              ),
        ]),
      );
      expectLater(() => testCommand.run(), throwsA(isA<AssertionError>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
    test('noHandlersThrowException no handler', () async {
      Command.globalExceptionHandler = null;
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.noHandlersThrowException,
              ),
        ]),
      );
      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
    test('noHandlersThrowException - local handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.noHandlersThrowException,
              ),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('noHandlersThrowException - global handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.noHandlersThrowException,
              ),
        ]),
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };
      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, isA<Exception>());
    });
    test('noHandlersThrowException - both handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.noHandlersThrowException,
              ),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };
      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('throwIfNoLocalHandler - local handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.throwIfNoLocalHandler,
              ),
        ]),
      );
      testCommand.errors.listen(
        (error, _) => localHandlerCaught = error?.error,
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };
      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, isA<Exception>());
      expect(globalHandlerCaught, null);
    });
    test('throwIfNoLocalHandler - no local handler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) => errorFilter<Exception>(
                error,
                ErrorReaction.throwIfNoLocalHandler,
              ),
        ]),
      );
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };
      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
  });
  group('force throw', () {
    test('throws exception', () async {
      // ignore: deprecated_member_use_from_same_package
      Command.debugErrorsThrowAlways = true;
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.none),
        ]),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
    test('throws exception global handler', () async {
      // ignore: deprecated_member_use_from_same_package
      Command.debugErrorsThrowAlways = true;
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.globalHandler),
        ]),
      );
      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
    test('localHandler throws', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        () => asyncFunction1(TestType.exception),
        errorFilter: PredicatesErrorFilter([
          (error, stacktrace) =>
              errorFilter<Exception>(error, ErrorReaction.localHandler),
        ]),
      );
      testCommand.errors.listen((error, _) {
        throw StateError('local handler throws');
      });
      Command.globalExceptionHandler = (error, _) {
        globalHandlerCaught = error.error;
      };

      testCommand.run();
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, isA<StateError>());
    });

    test('ErrorHandlerLocalAndGlobal constructor', () {
      // Test that the constructor works and filter returns correct reaction
      const filter = ErrorHandlerLocalAndGlobal();
      final reaction = filter.filter(Exception('test'), StackTrace.current);
      expect(reaction, ErrorReaction.localAndGlobalHandler);
    });

    test('TableErrorFilter constructor', () {
      // Test that the constructor works and filter returns correct reaction
      const filter = TableErrorFilter({
        Exception: ErrorReaction.localHandler,
        StateError: ErrorReaction.globalHandler,
      });
      expect(filter, isNotNull);
      expect(filter.filter(Exception('test'), StackTrace.current),
          ErrorReaction.localHandler);
    });
  });

  group('Global errors stream', () {
    late List<CommandError<dynamic>> errors;
    late StreamSubscription<CommandError<dynamic>> subscription;

    setUp(() {
      errors = <CommandError<dynamic>>[];
      subscription = Command.globalErrors.listen((e) => errors.add(e));
      // Set a global handler so assertions don't fail
      Command.globalExceptionHandler = (_, __) {};
    });

    tearDown(() async {
      await subscription.cancel();
      errors.clear();
      Command.globalExceptionHandler = null;
    });

    test('Stream emits when ErrorFilter routes to global', () async {
      final cmd = Command.createAsyncNoParam(
        () async => throw Exception('Test error'),
        initialValue: null,
        errorFilter: const GlobalIfNoLocalErrorFilter(),
      );

      await cmd.runAsync().catchError((_) {});

      expect(errors, hasLength(1));
      expect(errors.first.error.toString(), contains('Test error'));
      expect(errors.first.command, equals(cmd));
      expect(errors.first.stackTrace, isNotNull);
    });

    test('Stream does NOT emit for reportAllExceptions', () async {
      Command.reportAllExceptions = true;

      final cmd = Command.createAsyncNoParam(
        () async => throw Exception('Debug error'),
        initialValue: null,
        errorFilter: const LocalErrorFilter(),
      );
      cmd.errors.listen((_, __) {}); // Add local listener

      await cmd.runAsync().catchError((_) {});

      expect(errors, isEmpty); // Should NOT emit to stream

      Command.reportAllExceptions = false;
    });

    test('Stream emits when error handler throws', () async {
      Command.reportErrorHandlerExceptionsToGlobalHandler = true;

      final cmd = Command.createAsyncNoParam(
        () async => throw Exception('Original error'),
        initialValue: null,
      );

      // Error handler that throws
      cmd.errors.listen((error, _) {
        if (error != null) {
          throw Exception('Error handler bug!');
        }
      });

      await cmd.runAsync().catchError((_) {});

      expect(errors, hasLength(1));
      expect(errors.first.error.toString(), contains('Error handler bug'));
      expect(errors.first.originalError, isNotNull);
    });

    test('Stream only emits for global routing, not local', () async {
      // Local filter - should NOT emit
      final localCmd = Command.createAsyncNoParam(
        () async => throw Exception('Local error'),
        initialValue: null,
        errorFilter: const LocalErrorFilter(),
      );
      localCmd.errors.listen((_, __) {});

      await localCmd.runAsync().catchError((_) {});
      expect(errors, isEmpty);

      // Global filter - SHOULD emit
      final globalCmd = Command.createAsyncNoParam(
        () async => throw Exception('Global error'),
        initialValue: null,
        errorFilter: const GlobalIfNoLocalErrorFilter(),
      );

      await globalCmd.runAsync().catchError((_) {});
      expect(errors, hasLength(1));
      expect(errors.first.error.toString(), contains('Global error'));
    });
  });
}
