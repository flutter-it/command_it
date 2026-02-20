// ignore_for_file: avoid_positional_boolean_parameters, deprecated_member_use_from_same_package
library command_it;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:listen_it/listen_it.dart';
import 'package:quiver/core.dart';
import 'package:stack_trace/stack_trace.dart';

import 'error_filters.dart';

export 'package:command_it/error_filters.dart';
export 'package:listen_it/listen_it.dart';

part './async_command.dart';
part './command_builder.dart';
part './mock_command.dart';
part './progress_handle.dart';
part './sync_command.dart';
part './undoable_command.dart';

/// Combined execution state of a `Command` represented using four of its fields.
/// A [CommandResult] will be issued for any state change of any of its fields
/// During normal command execution you will get this items by listening at the command's [.results] ValueListenable.
/// 1. If the command was just newly created you will get `param data, null, null, false` (paramData, data, error, isRunning)
/// 2. When calling run: `param data, null, null, true`
/// 3. When execution finishes: `param data, the result, null, false`
/// `param data` is the data that you pass as parameter when calling the command
class CommandResult<TParam, TResult> {
  final TParam? paramData;
  final TResult? data;
  final bool isUndoValue;
  final Object? error;
  final bool isRunning;
  final ErrorReaction? errorReaction;
  final StackTrace? stackTrace;

  const CommandResult(
    this.paramData,
    this.data,
    this.error,
    this.isRunning, {
    this.errorReaction,
    this.stackTrace,
    this.isUndoValue = false,
  });

  const CommandResult.data(TParam? param, TResult data)
      : this(param, data, null, false);

  const CommandResult.error(
    TParam? param,
    dynamic error,
    ErrorReaction errorReaction,
    StackTrace? stackTrace,
  ) : this(
          param,
          null,
          error,
          false,
          errorReaction: errorReaction,
          stackTrace: stackTrace,
        );

  const CommandResult.isLoading([TParam? param])
      : this(param, null, null, true);

  const CommandResult.blank() : this(null, null, null, false);

  /// if a CommandResult is not running and has no error, it is considered successful
  /// if the command has no return value, this can be used to check if the command was executed successfully
  bool get isSuccess => !isRunning && !hasError;
  bool get hasData => data != null;

  bool get hasError => error != null && !isUndoValue;

  /// Deprecated: Use [isRunning] instead.
  /// This getter will be removed in v10.0.0.
  @Deprecated(
    'Use isRunning instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  bool get isExecuting => isRunning;

  @override
  bool operator ==(Object other) =>
      other is CommandResult<TParam, TResult> &&
      other.paramData == paramData &&
      other.data == data &&
      other.error == error &&
      other.isRunning == isRunning;

  @override
  int get hashCode => hash4(
        data.hashCode,
        error.hashCode,
        isRunning.hashCode,
        paramData.hashCode,
      );

  @override
  String toString() {
    return 'ParamData $paramData - Data: $data - HasError: $hasError - IsRunning: $isRunning';
  }
}

/// [CommandError] wraps an occurring error together with the argument that was
/// passed when the command was called.
/// This sort of objects are emitted on the `.errors` ValueListenable
/// of the Command
class CommandError<TParam> {
  final Object error;
  final TParam? paramData;
  String? get commandName => command?.name ?? 'Command Property not set';
  final Command<TParam, dynamic>? command;
  final StackTrace? stackTrace;

  /// if nuill, the error was not filtered by an ErrorFilter which means either send to the global handler
  /// because of [Command.reportAllExceptions] or the default error filter of the Command class
  final ErrorReaction? errorReaction;

  /// in case that an error handler throws an error, we will call the global exception handler
  /// with this error
  /// this will hold the original error that called the error handler that threw error
  final CommandError<TParam>? originalError;

  CommandError({
    this.command,
    this.errorReaction,
    this.paramData,
    required this.error,
    this.stackTrace,
    this.originalError,
  });

  @override
  bool operator ==(Object other) =>
      other is CommandError<TParam> &&
      other.paramData == paramData &&
      other.error == error;

  @override
  int get hashCode => hash2(error.hashCode, paramData.hashCode);

  @override
  String toString() {
    if (originalError != null) {
      return 'Error handler exeption: Error handler of Command: $commandName for param: $paramData,\n'
          'threw $error,\n Stacktrace: $stackTrace\n Original error: ${originalError!}\n';
    } else {
      return '$error - from Command: $commandName for param: $paramData,\n'
          'Stacktrace: $stackTrace';
    }
  }
}

typedef RunInsteadHandler<TParam> = void Function(TParam?);

/// Deprecated: Use [RunInsteadHandler] instead.
@Deprecated(
  'Use RunInsteadHandler instead. '
  'This will be removed in v10.0.0. '
  'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
)
typedef ExecuteInsteadHandler<TParam> = RunInsteadHandler<TParam>;

/// Function-based error filter for simple inline error handling logic.
///
/// Returns the [ErrorReaction] to use for the given error, or [ErrorReaction.defaulErrorFilter]
/// to use the default error handling behavior.
///
/// Example:
/// ```dart
/// errorFilterFn: (error, stackTrace) {
///   if (error is NetworkException) return ErrorReaction.globalHandler;
///   if (error is TimeoutException) return ErrorReaction.localHandler;
///   return ErrorReaction.defaulErrorFilter; // Use default for other errors
/// }
/// ```
///
/// For complex or reusable error handling logic, use [ErrorFilter] objects instead.
typedef ErrorFilterFn = ErrorReaction Function(
  Object error,
  StackTrace stackTrace,
);

/// [Command] capsules a given handler function that can then be run by its [run] method.
/// The result of this method is then published through its `ValueListenable` interface
/// Additionally it offers other `ValueListenables` for it's current execution state,
/// if the command can be run and for all possibly thrown exceptions during command execution.
///
/// [Command] implements the `ValueListenable` interface so you can register notification handlers
///  directly to the [Command] which emits the results of the wrapped function.
/// If this function has a [void] return type registered handler will still be called
///  so that you can listen for the end of the execution.
///
/// The [results] `ValueListenable` emits [CommandResult<TResult>] which is often easier in combination
/// with Flutter `ValueListenableBuilder`  because you have all state information at one place.
///
/// An [Command] is a generic class of type [Command<TParam, TResult>]
/// where [TParam] is the type of data that is passed when calling [run] and
/// [TResult] denotes the return type of the handler function. To signal that
/// a handler doesn't take a parameter or returns no value use the type `void`
abstract class Command<TParam, TResult> extends CustomValueNotifier<TResult> {
  Command({
    required TResult initialValue,
    required ValueListenable<bool>? restriction,
    required RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    required ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    required bool includeLastResultInCommandResults,
    required bool noReturnValue,
    required bool notifyOnlyWhenValueChanges,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    required String? name,
    required bool noParamValue,
  })  : assert(
          !(errorFilter != null && errorFilterFn != null),
          'Cannot provide both errorFilter and errorFilterFn. Use one or the other.',
        ),
        assert(
          !(ifRestrictedRunInstead != null &&
              ifRestrictedExecuteInstead != null),
          'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
        ),
        _restriction = restriction,
        _ifRestrictedRunInstead =
            ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
        _noReturnValue = noReturnValue,
        _noParamValue = noParamValue,
        _includeLastResultInCommandResults = includeLastResultInCommandResults,
        _errorFilter = errorFilter ?? errorFilterDefault,
        _errorFilterFn = errorFilterFn,
        _name = name,
        super(
          initialValue,
          mode: notifyOnlyWhenValueChanges
              ? CustomNotifierMode.normal
              : CustomNotifierMode.always,
        ) {
    _commandResult = CustomValueNotifier<CommandResult<TParam?, TResult>>(
      CommandResult.data(null, initialValue),
    );

    /// forward error states to the `errors` Listenable
    _commandResult
        .where((x) => x.hasError && x.errorReaction!.shouldCallLocalHandler)
        .listen((x, _) {
      final originalError = CommandError<TParam>(
        paramData: x.paramData,
        error: x.error!,
        command: this,
        errorReaction: x.errorReaction!,
        stackTrace: x.stackTrace,
      );
      _errors.value = originalError;
      _errors.notifyListeners(
        reportErrorHandlerExceptionsToGlobalHandler
            ? (error, stackTrace) => {
                  _internalGlobalErrorHandler(
                    CommandError<TParam>(
                      error: error,
                      command: this,
                      originalError: originalError,
                      errorReaction: ErrorReaction.none,
                    ),
                    stackTrace,
                  ),
                }
            : null,
      );
    });

    // /// forward busy states to the `isExecuting` Listenable
    // _commandResult.listen((x, _) => _isRunning.value = x.isExecuting);

    /// Merge the external execution restricting with the internal
    /// isExecuting which also blocks execution if true
    _canRun = (_restriction == null)
        ? _isRunning.map((val) => !val)
        : _restriction.combineLatest<bool, bool>(
            _isRunning,
            (restriction, isExecuting) => !restriction && !isExecuting,
          );

    /// decouple the async isExecuting from the sync isExecuting
    /// so that _canRun will update immediately
    _isRunning.listen((busy, _) {
      _isRunningAsync.value = busy;
    });
  }

