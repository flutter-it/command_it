part of './command_it.dart';

class CommandSync<TParam, TResult> extends Command<TParam, TResult> {
  final TResult Function(TParam)? _func;
  final TResult Function()? _funcNoParam;

  @override
  ValueListenable<bool> get isRunning {
    assert(false, "isRunning isn't supported by synchronous commands");
    return ValueNotifier<bool>(false);
  }

  CommandSync({
    TResult Function(TParam)? func,
    TResult Function()? funcNoParam,
    required super.initialValue,
    required super.restriction,
    required super.ifRestrictedRunInstead,
    @Deprecated(
      'Use ifRestrictedRunInstead instead. '
      'This will be removed in v10.0.0. '
      'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.',
    )
    required super.ifRestrictedExecuteInstead,
    required super.includeLastResultInCommandResults,
    required super.noReturnValue,
    required super.errorFilter,
    required super.errorFilterFn,
    required super.notifyOnlyWhenValueChanges,
    required super.name,
    required super.noParamValue,
  })  : _func = func,
        _funcNoParam = funcNoParam;

  @override
  TResult _run([TParam? param]) {
    if (_noParamValue) {
      assert(_funcNoParam != null);
      return _funcNoParam!();
    } else {
      assert(_func != null);
      assert(
        param != null || null is TParam,
        'You passed a null value to the command ${_name ?? ''} that has a non-nullable type as TParam',
      );
      return _func!(param as TParam);
    }
  }
}
