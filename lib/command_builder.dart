part of command_it;

class CommandBuilder<TParam, TResult> extends StatefulWidget {
  final Command<TParam, TResult> command;

  /// This builder will be called when the
  /// command is executed successfully, independent of the return value.
  final Widget Function(BuildContext context, TParam? param)? onSuccess;

  /// If your command has a return value, you can use this builder to build a widget
  /// when the command is executed successfully.
  final Widget Function(BuildContext context, TResult data, TParam? param)?
      onData;

  /// If the command has no return value or returns null, this builder will be called when the
  /// command is executed successfully.
  final Widget Function(BuildContext context, TParam? param)? onNullData;

  final Widget Function(
    BuildContext context,
    TResult? lastValue,
    TParam? param,
  )? whileRunning;

  @Deprecated(
    'Use whileRunning instead. '
    'This will be removed in v10.0.0. '
    'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
  )
  final Widget Function(
    BuildContext context,
    TResult? lastValue,
    TParam? param,
  )? whileExecuting;

  final Widget Function(
    BuildContext context,
    Object,
    TResult? lastValue,
    TParam?,
  )? onError;

  /// If true, the command will be executed once when the widget is first built.
  /// This is useful for loading data when the widget is mounted, especially when
  /// not using watch_it (which provides `callOnce` for this purpose).
  ///
  /// The command will only run once in initState, not on subsequent rebuilds.
  final bool runCommandOnFirstBuild;

  /// The parameter to pass to the command when [runCommandOnFirstBuild] is true.
  /// Ignored if [runCommandOnFirstBuild] is false.
  final TParam? initialParam;

  const CommandBuilder({
    required this.command,
    this.onSuccess,
    this.onData,
    this.onNullData,
    this.whileRunning,
    @Deprecated(
      'Use whileRunning instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    this.whileExecuting,
    this.onError,
    this.runCommandOnFirstBuild = false,
    this.initialParam,
    super.key,
  });

  @override
  State<CommandBuilder<TParam, TResult>> createState() =>
      _CommandBuilderState<TParam, TResult>();
}

class _CommandBuilderState<TParam, TResult>
    extends State<CommandBuilder<TParam, TResult>> {
  @override
  void initState() {
    super.initState();
    if (widget.runCommandOnFirstBuild) {
      widget.command(widget.initialParam);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.command._noReturnValue) {}
    return ValueListenableBuilder<CommandResult<TParam?, TResult>>(
      valueListenable: widget.command.results,
      builder: (context, result, _) {
        return result.toWidget(
          onData: widget.onData != null
              ? (data, paramData) =>
                  widget.onData!.call(context, data, paramData)
              : null,
          onSuccess: widget.onSuccess != null
              ? (paramData) => widget.onSuccess!.call(context, paramData)
              : null,
          onNullData: widget.onNullData != null
              ? (paramData) => widget.onNullData!.call(context, paramData)
              : null,
          // ignore: deprecated_member_use_from_same_package
          whileRunning: (widget.whileRunning ?? widget.whileExecuting) != null
              // ignore: deprecated_member_use_from_same_package
              ? (lastData, paramData) =>
                  (widget.whileRunning ?? widget.whileExecuting)!
                      .call(context, lastData, paramData)
              : null,
          onError: (error, lastData, paramData) {
            if (widget.onError == null) {
              return const SizedBox();
            }
            assert(
              result.errorReaction?.shouldCallLocalHandler == true,
              'This CommandBuilder received an error from Command ${widget.command.name} '
              'but the errorReaction indidates that the error should not be handled locally. ',
            );
            return widget.onError!.call(context, error, lastData, paramData);
          },
        );
      },
    );
  }
}

extension ToWidgeCommandResult<TParam, TResult>
    on CommandResult<TParam, TResult> {
  Widget toWidget({
    Widget Function(TResult result, TParam? param)? onData,
    Widget Function(TParam? param)? onSuccess,
    Widget Function(TParam? param)? onNullData,
    Widget Function(TResult? lastResult, TParam? param)? whileRunning,
    @Deprecated(
      'Use whileRunning instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    Widget Function(TResult? lastResult, TParam? param)? whileExecuting,
    Widget Function(Object error, TResult? lastResult, TParam? param)? onError,
  }) {
    assert(
      onData != null || onSuccess != null,
      'You have to provide at least a builder for onData or onSuccess',
    );
    if (error != null) {
      return onError?.call(error!, data, paramData) ?? const SizedBox();
    }
    if (isRunning) {
      return (whileRunning ?? whileExecuting)?.call(data, paramData) ??
          const SizedBox();
    }
    if (onSuccess != null) {
      return onSuccess.call(paramData);
    }
    if (data != null) {
      return onData?.call(data as TResult, paramData) ?? const SizedBox();
    } else {
      return onNullData?.call(paramData) ?? const SizedBox();
    }
  }
}