  /// Runs the wrapped function with optional [param].
  ///
  /// If [restriction] is true (command disabled), execution is skipped and
  /// [ifRestrictedRunInstead] is called instead (if provided).
  ///
  /// For async commands, sets [isRunning] to true, updates [results] during execution,
  /// and sets [isRunning] to false when complete. Sync commands execute immediately
  /// without [isRunning] updates (accessing [isRunning] on sync commands throws).
  ///
  /// Errors are routed according to [errorFilter] configuration (see [ErrorReaction]).
  /// Use [runAsync] if you need an awaitable result.
  void run([TParam? param]) async {
    // its valid to dispose a command anytime, so we have to make sure this
    // doesn't create an invalid state
    if (_isDisposing) {
      return;
    }
    if (Command.detailedStackTraces) {
      _traceBeforeExecute = Trace.current();
    }

    if (_restriction?.value == true) {
      _ifRestrictedRunInstead?.call(param);
      return;
    }
    if (!_canRun.value) {
      return;
    }

    if (_isRunning.value) {
      return;
    } else {
      _isRunning.value = true;
    }

    _errors.value = null; // this will not trigger the listeners

    if (this is! CommandSync<TParam, TResult>) {
      _commandResult.value = CommandResult<TParam, TResult>(
        param,
        _includeLastResultInCommandResults ? value : null,
        null,
        true,
      );

      /// give the async notifications a chance to propagate
      await Future<void>.delayed(Duration.zero);
    }

    try {
      // lets play it save and check again if the command was disposed
      if (_isDisposing) {
        return;
      }
      TResult result;

      /// here we call the actual handler function
      final FutureOr = _run(param);
      if (FutureOr is Future) {
        result = await FutureOr;
      } else {
        result = FutureOr;
      }

      if (_isDisposing) {
        return;
      }

      _commandResult.value = CommandResult<TParam, TResult>(
        param,
        _noReturnValue ? null : result,
        null,
        false,
      );

      /// make sure set _isRunning to false before we notify the listeners
      /// in case the listener wants to call another command that is restricted
      /// by this isExecuting flag
      _isRunning.value = false;
      if (!_noReturnValue) {
        value = result;
      } else {
        notifyListeners();
      }
      _futureCompleter?.complete(result);
      _futureCompleter = null;
    } catch (error, stacktrace) {
      StackTrace chain = _mandatoryErrorHandling(stacktrace, error, param);

      if (this is UndoableCommand) {
        final undoAble = this as UndoableCommand;
        if (undoAble._undoOnExecutionFailure) {
          undoAble._undo(error);
        }
      }

      _handleErrorFiltered(param, error, chain);
    } finally {
      if (!_isDisposing) {
        _isRunning.value = false;
      }

      /// give the async notifications a chance to propagate
      await Future<void>.delayed(Duration.zero);
      if (_name != null) {
        Command.loggingHandler?.call(_name, _commandResult.value);
      }
    }
  }

  /// Deprecated: Use [run] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use run() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  void execute([TParam? param]) => run(param);

  StackTrace _mandatoryErrorHandling(
    StackTrace stacktrace,
    Object error,
    TParam? param,
  ) {
    StackTrace chain = Command.detailedStackTraces
        ? _improveStacktrace(stacktrace).terse
        : stacktrace;

    if (Command.assertionsAlwaysThrow && error is AssertionError) {
      Error.throwWithStackTrace(error, chain);
    }

    if (kDebugMode && Command.debugErrorsThrowAlways) {
      Error.throwWithStackTrace(error, chain);
    }

    if (Command.reportAllExceptions) {
      Command.globalExceptionHandler?.call(
        CommandError(
          paramData: param,
          error: error,
          command: this,
          stackTrace: chain,
        ),
        chain,
      );
    }
    return chain;
  }

  /// override this method to implement the actual command logic
  // ignore: unused_element_parameter
  FutureOr<TResult> _run([TParam? param]);

  /// This makes Command a callable class, so instead of `myCommand.run()`
  /// you can write `myCommand()`
  void call([TParam? param]) => run(param);

  final RunInsteadHandler<TParam>? _ifRestrictedRunInstead;

  /// emits [CommandResult<TResult>] the combined state of the command, which is
  /// often easier in combination with Flutter's `ValueListenableBuilder`
  /// because you have all state information at one place.
  ValueListenable<CommandResult<TParam?, TResult>> get results =>
      _commandResult;

  /// `ValueListenable<bool>` that tracks whether the command is currently running.
  ///
  /// **Use this for UI updates** (ValueListenableBuilder, watch_it, etc.)
  /// Notifications are delivered asynchronously to avoid triggering rebuilds
  /// during an ongoing build (which would throw a FlutterError).
  ///
  /// For command coordination/restrictions, use [isRunningSync] instead.
  ValueListenable<bool> get isRunning => _isRunningAsync;

  /// Deprecated: Use [isRunning] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use isRunning instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  ValueListenable<bool> get isExecuting => isRunning;

  /// `ValueListenable<bool>` that tracks whether the command is currently running.
  ///
  /// **Use this for command restrictions and chaining** - notifications are
  /// delivered synchronously (immediately) to prevent race conditions.
  ///
  /// Example: `restriction: loadCommand.isRunningSync` prevents another
  /// command from running while `loadCommand` is active.
  ///
  /// For UI updates, use [isRunning] instead (async notifications are smoother).
  ValueListenable<bool> get isRunningSync => _isRunning;

