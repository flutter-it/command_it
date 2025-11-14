import 'package:command_it/command_it.dart';
import 'package:test/test.dart';

// Test error types
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}

class ValidationError implements Exception {
  final String message;
  ValidationError(this.message);
}

// Test functions
Future<void> throwNetworkError() async {
  throw NetworkException('Network failed');
}

Future<void> throwTimeoutError() async {
  throw TimeoutException('Request timed out');
}

Future<void> throwValidationError() async {
  throw ValidationError('Invalid input');
}

Future<bool> throwException() async {
  throw Exception('Generic exception');
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

  group('ErrorFilterFn Basic Tests', () {
    test('Simple errorFilterFn with globalHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwNetworkError,
        errorFilterFn: (error, stackTrace) {
          if (error is NetworkException) return ErrorReaction.globalHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(globalHandlerCaught, isA<NetworkException>());
      expect(localHandlerCaught, null);
    });

    test('errorFilterFn with localHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwTimeoutError,
        errorFilterFn: (error, stackTrace) {
          if (error is TimeoutException) return ErrorReaction.localHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(localHandlerCaught, isA<CommandError<void>>());
      expect((localHandlerCaught as CommandError<void>).error,
          isA<TimeoutException>());
      expect(globalHandlerCaught, null);
    });

    test('errorFilterFn with ErrorReaction.none', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwValidationError,
        errorFilterFn: (error, stackTrace) {
          if (error is ValidationError) return ErrorReaction.none;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });

    test('errorFilterFn with throwException', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwException,
        errorFilterFn: (error, stackTrace) {
          if (error is Exception) return ErrorReaction.throwException;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      expectLater(() => testCommand.run(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(localHandlerCaught, null);
      expect(globalHandlerCaught, null);
    });
  });

  group('ErrorFilterFn Multiple Error Types', () {
    test('Handle different error types differently', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final commands = [
        Command.createAsyncNoParamNoResult(
          throwNetworkError,
          errorFilterFn: (error, stackTrace) {
            if (error is NetworkException) return ErrorReaction.globalHandler;
            if (error is TimeoutException) return ErrorReaction.localHandler;
            if (error is ValidationError) return ErrorReaction.none;
            return ErrorReaction.defaulErrorFilter;
          },
        ),
        Command.createAsyncNoParamNoResult(
          throwTimeoutError,
          errorFilterFn: (error, stackTrace) {
            if (error is NetworkException) return ErrorReaction.globalHandler;
            if (error is TimeoutException) return ErrorReaction.localHandler;
            if (error is ValidationError) return ErrorReaction.none;
            return ErrorReaction.defaulErrorFilter;
          },
        ),
      ];

      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      // Test NetworkException -> globalHandler
      commands[0].errors.listen((error, _) => localHandlerCaught = error);
      commands[0].run();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(globalHandlerCaught, isA<NetworkException>());
      expect(localHandlerCaught, null);

      // Reset
      globalHandlerCaught = null;
      localHandlerCaught = null;

      // Test TimeoutException -> localHandler
      commands[1].errors.listen((error, _) => localHandlerCaught = error);
      commands[1].run();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(localHandlerCaught, isA<CommandError<void>>());
      expect(globalHandlerCaught, null);
    });
  });

  group('ErrorFilterFn Default Delegation', () {
    test('Return defaulErrorFilter delegates to default', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      // Set default error filter to global handler
      Command.errorFilterDefault =
          const ErrorFilerConstant(ErrorReaction.globalHandler);

      final testCommand = Command.createAsyncNoParamNoResult(
        throwException,
        errorFilterFn: (error, stackTrace) {
          // Always delegate to default
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should use default (globalHandler)
      expect(globalHandlerCaught, isA<Exception>());
      expect(localHandlerCaught, null);

      // Reset default
      Command.errorFilterDefault = const ErrorHandlerGlobalIfNoLocal();
    });
  });

  group('ErrorFilterFn Assertion Tests', () {
    test('Cannot provide both errorFilter and errorFilterFn', () {
      expect(
        () => Command.createAsyncNoParamNoResult(
          throwException,
          errorFilter: const ErrorHandlerLocal(),
          errorFilterFn: (error, stackTrace) => ErrorReaction.localHandler,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ErrorFilterFn with Different Command Types', () {
    test('errorFilterFn with sync command', () {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      void syncThrow() {
        throw ValidationError('Sync validation error');
      }

      final testCommand = Command.createSyncNoParamNoResult(
        syncThrow,
        errorFilterFn: (error, stackTrace) {
          if (error is ValidationError) return ErrorReaction.localHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();

      expect(localHandlerCaught, isA<CommandError<void>>());
      expect((localHandlerCaught as CommandError<void>).error,
          isA<ValidationError>());
      expect(globalHandlerCaught, null);
    });

    test('errorFilterFn with async command with parameter', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      Future<void> asyncThrowWithParam(String param) async {
        throw NetworkException('Error for: $param');
      }

      final testCommand = Command.createAsyncNoResult<String>(
        asyncThrowWithParam,
        errorFilterFn: (error, stackTrace) {
          if (error is NetworkException) return ErrorReaction.globalHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run('test-param');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(globalHandlerCaught, isA<NetworkException>());
      expect(localHandlerCaught, null);
    });

    test('errorFilterFn with async command with return value', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      Future<String> asyncThrowWithReturn() async {
        throw TimeoutException('Async error');
      }

      final testCommand = Command.createAsyncNoParam<String>(
        asyncThrowWithReturn,
        initialValue: '',
        errorFilterFn: (error, stackTrace) {
          if (error is TimeoutException) return ErrorReaction.localHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(localHandlerCaught, isA<CommandError<void>>());
      expect((localHandlerCaught as CommandError<void>).error,
          isA<TimeoutException>());
      expect(globalHandlerCaught, null);
    });

    test('errorFilterFn with undoable command', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      Future<void> undoableAction(UndoStack<String> undoStack) async {
        undoStack.push('undo-data');
        throw ValidationError('Undoable error');
      }

      final testCommand = Command.createUndoableNoParamNoResult<String>(
        undoableAction,
        undo: (stack, reason) async {
          stack.pop();
        },
        errorFilter: null, // Must pass null when using errorFilterFn
        errorFilterFn: (error, stackTrace) {
          if (error is ValidationError) return ErrorReaction.globalHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(globalHandlerCaught, isA<ValidationError>());
      expect(localHandlerCaught, null);
    });
  });

  group('ErrorFilterFn Advanced Scenarios', () {
    test('errorFilterFn with localAndGlobalHandler', () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwNetworkError,
        errorFilterFn: (error, stackTrace) {
          if (error is NetworkException) {
            return ErrorReaction.localAndGlobalHandler;
          }
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(localHandlerCaught, isA<CommandError<void>>());
      expect(globalHandlerCaught, isA<NetworkException>());
    });

    test('errorFilterFn with firstLocalThenGlobalHandler (with local)',
        () async {
      Object? globalHandlerCaught;
      Object? localHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwTimeoutError,
        errorFilterFn: (error, stackTrace) {
          if (error is TimeoutException) {
            return ErrorReaction.firstLocalThenGlobalHandler;
          }
          return ErrorReaction.defaulErrorFilter;
        },
      );

      testCommand.errors.listen((error, _) => localHandlerCaught = error);
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should call local since it exists
      expect(localHandlerCaught, isA<CommandError<void>>());
      expect(globalHandlerCaught, null);
    });

    test('errorFilterFn with firstLocalThenGlobalHandler (no local)', () async {
      Object? globalHandlerCaught;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwTimeoutError,
        errorFilterFn: (error, stackTrace) {
          if (error is TimeoutException) {
            return ErrorReaction.firstLocalThenGlobalHandler;
          }
          return ErrorReaction.defaulErrorFilter;
        },
      );

      // No local listener
      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should call global since no local exists
      expect(globalHandlerCaught, isA<TimeoutException>());
    });

    test('errorFilterFn examines stack trace', () async {
      Object? globalHandlerCaught;
      String? capturedStackTrace;

      final testCommand = Command.createAsyncNoParamNoResult(
        throwNetworkError,
        errorFilterFn: (error, stackTrace) {
          capturedStackTrace = stackTrace.toString();
          return ErrorReaction.globalHandler;
        },
      );

      Command.globalExceptionHandler =
          (error, _) => globalHandlerCaught = error.error;

      testCommand.run();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(globalHandlerCaught, isA<NetworkException>());
      expect(capturedStackTrace, isNotNull);
      expect(capturedStackTrace, contains('throwNetworkError'));
    });
  });

  group('ErrorFilterFn with MockCommand', () {
    test('MockCommand with errorFilterFn', () {
      Object? localHandlerCaught;

      final mockCommand = MockCommand<void, String>(
        initialValue: '',
        noParamValue: true,
        errorFilterFn: (error, stackTrace) {
          if (error is Exception) return ErrorReaction.localHandler;
          return ErrorReaction.defaulErrorFilter;
        },
      );

      mockCommand.errors.listen((error, _) => localHandlerCaught = error);
      mockCommand.endExecutionWithError('Mock error');

      expect(localHandlerCaught, isA<CommandError<void>>());
    });
  });
}
