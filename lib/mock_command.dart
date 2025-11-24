part of './command_it.dart';

/// `MockCommand` allows you to easily mock an Command for your Unit and UI tests
/// Mocking a command with `mockito` https://pub.dartlang.org/packages/mockito has its limitations.
class MockCommand<TParam, TResult> extends Command<TParam, TResult> {
  /// Internal storage for queued results - use [queueResultsForNextRunCall] to set
  List<CommandResult<TParam, TResult>>? returnValuesForNextRun;

  /// the last value that was passed when run or the command directly was called
  TParam? lastPassedValueToRun;

  /// Number of times run or the command directly was called
  int runCount = 0;

  /// Deprecated: Use [runCount] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use runCount instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  int get executionCount => runCount;

  @Deprecated(
    'Use runCount instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  set executionCount(int value) => runCount = value;

  /// Deprecated: Use [lastPassedValueToRun] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use lastPassedValueToRun instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  TParam? get lastPassedValueToExecute => lastPassedValueToRun;

  @Deprecated(
    'Use lastPassedValueToRun instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  set lastPassedValueToExecute(TParam? value) => lastPassedValueToRun = value;

  /// Deprecated: Use [returnValuesForNextRun] instead.
  /// This property will be removed in v10.0.0.
  @Deprecated(
    'Use returnValuesForNextRun instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  List<CommandResult<TParam, TResult>>? get returnValuesForNextExecute =>
      returnValuesForNextRun;

  @Deprecated(
    'Use returnValuesForNextRun instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  set returnValuesForNextExecute(List<CommandResult<TParam, TResult>>? value) =>
      returnValuesForNextRun = value;

  /// constructor that can take an optional `ValueListenable` to control if the command can be run
  /// if the wrapped function has `void` as return type [noResult] has to be `true`
  /// [withProgressHandle] if `true` creates a [ProgressHandle] to enable progress simulation in tests
  MockCommand({
    required super.initialValue,
    super.noParamValue = false,
    super.noReturnValue = false,
    super.restriction,
    super.ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    super.ifRestrictedExecuteInstead,
    super.includeLastResultInCommandResults = false,
    super.errorFilter,
    super.errorFilterFn,
    super.notifyOnlyWhenValueChanges = false,
    super.name,
    bool withProgressHandle = false,
  }) {
    _commandResult
        .where((result) => result.hasData)
        .listen((result, _) => value = result.data!);

    // Create ProgressHandle if requested for testing progress-aware commands
    if (withProgressHandle) {
      _handle = ProgressHandle();
    }
  }

  /// Deprecated: Use [queueResultsForNextRunCall] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use queueResultsForNextRunCall() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  // ignore: use_setters_to_change_properties
  void queueResultsForNextExecuteCall(
    List<CommandResult<TParam, TResult>> values,
  ) {
    queueResultsForNextRunCall(values);
  }

  /// Can either be called directly or by calling the object itself because Commands are callable classes
  /// Will increase [runCount] and assign [lastPassedValueToRun] the value of [param]
  /// If you have queued a result with [queueResultsForNextRunCall] it will be copies tho the output stream.
  /// [isRunning], [canRun] and [results] will work as with a real command.
  @override
  void run([TParam? param]) {
    if (_restriction?.value == true) {
      _ifRestrictedRunInstead?.call(param);
      return;
    }
    if (!_canRun.value) {
      return;
    }

    _isRunning.value = true;
    runCount++;
    lastPassedValueToRun = param;
    // ignore: avoid_print
    print('Called Execute');
    if (returnValuesForNextRun != null) {
      returnValuesForNextRun!.map((entry) {
        if ((entry.isRunning || entry.hasError) &&
            _includeLastResultInCommandResults) {
          return CommandResult<TParam, TResult>(
            param,
            value,
            entry.error,
            entry.isRunning,
          );
        }
        return entry;
      }).forEach((x) => _commandResult.value = x);
    } else if (_noReturnValue) {
      notifyListeners();
    } else {
      // ignore: avoid_print
      print('No values for execution queued');
    }
    _isRunning.value = false;
  }

  /// Deprecated: Use [run] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use run() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  @override
  void execute([TParam? param]) => run(param);

  /// Deprecated: Use [startRun] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use startRun() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  void startExecution([TParam? param]) {
    startRun(param);
  }

  /// Deprecated: Use [endRunWithData] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use endRunWithData() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  void endExecutionWithData(TResult data) {
    endRunWithData(data);
  }

  /// Deprecated: Use [endRunWithError] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use endRunWithError() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  void endExecutionWithError(String message) {
    endRunWithError(message);
  }

  /// Deprecated: Use [endRunNoData] instead.
  /// This method will be removed in v10.0.0.
  @Deprecated(
    'Use endRunNoData() instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  void endExecutionNoData() {
    endRunNoData();
  }

  /// For a more fine grained control to simulate the different states of an [Command]
  /// there are these functions
  /// `startRun` will issue a [CommandResult] with
  /// data: null
  /// error: null
  /// isRunning : true
  void startRun([TParam? param]) {
    lastPassedValueToRun = param;
    _commandResult.value = CommandResult<TParam, TResult>(
      param,
      _includeLastResultInCommandResults ? value : null,
      null,
      true,
    );
    _isRunning.value = true;
  }

  /// `endRunWithData` will issue a [CommandResult] with
  /// data: [data]
  /// error: null
  /// isRunning : false
  void endRunWithData(TResult data) {
    value = data;
    _commandResult.value = CommandResult<TParam, TResult>(
      lastPassedValueToRun,
      data,
      null,
      false,
    );
    if (_name != null) {
      Command.loggingHandler?.call(_name, _commandResult.value);
    }
    _isRunning.value = false;
  }

  /// `endRunWithError` will issue a [CommandResult] with
  /// data: null
  /// error: Exception([message])
  /// isRunning : false
  void endRunWithError(String message) {
    _handleErrorFiltered(
      lastPassedValueToRun,
      Exception(message),
      StackTrace.current,
    );
    _isRunning.value = false;
    if (_name != null) {
      Command.loggingHandler?.call(_name, _commandResult.value);
    }
  }

  /// `endRunNoData` will issue a [CommandResult] with
  /// data: null
  /// error: null
  /// isRunning : false
  void endRunNoData() {
    _commandResult.value = CommandResult<TParam, TResult>(
      lastPassedValueToRun,
      _includeLastResultInCommandResults ? value : null,
      null,
      false,
    );
    if (_name != null) {
      Command.loggingHandler?.call(_name, _commandResult.value);
    }
    _isRunning.value = false;
  }

  /// to be able to simulate any output of the command when it is called you can here queue the output data for the next run call
  // ignore: use_setters_to_change_properties
  void queueResultsForNextRunCall(
    List<CommandResult<TParam, TResult>> values,
  ) {
    returnValuesForNextRun = values;
  }

  /// Simulates a progress update for testing progress-aware commands.
  ///
  /// Requires the MockCommand to be created with `withProgressHandle: true`.
  ///
  /// Example:
  /// ```dart
  /// final mockCommand = MockCommand<int, String>(
  ///   initialValue: '',
  ///   withProgressHandle: true,
  /// );
  /// mockCommand.updateMockProgress(0.5);
  /// expect(mockCommand.progress.value, 0.5);
  /// ```
  void updateMockProgress(double value) {
    assert(
      _handle != null,
      'MockCommand must be created with withProgressHandle: true to simulate progress updates',
    );
    _handle!.updateProgress(value);
  }

  /// Simulates a status message update for testing progress-aware commands.
  ///
  /// Requires the MockCommand to be created with `withProgressHandle: true`.
  ///
  /// Example:
  /// ```dart
  /// final mockCommand = MockCommand<int, String>(
  ///   initialValue: '',
  ///   withProgressHandle: true,
  /// );
  /// mockCommand.updateMockStatusMessage('Processing...');
  /// expect(mockCommand.statusMessage.value, 'Processing...');
  /// ```
  void updateMockStatusMessage(String? message) {
    assert(
      _handle != null,
      'MockCommand must be created with withProgressHandle: true to simulate status message updates',
    );
    _handle!.updateStatusMessage(message);
  }

  /// Simulates cancellation for testing progress-aware commands.
  ///
  /// Requires the MockCommand to be created with `withProgressHandle: true`.
  ///
  /// Example:
  /// ```dart
  /// final mockCommand = MockCommand<int, String>(
  ///   initialValue: '',
  ///   withProgressHandle: true,
  /// );
  /// mockCommand.mockCancel();
  /// expect(mockCommand.isCanceled.value, true);
  /// ```
  void mockCancel() {
    assert(
      _handle != null,
      'MockCommand must be created with withProgressHandle: true to simulate cancellation',
    );
    _handle!.cancel();
  }

  @override
  Future<TResult> _run([TParam? param]) async {
    // Not implemented - MockCommand overrides run() directly instead of using _run()
    throw UnimplementedError();
  }
}