  /// Deprecated: Use [isRunningSync] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use isRunningSync instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  ValueListenable<bool> get isExecutingSync => isRunningSync;

  /// `ValueListenable<bool>` that changes its value on any change of the current
  /// executability state of the command. Meaning if the command can be run or not.
  /// This will issue `false` while the command runs, but also if the command
  /// receives a `true` from the [restriction] `ValueListenable` that you can pass when
  /// creating the Command.
  /// its value is `!restriction.value && !isRunning.value`
  ValueListenable<bool> get canRun => _canRun;

  /// Deprecated: Use [canRun] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use canRun instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  ValueListenable<bool> get canExecute => canRun;

  /// `ValueListenable<CommandError>` that reflects the Error State of the command
  /// if the wrapped function throws an error, its value is set to the error is
  /// wrapped in an `CommandError`
  ///
  @Deprecated('use errors instead')
  ValueListenable<CommandError<TParam>?> get thrownExceptions => _errors;

  /// `ValueListenable<CommandError>` that reflects the Error State of the command
  /// if the wrapped function throws an error, its value is set to the error is
  /// wrapped in an `CommandError`
  ValueListenable<CommandError<TParam>?> get errors => _errors;

  /// Same as [errors] but with a dynamic error type. This is useful if you have
  /// want to merge different error types in one listener.
  ValueListenable<CommandError<dynamic>?> get errorsDynamic => _errors;

  /// clears the error state of the command. This will trigger any listeners
  /// especially useful if you use `watch_it` to watch the errors property.
  /// However the prefered way to handle the [errors] property is either use
  /// `registerHandler` or `listen` in `initState` of a `StatefulWidget`
  void clearErrors() {
    _errors.value = null;
    if (_isDisposing) {
      return;
    }
    _errors.notifyListeners();
  }

  /// Observable progress value between 0.0 (0%) and 1.0 (100%).
  ///
  /// For commands created with `WithProgress` factories, returns the actual
  /// progress notifier from the [ProgressHandle]. For regular commands,
  /// returns a static notifier that always returns 0.0.
  ///
  /// Updated by calling [ProgressHandle.updateProgress] inside the command function.
  /// UI can observe this to show progress bars or percentage indicators.
  ///
  /// Example:
  /// ```dart
  /// // In UI
  /// watchValue((MyService s) => s.uploadCommand.progress)
  /// LinearProgressIndicator(value: command.progress.value)
  /// ```
  ValueListenable<double> get progress => _handle?.progress ?? _defaultProgress;

  /// Observable status message providing human-readable operation status.
  ///
  /// For commands created with `WithProgress` factories, returns the actual
  /// status message notifier from the [ProgressHandle]. For regular commands,
  /// returns a static notifier that always returns null.
  ///
  /// Updated by calling [ProgressHandle.updateStatusMessage] inside the command function.
  /// UI can observe this to show operation details to users.
  ///
  /// Example:
  /// ```dart
  /// // In UI
  /// watchValue((MyService s) => s.uploadCommand.statusMessage)
  /// Text(command.statusMessage.value ?? 'Ready')
  /// ```
  ValueListenable<String?> get statusMessage =>
      _handle?.statusMessage ?? _defaultStatusMessage;

  /// Observable cancellation flag.
  ///
  /// For commands created with `WithProgress` factories, returns the actual
  /// cancellation notifier from the [ProgressHandle]. For regular commands,
  /// returns a static notifier that always returns false.
  ///
  /// Set to true when [cancel] is called. The wrapped command function
  /// should check `isCanceled.value` periodically and handle cancellation
  /// cooperatively (e.g., return early, throw exception, clean up resources).
  ///
  /// Can also be observed via `.listen()` to forward cancellation to external
  /// tokens (e.g., Dio's CancelToken).
  ///
  /// Example:
  /// ```dart
  /// // In command function
  /// if (handle.isCanceled.value) return partialResult;
  ///
  /// // Or reactive forwarding
  /// handle.isCanceled.listen((canceled) {
  ///   if (canceled) dioToken.cancel();
  /// });
  /// ```
  ValueListenable<bool> get isCanceled =>
      _handle?.isCanceled ?? _defaultCanceled;

  /// Requests cooperative cancellation of the command execution.
  ///
  /// For commands created with `WithProgress` factories, sets the cancellation
  /// flag in the [ProgressHandle]. The wrapped function is responsible for
  /// checking this flag and responding appropriately.
  ///
  /// For regular commands without progress tracking, this is a no-op.
  ///
  /// This does NOT forcibly stop execution - cancellation is cooperative.
  /// The function must check `handle.isCanceled.value` and decide how to handle it.
  void cancel() => _handle?.cancel();

  /// Manually resets all progress state to initial values.
  ///
  /// Clears progress (to 0.0), statusMessage (to null), and isCanceled (to false).
  /// This is called automatically at the start of each execution, but can also
  /// be called manually when needed (e.g., to clear 100% progress from UI after
  /// completion, or to initialize a command to a specific progress value).
  ///
  /// Optional parameters allow setting specific initial values:
  /// - [progress]: Initial progress value (0.0-1.0), defaults to 0.0
  /// - [statusMessage]: Initial status message, defaults to null
  ///
  /// Example:
  /// ```dart
  /// // Reset to default (0.0, null)
  /// command.resetProgress();
  ///
  /// // Initialize to 50% with a message
  /// command.resetProgress(progress: 0.5, statusMessage: 'Resuming...');
  ///
  /// // Clear 100% progress after completion
  /// if (command.progress.value == 1.0) {
  ///   await Future.delayed(Duration(seconds: 2));
  ///   command.resetProgress();
  /// }
  /// ```
  ///
  /// For commands without progress (created with regular factories), this is a no-op.
  void resetProgress({double? progress, String? statusMessage}) =>
      _handle?.reset(progress: progress, statusMessage: statusMessage);

  /// optional hander that will get called on any exception that happens inside
  /// any Command of the app. Ideal for logging.
  /// the [name] of the Command that was responsible for the error is inside
  /// the error object.
  static void Function(CommandError<dynamic> error, StackTrace stackTrace)?
      globalExceptionHandler;

  /// if no individual ErrorFilter is set when creating a Command
  /// this filter is used in case of an error
  static ErrorFilter errorFilterDefault = const GlobalIfNoLocalErrorFilter();

  /// `AssertionErrors` are almost never wanted in production, so by default
  /// they will dirextly be rethrown, so that they are found early in development
  /// In case you want them to be handled like any other error, meaning
  /// an ErrorFilter will decide what should happen, set this to false.
  static bool assertionsAlwaysThrow = true;

  // if the function that is wrapped by the command throws an exception, it's
  // it's sometime s not easy to understand where the execption originated,
  // Escpecially if you used an Errrorfilter that swallows possible exceptions.
  // by setting this to true, the Command will directly rethrow any exception
  // so that you can get a helpfult stacktrace.
  // works only in debug mode
  @Deprecated(
    'use reportAllExeceptions instead, it turned out that throwing does not help as much as expected',
  )
  static bool debugErrorsThrowAlways = false;

  /// overrides any ErrorFilter that is set for a Command and will call the global exception handler
  /// for any error that occurs in any Command of the app.
  /// Together with the [detailledStackTraces] this gives detailed information what's going on in the app
  static bool reportAllExceptions = false;

  /// Will capture detailed stacktraces for any Command execution. If this has negative impact on performance
  /// you can set this to false. This is a global setting for all Commands in the app.
  static bool detailedStackTraces = true;

  /// experimental if enabled you will get a detailed stacktrace of the origin of the exception
  /// inside the wrapped function.
  static bool useChainCapture = false;

  /// if a local error handler is present and that handler throws an exception
  /// this flag will decide if the global exception handler will be called with
  /// the error of the error handler. In that casse the original error is stored
  /// in the `originalError` property of the CommandError.
  /// If set to false such errors will only by the Flutter error logger
  static bool reportErrorHandlerExceptionsToGlobalHandler = true;

  /// optional handler that will get called on all `Command` executions if the Command
  /// has a set a name.
  /// [commandName] the [name] of the Command
  static void Function(
    String? commandName,
    CommandResult<dynamic, dynamic> result,
  )? loggingHandler;

  static final StreamController<CommandError<dynamic>> _globalErrorStream =
      StreamController<CommandError<dynamic>>.broadcast();

  /// Stream of all command errors across the entire application.
  /// Emits whenever any command encounters an error that would trigger
  /// the [globalExceptionHandler] (based on ErrorFilter routing).
  ///
  /// Does NOT emit errors from [reportAllExceptions] (debug-only).
  ///
  /// Useful for:
  /// - Centralized logging
  /// - Analytics/monitoring
  /// - Crash reporting
  /// - UI notifications (error toasts via watch_it's registerStreamHandler)
  ///
  /// Example with watch_it integration:
  /// ```dart
  /// class MyApp extends WatchingWidget {
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     registerStreamHandler<Stream<CommandError>, CommandError>(
  ///       target: Command.globalErrors,
  ///       handler: (context, snapshot, cancel) {
  ///         if (snapshot.hasData) {
  ///           final error = snapshot.data!;
  ///           ScaffoldMessenger.of(context).showSnackBar(
  ///             SnackBar(content: Text('Error: ${error.error}')),
  ///           );
  ///         }
  ///       },
  ///     );
  ///     return MaterialApp(...);
  ///   }
  /// }
  /// ```
  static Stream<CommandError<dynamic>> get globalErrors =>
      _globalErrorStream.stream;

  /// Internal handler that emits to stream and calls public globalExceptionHandler.
  /// Used for errors that should be globally handled (not debug-only).
  static void _internalGlobalErrorHandler(
    CommandError<dynamic> error,
    StackTrace stackTrace,
  ) {
    _globalErrorStream.add(error);
    globalExceptionHandler?.call(error, stackTrace);
  }

  /// Default progress notifier returned for commands without ProgressHandle.
  /// Always returns 0.0 and never changes.
  static final CustomValueNotifier<double> _defaultProgress =
      CustomValueNotifier<double>(0.0);

  /// Default status message notifier returned for commands without ProgressHandle.
  /// Always returns null and never changes.
  static final CustomValueNotifier<String?> _defaultStatusMessage =
      CustomValueNotifier<String?>(null);

  /// Default cancellation notifier returned for commands without ProgressHandle.
  /// Always returns false and never changes.
  static final CustomValueNotifier<bool> _defaultCanceled =
      CustomValueNotifier<bool>(false);

  /// as we don't want that anyone changes the values of these ValueNotifiers
  /// properties we make them private and only publish their `ValueListenable`
  /// interface via getters.
  late CustomValueNotifier<CommandResult<TParam?, TResult>> _commandResult;
  final CustomValueNotifier<bool> _isRunningAsync = CustomValueNotifier<bool>(
    false,
    asyncNotification: true,
  );
  final CustomValueNotifier<bool> _isRunning = CustomValueNotifier<bool>(
    false,
  );
  late ValueListenable<bool> _canRun;
  late final ValueListenable<bool>? _restriction;
  final CustomValueNotifier<CommandError<TParam>?> _errors =
      CustomValueNotifier<CommandError<TParam>?>(
    null,
    mode: CustomNotifierMode.manual,
  );

  /// Optional progress handle for commands created with WithProgress factories.
  /// Null for commands without progress tracking.
  ProgressHandle? _handle;

  /// If you don't need a command any longer it is a good practise to
  /// dispose it to make sure all registered notification handlers are remove to
  /// prevent memory leaks
  @override
  void dispose() {
    assert(
      !_isDisposing,
      'You are trying to dispose a Command that was already disposed. This is not allowed.',
    );
    _isDisposing = true;

    /// ensure that all ValueNotifiers have finished their async notifications
    /// before we dispose them with a delay of 50ms otherwise if any listener of any of the
    /// ValueNotifiers would dispose the command itself, we would get an exception
    Future<void>.delayed(Duration(milliseconds: 50), () {
      _commandResult.dispose();
      // _canRun is created by listen_it operators which return disposable ValueListenables
      if (_canRun is ChangeNotifier) {
        (_canRun as ChangeNotifier).dispose();
      }
      _isRunning.dispose();
      _isRunningAsync.dispose();
      _errors.dispose();
      _handle?.dispose();
      if (!(_futureCompleter?.isCompleted ?? true)) {
        _futureCompleter!.complete(null);
        _futureCompleter = null;
      }

      super.dispose();
    });
  }

  bool _isDisposing = false;

  /// Flag that we always should include the last successful value in `CommandResult`
  /// for isExecuting or error states
  final bool _includeLastResultInCommandResults;

  ///Flag to signal the wrapped command has no return value which means
  ///`notifyListener` has to be called directly
  final bool _noReturnValue;

  ///Flag to signal the wrapped command expects not parameter value
  final bool _noParamValue;

  final ErrorFilter _errorFilter;

  final ErrorFilterFn? _errorFilterFn;

  /// optional Name that is included in log messages.
  final String? _name;

  String? get name => _name;

  Completer<TResult>? _futureCompleter;

  Trace? _traceBeforeExecute;

  /// Runs an async Command and returns a Future that completes as soon as
  /// the Command completes. This is especially useful if you use a
  /// RefreshIndicator
  Future<TResult> runAsync([TParam? param]) {
    assert(
      this is CommandAsync || this is UndoableCommand,
      'runAsync can\t be used with synchronous Commands',
    );
    if (_futureCompleter != null && !_futureCompleter!.isCompleted) {
      return _futureCompleter!.future;
    }
    _futureCompleter = Completer<TResult>();

    run(param);
    return _futureCompleter!.future;
  }

  /// Deprecated: Use [runAsync] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use runAsync() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  Future<TResult> executeWithFuture([TParam? param]) => runAsync(param);

  /// Returns a the result of one of three builders depending on the current state
  /// of the Command. This function won't trigger a rebuild if the command changes states
  /// so it should be used together with get_it_mixin, provider, flutter_hooks and the like.
  @Deprecated(
    'Use CommandResult.toWidget() instead. '
    'This will be removed in v10.0.0.',
  )
  Widget toWidget({
    required Widget Function(TResult lastResult, TParam? param) onResult,
    Widget Function(TResult lastResult, TParam? param)? whileRunning,
    @Deprecated(
      'Use whileRunning instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    Widget Function(TResult lastResult, TParam? param)? whileExecuting,
    Widget Function(Object? error, TParam? param)? onError,
  }) {
    if (_commandResult.value.hasError) {
      return onError?.call(
            _commandResult.value.error,
            _commandResult.value.paramData,
          ) ??
          const SizedBox();
    }
    if (isRunning.value) {
      return (whileRunning ?? whileExecuting)?.call(
            value,
            _commandResult.value.paramData,
          ) ??
          const SizedBox();
    }
    return onResult(value, _commandResult.value.paramData);
  }

  bool get _hasLocalErrorHandler =>
      _commandResult.listenerCount >= 2 || _errors.hasListeners;

  void _handleErrorFiltered(
    TParam? param,
    Object error,
    StackTrace stackTrace,
  ) {
    // Check which filter is provided (assertion in constructor ensures only one)
    ErrorReaction errorReaction;
    if (_errorFilterFn != null) {
      errorReaction = _errorFilterFn(error, stackTrace);
    } else {
      errorReaction = _errorFilter.filter(error, stackTrace);
    }

    // If defaulErrorFilter is returned, use the default filter
    if (errorReaction == ErrorReaction.defaulErrorFilter) {
      errorReaction = errorFilterDefault.filter(error, stackTrace);
    }
    bool pushToResults = true;
    bool callGlobal = false;
    switch (errorReaction) {
      case ErrorReaction.none:
        assert(
          _futureCompleter == null,
          'Command: $_name: ErrorFilter returned [ErrorReaction.none], but this Command is executed with [runAsync] which is '
          'combination that is not allowed, because of the error we don\t have any value to complet the future normally with.',
        );
        pushToResults = false;
        return;
      case ErrorReaction.throwException:
        Error.throwWithStackTrace(error, stackTrace);
      case ErrorReaction.globalHandler:
        assert(
          globalExceptionHandler != null,
          'Command: $_name: Errorfilter returned [ErrorReaction.globalHandler], but no global handler is registered',
        );
        callGlobal = true;
        break;
      case ErrorReaction.localHandler:
        assert(
          _hasLocalErrorHandler,
          'Command: $_name: ErrorFilter returned ErrorReaction.localHandler, but there are no listeners on errors or .result',
        );
        break;
      case ErrorReaction.localAndGlobalHandler:
        assert(
          globalExceptionHandler != null,
          'Command: $_name: Errorfilter returned ErrorReaction.localAndgloBalHandler, but no global handler is registered',
        );
        assert(
          _hasLocalErrorHandler,
          'Command: $_name: ErrorFilter returned ErrorReaction.localAndGlobalHandler, but there are no listeners on errors or .result',
        );
        callGlobal = true;
        break;
      case ErrorReaction.firstLocalThenGlobalHandler:
        if (!_hasLocalErrorHandler) {
          assert(
            globalExceptionHandler != null,
            'Command: $_name: Errorfilter returned ErrorReaction.firsLocalThenGlobalHandler, but no global handler is registered',
          );
          callGlobal = true;
        }
        break;
      case ErrorReaction.noHandlersThrowException:
        if (!_hasLocalErrorHandler && globalExceptionHandler == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (!_hasLocalErrorHandler) {
          callGlobal = true;
        }
        break;
      case ErrorReaction.throwIfNoLocalHandler:
        if (!_hasLocalErrorHandler) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        break;
      case ErrorReaction.defaulErrorFilter:
        throw StateError(
          'The defaultErrorFilter of Command: $_name\'s returned "ErrorReaction.defaultErrorFilter" which isn\'t allowed.',
        );
    }
    if (pushToResults) {
      _commandResult.value = CommandResult<TParam, TResult>(
        param,
        _includeLastResultInCommandResults ? value : null,
        error,
        false,
        errorReaction: errorReaction,
        stackTrace: stackTrace,
      );
    }
    if (callGlobal) {
      _internalGlobalErrorHandler(
        CommandError(
          paramData: param,
          error: error,
          command: this,
          errorReaction: errorReaction,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
    _futureCompleter?.completeError(error, stackTrace);
    _futureCompleter = null;
  }

  Chain _improveStacktrace(StackTrace stacktrace) {
    var trace = Trace.from(stacktrace);

    final strippedFrames = trace.frames
        .where(
          (frame) => switch (frame) {
            Frame(package: 'stack_trace') => false,
            Frame(:final member) when member!.contains('Zone') => false,
            Frame(:final member) when member!.contains('_rootRun') => false,
            Frame(package: 'command_it', :final member)
                when member!.contains('_run') =>
              false,
            _ => true,
          },

          /// leave that for now, not 100% sure if it's better
          // return switch ((frame.package, frame.member)) {
          //   ('stack_trace', _) => false,
          //   (_, final member) when member!.contains('Zone') => false,
          //   (_, final member) when member!.contains('_rootRun') => false,
          //   ('command_it', final member) when member!.contains('_run') =>
          //     false,
          //   _ => true
          // };
          // if (frame.package == 'stack_trace') {
          //   return false;
          // }
          // if (frame.member?.contains('Zone') == true) {
          //   return false;
          // }
          // if (frame.member?.contains('_rootRun') == true) {
          //   return false;
          // }
          // if (frame.package == 'command_it' &&
          //     frame.member!.contains('_run')) {
          //   return false;
          // }
          // return true;
        )
        .toList();
    if (strippedFrames.isNotEmpty) {
      final commandFrame = strippedFrames.removeLast();
      strippedFrames.add(
        Frame(
          commandFrame.uri,
          commandFrame.line,
          commandFrame.column,
          _name != null
              ? '${commandFrame.member} ($_name)'
              : commandFrame.member,
        ),
      );
    }
    trace = Trace(strippedFrames);

    final framesBefore = _traceBeforeExecute?.frames.where(
          (frame) => frame.package != 'command_it',
        ) ??
        [];

    final chain = Chain([trace, Trace(framesBefore)]);

    return chain.terse;
  }

  ///////////////////////// Factory functions from here on //////////////////////

  ///
  /// Creates  a Command for a synchronous handler function with no parameter and no return type
  /// [action] : handler function
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// As synchronous function doesn't give any the UI any chance to react on on a change of
  /// `.isExecuting`,isExecuting isn't supported for synchronous commands ans will throw an
  /// assert if you try to use it.
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, void> createSyncNoParamNoResult(
    void Function() action, {
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return CommandSync<void, void>(
      funcNoParam: action,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  a Command for a synchronous handler function with one parameter and no return type
  /// [action] : handler function
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// As synchronous function doesn't give the UI any chance to react on on a change of
  /// `.isExecuting`,isExecuting isn't supported for synchronous commands and will throw an
  /// assert if you try to use it.
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, void> createSyncNoResult<TParam>(
    void Function(TParam x) action, {
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return CommandSync<TParam, void>(
      func: (x) => action(x),
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );
  }

  /// Creates  a Command for a synchronous handler function with no parameter that returns a value
  /// [func] : handler function
  /// [initialValue] sets the `.value` of the Command.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable the command based on
  /// some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [includeLastResultInCommandResults] will include the value of the last successful execution in
  /// all `CommandResult` values unless there is no result. This can be handy if you always want to be able
  /// to display something even when you got an error.
  /// As synchronous function doesn't give any the UI any chance to react on on a change of
  /// `.isExecuting`,isExecuting isn't supported for synchronous commands and will throw an
  /// assert if you try to use it.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, TResult> createSyncNoParam<TResult>(
    TResult Function() func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return CommandSync<void, TResult>(
      funcNoParam: func,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  a Command for a synchronous handler function with parameter that returns a value
  /// [func] : handler function
  /// [initialValue] sets the `.value` of the Command.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable the command based on
  ///  some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [includeLastResultInCommandResults] will include the value of the last successful execution in
  /// all `CommandResult` values unless there is no result. This can be handy if you always want to be able
  /// to display something even when you got an error.
  /// As synchronous function doesn't give the UI any chance to react on on a change of
  /// `.isExecuting`,isExecuting isn't supported for synchronous commands and will throw an
  /// assert if you try to use it.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, TResult> createSync<TParam, TResult>(
    TResult Function(TParam x) func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return CommandSync<TParam, TResult>(
      func: func,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );
  }

  // Asynchronous

  /// Creates  a Command for an asynchronous handler function with no parameter and no return type
  /// [action] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, void> createAsyncNoParamNoResult(
    Future<void> Function() action, {
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return CommandAsync<void, void>(
      funcNoParam: action,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  a Command for an asynchronous handler function with one parameter and no return type
  /// [action] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, void> createAsyncNoResult<TParam>(
    Future<void> Function(TParam x) action, {
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return CommandAsync<TParam, void>(
      func: action,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );
  }

  /// Creates  a Command for an asynchronous handler function with no parameter that returns a value
  /// [func] : handler function
  /// [initialValue] sets the `.value` of the Command.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable the command based on
  ///  some other state change. `true` means that the Command cannot be executed. If omitted the command
  /// can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [includeLastResultInCommandResults] will include the value of the last successful execution in
  /// all `CommandResult` values unless there is no result. This can be handy if you always want to be able
  /// to display something even when you got an error or while the command is still running.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, TResult> createAsyncNoParam<TResult>(
    Future<TResult> Function() func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return CommandAsync<void, TResult>(
      funcNoParam: func,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  a Command for an asynchronous handler function with parameter that returns a value
  /// [func] : handler function
  /// [initialValue] sets the `.value` of the Command.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable the command based on
  ///  some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [includeLastResultInCommandResults] will include the value of the last successful execution in
  /// all `CommandResult` values unless there is no result. This can be handy if you always want to be able
  /// to display something even when you got an error or while the command is still running.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, TResult> createAsync<TParam, TResult>(
    Future<TResult> Function(TParam x) func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return CommandAsync<TParam, TResult>(
      func: func,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );
  }

  /// Creates  an undoable Command for an asynchronous handler function with no parameter and no return type
  /// [action] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [undo] : function that undoes the action.
  /// [undoOnExecutionFailure] : if `true` the undo function will be executed automatically if the action
  /// fails.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, void> createUndoableNoParamNoResult<TUndoState>(
    Future<void> Function(UndoStack<TUndoState>) action, {
    required UndoFn<TUndoState, void> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter = const ErrorHandlerLocal(),
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return UndoableCommand<void, void, TUndoState>(
      funcNoParam: action,
      undo: undo,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      undoOnExecutionFailure: undoOnExecutionFailure,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  an undoable Command for an asynchronous handler function with one parameter and no return type
  /// [action] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [undo] : function that undoes the action.
  /// [undoOnExecutionFailure] : if `true` the undo function will be executed automatically if the action
  /// fails.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, void> createUndoableNoResult<TParam, TUndoState>(
    Future<void> Function(TParam, UndoStack<TUndoState>) action, {
    required UndoFn<TUndoState, void> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return UndoableCommand<TParam, void, TUndoState>(
      func: action,
      undo: undo,
      undoOnExecutionFailure: undoOnExecutionFailure,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );
  }

  /// Creates  a undoable Command for an asynchronous handler function with no parameter that returns a value
  /// [func] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [undo] : function that undoes the action.
  /// [initialValue] sets the `.value` of the Command.
  /// [undoOnExecutionFailure] : if `true` the undo function will be executed automatically if the action
  /// fails.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<void, TResult> createUndoableNoParam<TResult, TUndoState>(
    Future<TResult> Function(UndoStack<TUndoState>) func, {
    required TResult initialValue,
    required UndoFn<TUndoState, TResult> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    void Function()? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    void Function()? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    final handler = ifRestrictedRunInstead ?? ifRestrictedExecuteInstead;
    return UndoableCommand<void, TResult, TUndoState>(
      funcNoParam: func,
      undo: undo,
      initialValue: initialValue,
      undoOnExecutionFailure: undoOnExecutionFailure,
      restriction: restriction,
      ifRestrictedRunInstead: handler != null ? (_) => handler() : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );
  }

  /// Creates  a Command for an asynchronous handler function with parameter that returns a value
  /// [func] : handler function
  /// Can't be used with an `ValueListenableBuilder` because it doesn't have a value, but you can
  /// register a handler to wait for the completion of the wrapped function.
  /// [undo] : function that undoes the action.
  /// [initialValue] sets the `.value` of the Command.
  /// [undoOnExecutionFailure] : if `true` the undo function will be executed automatically if the action
  /// fails.
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// If omitted the command can be executed always except it's already executing
  /// [ifRestrictedRunInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
  /// [errorFilter] : overrides the default set by [errorFilterDefault].
  /// If `false`, Exceptions thrown by the wrapped function won't be caught but rethrown
  /// unless there is a listener on [errors] or [results].
  /// [notifyOnlyWhenValueChanges] : the default is that the command notifies it's listeners even
  /// if the value hasn't changed. If you set this to `true` the command will only notify
  /// it's listeners if the value has changed.
  /// [debugName] optional identifier that is included when you register a [globalExceptionHandler]
  /// or a [loggingHandler]
  static Command<TParam, TResult> createUndoable<TParam, TResult, TUndoState>(
    Future<TResult> Function(TParam, UndoStack<TUndoState>) func, {
    required TResult initialValue,
    required UndoFn<TUndoState, TResult> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    assert(
      !(ifRestrictedRunInstead != null && ifRestrictedExecuteInstead != null),
      'Cannot provide both ifRestrictedRunInstead and ifRestrictedExecuteInstead. Use ifRestrictedRunInstead.',
    );
    return UndoableCommand<TParam, TResult, TUndoState>(
      func: func,
      initialValue: initialValue,
      undo: undo,
      restriction: restriction,
      ifRestrictedRunInstead:
          ifRestrictedRunInstead ?? ifRestrictedExecuteInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
      undoOnExecutionFailure: undoOnExecutionFailure,
    );
  }

  /// Creates an async Command with [ProgressHandle] for progress tracking,
  /// status messages, and cooperative cancellation.
  ///
  /// The wrapped function receives both the parameter and a [ProgressHandle]
  /// that can be used to report progress (0.0-1.0), update status messages,
  /// and check for cancellation requests.
  ///
  /// Example:
  /// ```dart
  /// final uploadCommand = Command.createAsyncWithProgress<File, String>(
  ///   (file, handle) async {
  ///     for (int i = 0; i <= 100; i += 10) {
  ///       if (handle.isCanceled.value) return 'Canceled';
  ///       await uploadChunk(file, i);
  ///       handle.updateProgress(i / 100.0);
  ///       handle.updateStatusMessage('Uploading: $i%');
  ///     }
  ///     return 'Complete';
  ///   },
  ///   initialValue: '',
  /// );
  ///
  /// // UI observes progress
  /// LinearProgressIndicator(value: uploadCommand.progress.value)
  /// Text(uploadCommand.statusMessage.value ?? 'Ready')
  ///
  /// // UI can cancel
  /// ElevatedButton(onPressed: uploadCommand.cancel, child: Text('Cancel'))
  /// ```
  ///
  /// [func] : handler function that receives parameter and ProgressHandle
  /// [initialValue] : the initial value that the Command has before it executes
  /// [restriction] : `ValueListenable<bool>` that can be used to enable/disable
  /// the command based on some other state change. `true` means that the Command cannot be executed.
  /// [ifRestrictedRunInstead] : if [restriction] is set and its value is `true`,
  /// this function will be called instead of the wrapped function
  /// [includeLastResultInCommandResults] : by default false, if set to `true` the
  /// `data` field of `CommandResult` will hold the last valid result even while
  /// running and in case of an error
  /// [errorFilter] : overrides the default set by [errorFilterDefault]
  /// [errorFilterFn] : function-based error filter (alternative to errorFilter)
  /// [notifyOnlyWhenValueChanges] : if `true`, only notifies listeners when value changes
  /// [debugName] : optional name for debugging/logging
  static Command<TParam, TResult> createAsyncWithProgress<TParam, TResult>(
    Future<TResult> Function(TParam x, ProgressHandle handle) func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's function to reset handle state and inject the handle
    Future<TResult> wrappedFunc(TParam param) async {
      handle.reset(); // Reset progress state before each execution
      return await func(param, handle);
    }

    // Create the command with the wrapped function
    final command = CommandAsync<TParam, TResult>(
      func: wrappedFunc,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an async Command with [ProgressHandle] for no-parameter functions.
  ///
  /// Similar to [createAsyncWithProgress] but for functions that don't take parameters.
  ///
  /// Example:
  /// ```dart
  /// final syncCommand = Command.createAsyncNoParamWithProgress<String>(
  ///   (handle) async {
  ///     handle.updateStatusMessage('Syncing...');
  ///     for (int i = 0; i < 10; i++) {
  ///       if (handle.isCanceled.value) return 'Canceled';
  ///       await syncItem(i);
  ///       handle.updateProgress((i + 1) / 10.0);
  ///     }
  ///     return 'Synced';
  ///   },
  ///   initialValue: '',
  /// );
  /// ```
  static Command<void, TResult> createAsyncNoParamWithProgress<TResult>(
    Future<TResult> Function(ProgressHandle handle) func, {
    required TResult initialValue,
    ValueListenable<bool>? restriction,
    VoidCallback? ifRestrictedRunInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's function to reset handle state and inject the handle
    Future<TResult> wrappedFunc() async {
      handle.reset(); // Reset progress state before each execution
      return await func(handle);
    }

    // Create the command with the wrapped function
    final command = CommandAsync<void, TResult>(
      funcNoParam: wrappedFunc,
      initialValue: initialValue,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead != null
          ? (_) => ifRestrictedRunInstead()
          : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an async Command with [ProgressHandle] for void-return functions.
  ///
  /// Similar to [createAsyncWithProgress] but for functions that don't return a value.
  ///
  /// Example:
  /// ```dart
  /// final deleteCommand = Command.createAsyncNoResultWithProgress<int>(
  ///   (itemId, handle) async {
  ///     handle.updateStatusMessage('Deleting item $itemId...');
  ///     await api.delete(itemId);
  ///     handle.updateProgress(1.0);
  ///   },
  /// );
  /// ```
  static Command<TParam, void> createAsyncNoResultWithProgress<TParam>(
    Future<void> Function(TParam x, ProgressHandle handle) action, {
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's action to reset handle state and inject the handle
    Future<void> wrappedAction(TParam param) async {
      handle.reset(); // Reset progress state before each execution
      return await action(param, handle);
    }

    // Create the command with the wrapped action
    final command = CommandAsync<TParam, void>(
      func: wrappedAction,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: false,
      name: debugName,
      noParamValue: false,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an async Command with [ProgressHandle] for no-parameter, void-return functions.
  ///
  /// Similar to [createAsyncWithProgress] but for functions that neither take
  /// parameters nor return values.
  ///
  /// Example:
  /// ```dart
  /// final refreshCommand = Command.createAsyncNoParamNoResultWithProgress(
  ///   (handle) async {
  ///     handle.updateStatusMessage('Refreshing...');
  ///     handle.updateProgress(0.5);
  ///     await api.refresh();
  ///     handle.updateProgress(1.0);
  ///   },
  /// );
  /// ```
  static Command<void, void> createAsyncNoParamNoResultWithProgress(
    Future<void> Function(ProgressHandle handle) action, {
    ValueListenable<bool>? restriction,
    VoidCallback? ifRestrictedRunInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's action to reset handle state and inject the handle
    Future<void> wrappedAction() async {
      handle.reset(); // Reset progress state before each execution
      return await action(handle);
    }

    // Create the command with the wrapped action
    final command = CommandAsync<void, void>(
      funcNoParam: wrappedAction,
      initialValue: null,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead != null
          ? (_) => ifRestrictedRunInstead()
          : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: false,
      name: debugName,
      noParamValue: true,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an undoable Command with [ProgressHandle] for async functions.
  ///
  /// Combines undo capability with progress tracking, status messages, and cancellation.
  /// The wrapped function receives the parameter, ProgressHandle, and UndoStack.
  ///
  /// Example:
  /// ```dart
  /// final uploadCommand = Command.createUndoableWithProgress<File, String, UploadState>(
  ///   (file, handle, undoStack) async {
  ///     handle.updateStatusMessage('Starting upload...');
  ///     final uploadId = await api.startUpload(file);
  ///     undoStack.addUndoState(UploadState(uploadId));
  ///
  ///     for (int i = 0; i < chunks; i++) {
  ///       if (handle.isCanceled.value) {
  ///         await api.cancelUpload(uploadId);
  ///         return 'Canceled';
  ///       }
  ///       await uploadChunk(file, i);
  ///       handle.updateProgress((i + 1) / chunks);
  ///     }
  ///     return 'Upload complete';
  ///   },
  ///   undo: (state, _) async {
  ///     await api.deleteUpload(state.uploadId);
  ///   },
  ///   initialValue: '',
  /// );
  /// ```
  static Command<TParam, TResult>
      createUndoableWithProgress<TParam, TResult, TUndoState>(
    Future<TResult> Function(TParam, ProgressHandle, UndoStack<TUndoState>)
        func, {
    required TResult initialValue,
    required UndoFn<TUndoState, TResult> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's function to reset handle state and inject the handle
    Future<TResult> wrappedFunc(
        TParam param, UndoStack<TUndoState> undoStack) async {
      handle.reset(); // Reset progress state before each execution
      return await func(param, handle, undoStack);
    }

    // Create the command with the wrapped function
    final command = UndoableCommand<TParam, TResult, TUndoState>(
      func: wrappedFunc,
      initialValue: initialValue,
      undo: undo,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: false,
      undoOnExecutionFailure: undoOnExecutionFailure,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an undoable Command with [ProgressHandle] for no-parameter functions.
  ///
  /// Similar to [createUndoableWithProgress] but for functions that don't take parameters.
  ///
  /// Example:
  /// ```dart
  /// final syncCommand = Command.createUndoableNoParamWithProgress<String, SyncState>(
  ///   (handle, undoStack) async {
  ///     handle.updateStatusMessage('Syncing...');
  ///     final timestamp = DateTime.now();
  ///     undoStack.addUndoState(SyncState(timestamp));
  ///
  ///     for (int i = 0; i < items; i++) {
  ///       if (handle.isCanceled.value) return 'Canceled';
  ///       await syncItem(i);
  ///       handle.updateProgress((i + 1) / items);
  ///     }
  ///     return 'Synced';
  ///   },
  ///   undo: (state, _) async {
  ///     await revertToTimestamp(state.timestamp);
  ///   },
  ///   initialValue: '',
  /// );
  /// ```
  static Command<void, TResult>
      createUndoableNoParamWithProgress<TResult, TUndoState>(
    Future<TResult> Function(ProgressHandle, UndoStack<TUndoState>) func, {
    required TResult initialValue,
    required UndoFn<TUndoState, TResult> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    VoidCallback? ifRestrictedRunInstead,
    bool includeLastResultInCommandResults = false,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    bool notifyOnlyWhenValueChanges = false,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's function to reset handle state and inject the handle
    Future<TResult> wrappedFunc(UndoStack<TUndoState> undoStack) async {
      handle.reset(); // Reset progress state before each execution
      return await func(handle, undoStack);
    }

    // Create the command with the wrapped function
    final command = UndoableCommand<void, TResult, TUndoState>(
      funcNoParam: wrappedFunc,
      initialValue: initialValue,
      undo: undo,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead != null
          ? (_) => ifRestrictedRunInstead()
          : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: includeLastResultInCommandResults,
      noReturnValue: false,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
      name: debugName,
      noParamValue: true,
      undoOnExecutionFailure: undoOnExecutionFailure,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an undoable Command with [ProgressHandle] for void-return functions.
  ///
  /// Similar to [createUndoableWithProgress] but for functions that don't return a value.
  ///
  /// Example:
  /// ```dart
  /// final deleteCommand = Command.createUndoableNoResultWithProgress<int, DeleteState>(
  ///   (itemId, handle, undoStack) async {
  ///     handle.updateStatusMessage('Deleting item $itemId...');
  ///     final item = await api.getItem(itemId);
  ///     undoStack.addUndoState(DeleteState(item));
  ///     await api.delete(itemId);
  ///     handle.updateProgress(1.0);
  ///   },
  ///   undo: (state, _) async {
  ///     await api.restore(state.item);
  ///   },
  /// );
  /// ```
  static Command<TParam, void>
      createUndoableNoResultWithProgress<TParam, TUndoState>(
    Future<void> Function(TParam, ProgressHandle, UndoStack<TUndoState>)
        action, {
    required UndoFn<TUndoState, void> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    RunInsteadHandler<TParam>? ifRestrictedRunInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's action to reset handle state and inject the handle
    Future<void> wrappedAction(
        TParam param, UndoStack<TUndoState> undoStack) async {
      handle.reset(); // Reset progress state before each execution
      return await action(param, handle, undoStack);
    }

    // Create the command with the wrapped action
    final command = UndoableCommand<TParam, void, TUndoState>(
      func: wrappedAction,
      initialValue: null,
      undo: undo,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: false,
      name: debugName,
      noParamValue: false,
      undoOnExecutionFailure: undoOnExecutionFailure,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }

  /// Creates an undoable Command with [ProgressHandle] for no-parameter, void-return functions.
  ///
  /// Similar to [createUndoableWithProgress] but for functions that neither take
  /// parameters nor return values.
  ///
  /// Example:
  /// ```dart
  /// final clearCacheCommand = Command.createUndoableNoParamNoResultWithProgress<CacheState>(
  ///   (handle, undoStack) async {
  ///     handle.updateStatusMessage('Backing up cache...');
  ///     final backup = await backupCache();
  ///     undoStack.addUndoState(CacheState(backup));
  ///     handle.updateProgress(0.5);
  ///
  ///     handle.updateStatusMessage('Clearing cache...');
  ///     await clearCache();
  ///     handle.updateProgress(1.0);
  ///   },
  ///   undo: (state, _) async {
  ///     await restoreCache(state.backup);
  ///   },
  /// );
  /// ```
  static Command<void, void>
      createUndoableNoParamNoResultWithProgress<TUndoState>(
    Future<void> Function(ProgressHandle, UndoStack<TUndoState>) action, {
    required UndoFn<TUndoState, void> undo,
    bool undoOnExecutionFailure = true,
    ValueListenable<bool>? restriction,
    VoidCallback? ifRestrictedRunInstead,
    ErrorFilter? errorFilter,
    ErrorFilterFn? errorFilterFn,
    String? debugName,
  }) {
    // Create the ProgressHandle
    final handle = ProgressHandle();

    // Wrap the user's action to reset handle state and inject the handle
    Future<void> wrappedAction(UndoStack<TUndoState> undoStack) async {
      handle.reset(); // Reset progress state before each execution
      return await action(handle, undoStack);
    }

    // Create the command with the wrapped action
    final command = UndoableCommand<void, void, TUndoState>(
      funcNoParam: wrappedAction,
      initialValue: null,
      undo: undo,
      restriction: restriction,
      ifRestrictedRunInstead: ifRestrictedRunInstead != null
          ? (_) => ifRestrictedRunInstead()
          : null,
      ifRestrictedExecuteInstead: null,
      includeLastResultInCommandResults: false,
      noReturnValue: true,
      errorFilter: errorFilter,
      errorFilterFn: errorFilterFn,
      notifyOnlyWhenValueChanges: false,
      name: debugName,
      noParamValue: true,
      undoOnExecutionFailure: undoOnExecutionFailure,
    );

    // Attach the handle to the command
    command._handle = handle;

    return command;
  }
}

/// Extension to pipe [ValueListenable] changes to a [Command].
///
/// This allows chaining commands - when the source ValueListenable changes,
/// it automatically triggers the target command.
///
/// **Warning**: Circular pipes (A→B→A) will cause infinite loops.
/// Ensure your pipe graph is acyclic.
///
/// Example:
/// ```dart
/// // Trigger refresh after save completes
/// saveCommand.pipeToCommand(refreshCommand);
///
/// // With transform function
/// userIdCommand.pipeToCommand(fetchUserCommand, transform: (id) => UserRequest(id));
///
/// // Pipe from isRunning to track execution state
/// longCommand.isRunning.pipeToCommand(spinnerCommand);
/// ```
extension ValueListenablePipe<T> on ValueListenable<T> {
  /// Triggers [target] command whenever this ValueListenable's value changes.
  ///
  /// - If [transform] is provided, transforms the value before passing to target
  /// - If [transform] is null and value is assignable to TTargetParam, passes directly
  /// - If [transform] is null and types don't match, calls target.run() without param
  ///   (useful for triggering no-param commands)
  ///
  /// Returns the [ListenableSubscription] for manual cancellation if needed.
  /// Normally, the subscription is automatically cleaned up when the source
  /// ValueListenable is disposed.
  ListenableSubscription pipeToCommand<TTargetParam, TTargetResult>(
    Command<TTargetParam, TTargetResult> target, {
    TTargetParam Function(T value)? transform,
  }) {
    return listen((value, _) {
      if (transform != null) {
        target.run(transform(value));
      } else if (value is TTargetParam) {
        target.run(value);
      } else {
        // Types don't match, call without param (for void/no-param targets)
        target.run();
      }
    });
  }
}
