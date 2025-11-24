[9.4.0] - 2024-11-24

### New Features

- **Progress Control**: Commands now support built-in progress tracking, status messages, and cooperative cancellation through the new `ProgressHandle` class.

**New Factory Methods** (8 variants):
- `Command.createAsyncWithProgress<TParam, TResult>()` - Async command with progress tracking
- `Command.createAsyncNoParamWithProgress<TResult>()` - No-param async with progress
- `Command.createAsyncNoResultWithProgress<TParam>()` - Void-return async with progress
- `Command.createAsyncNoParamNoResultWithProgress()` - No-param, void-return async with progress
- `Command.createUndoableWithProgress<TParam, TResult, TUndoState>()` - Undoable with progress
- `Command.createUndoableNoParamWithProgress<TResult, TUndoState>()` - No-param undoable with progress
- `Command.createUndoableNoResultWithProgress<TParam, TUndoState>()` - Void-return undoable with progress
- `Command.createUndoableNoParamNoResultWithProgress<TUndoState>()` - No-param, void-return undoable with progress

**New Command Properties**:
- `progress` - Observable progress value (0.0-1.0) via `ValueListenable<double>`
- `statusMessage` - Observable status text via `ValueListenable<String?>`
- `isCanceled` - Observable cancellation flag via `ValueListenable<bool>`
- `cancel()` - Request cooperative cancellation

**MockCommand Progress Support**:
- `withProgressHandle` constructor parameter to enable progress simulation
- `updateMockProgress(double)` - Simulate progress updates in tests
- `updateMockStatusMessage(String?)` - Simulate status message updates
- `mockCancel()` - Simulate cancellation

**Example Usage**:
```dart
final uploadCommand = Command.createAsyncWithProgress<File, String>(
  (file, handle) async {
    for (int i = 0; i <= 100; i += 10) {
      if (handle.isCanceled.value) return 'Canceled';

      await uploadChunk(file, i);
      handle.updateProgress(i / 100.0);
      handle.updateStatusMessage('Uploading: $i%');
    }
    return 'Complete';
  },
  initialValue: '',
);

// In UI:
watchValue((MyService s) => s.uploadCommand.progress)  // 0.0 to 1.0
watchValue((MyService s) => s.uploadCommand.statusMessage)  // Status text
uploadCommand.cancel();  // Request cancellation
```

**Benefits**:
- Zero-overhead: Commands without progress use static default notifiers (no memory cost)
- Type-safe: Progress properties available on all commands via non-nullable API
- Cooperative cancellation: Works with external cancellation tokens (e.g., Dio's CancelToken)
- Test-friendly: MockCommand supports full progress simulation

[9.3.0] - 2025-01-23

### Added

- **MockCommand "run" Terminology**: MockCommand now uses "run" terminology to match the Command API migration from v9.0.0:
  - `startRun()` - replaces `startExecution()`
  - `endRunWithData()` - replaces `endExecutionWithData()`
  - `endRunWithError()` - replaces `endExecutionWithError()`
  - `endRunNoData()` - replaces `endExecutionNoData()`
  - `queueResultsForNextRunCall()` - replaces `queueResultsForNextExecuteCall()`
  - `runCount` property - replaces `executionCount`
  - `lastPassedValueToRun` property - replaces `lastPassedValueToExecute`
  - `returnValuesForNextRun` property - replaces `returnValuesForNextExecute`

### Deprecated

- **Old MockCommand "execute" Terminology**: All "execute" terminology methods and properties in MockCommand are now deprecated
- Will be removed in v10.0.0
- See `BREAKING_CHANGE_EXECUTE_TO_RUN.md` for migration guide

[9.2.0] - 2025-11-22

### New Features

- **CommandBuilder Auto-Run**: CommandBuilder now supports automatically executing commands on first build via `runCommandOnFirstBuild` parameter. This is especially useful for non-watch_it users who want self-contained data-loading widgets without needing StatefulWidget boilerplate.

```dart
CommandBuilder<String, List<Item>>(
  command: searchCommand,
  runCommandOnFirstBuild: true,  // Executes in initState
  initialParam: 'flutter',        // Parameter to pass
  onData: (context, items, _) => ItemList(items),
  whileRunning: (context, _, __) => LoadingIndicator(),
)
```

**Benefits:**
- Eliminates StatefulWidget boilerplate for simple data loading
- Self-contained widgets that manage their own data fetching
- Runs only once in initState (not on rebuilds)
- Perfect for non-watch_it users (watch_it users should continue using `callOnce`)

### Deprecations

- **Deprecated Command.toWidget()**: The `Command.toWidget()` method is now deprecated in favor of `CommandResult.toWidget()`. The CommandResult version provides a richer API with better separation of concerns (onData/onSuccess/onNullData) and is already used by CommandBuilder. Command.toWidget() will be removed in v10.0.0.

**Migration:**
```dart
// Before (deprecated):
command.toWidget(
  onResult: (data, param) => DataWidget(data),
  whileRunning: (lastData, param) => LoadingWidget(),
  onError: (error, param) => ErrorWidget(error),
)

// After (recommended):
ValueListenableBuilder(
  valueListenable: command.results,
  builder: (context, result, _) => result.toWidget(
    onData: (data, param) => DataWidget(data),
    whileRunning: (lastData, param) => LoadingWidget(),
    onError: (error, lastData, param) => ErrorWidget(error),
  ),
)
```

[9.1.1] - 2025-11-21

### Improvements

- **Renamed GlobalIfNoLocalErrorFilter**: Renamed `FirstLocalThenGlobalErrorFilter` to `GlobalIfNoLocalErrorFilter` for better clarity. The name now clearly indicates "global if no local handler".

### New Features

- **Added GlobalErrorFilter**: New filter that routes errors ONLY to the global handler, regardless of local listeners. Returns `ErrorReaction.globalHandler`.

### Fixes

- **Removed incorrectly named GlobalErrorFilter**: The previous `GlobalErrorFilter` that was deprecated in v9.1.0 has been removed and replaced with the correct implementation.

[9.1.0] - 2025-11-21

### New Features

- **Global errors stream**: Added `Command.globalErrors` stream that emits all command errors across the entire application. This provides a centralized way to observe, log, and respond to command errors without polling individual commands.

**Key capabilities:**
- **Reactive error monitoring**: Stream emits `CommandError<dynamic>` for every globally-routed error
- **Production-focused**: Emits for ErrorFilter-routed errors and error handler exceptions, does NOT emit debug-only `reportAllExceptions`
- **Use cases**: Centralized logging, analytics/monitoring, crash reporting, global UI notifications (error toasts)
- **watch_it integration**: Perfect for `registerStreamHandler` to show error toasts in root widget

**Example - Global error toast with watch_it:**
```dart
class MyApp extends WatchingWidget {
  @override
  Widget build(BuildContext context) {
    registerStreamHandler<Stream<CommandError>, CommandError>(
      target: Command.globalErrors,
      handler: (context, snapshot, cancel) {
        if (snapshot.hasData) {
          final error = snapshot.data!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${error.error}')),
          );
        }
      },
    );
    return MaterialApp(...);
  }
}
```

**Stream behavior:**
- ✅ Emits when `ErrorFilter` routes error to global handler
- ✅ Emits when error handler itself throws (if `reportErrorHandlerExceptionsToGlobalHandler` enabled)
- ❌ Does NOT emit for `reportAllExceptions` (debug-only feature)
- Multiple listeners supported (broadcast stream)
- Cannot be closed

[9.0.3] - TBD

### Improvements

- **Improved ErrorFilter class naming consistency**: Renamed `ErrorHandler*` classes to simpler `*ErrorFilter` pattern to better align with existing filters. Old names remain functional with deprecation warnings until v10.0.0.

**Class name changes:**
- `ErrorHandlerGlobalIfNoLocal` → `GlobalIfNoLocalErrorFilter` (deprecated)
- `ErrorHandlerLocal` → `LocalErrorFilter` (deprecated)
- `ErrorHandlerLocalAndGlobal` → `LocalAndGlobalIfNoLocalErrorFilter` (deprecated)

**Why this change:**
- Better naming consistency: matches `TableErrorFilter` and `PredicatesErrorFilter` pattern
- Simpler and clearer: `LocalErrorFilter` vs `LocalHandlingFilter`
- All filter implementations now end with `*ErrorFilter`

**Migration:**
No action required - old names still work with deprecation warnings. Update at your convenience:
```dart
// Old (still works)
Command.errorFilterDefault = const ErrorHandlerGlobalIfNoLocal();
errorFilter: const ErrorHandlerLocal()

// New
Command.errorFilterDefault = const GlobalIfNoLocalErrorFilter();
errorFilter: const LocalErrorFilter()
```

[9.0.2] - 2025-11-15

### Fixes

- **Properly deprecated ExecuteInsteadHandler and ifRestrictedExecuteInstead**: Added proper deprecation instead of breaking renames. Both old (`ExecuteInsteadHandler`, `ifRestrictedExecuteInstead`) and new (`RunInsteadHandler`, `ifRestrictedRunInstead`) names now work during v9.x. Added comprehensive tests for deprecated variants to maintain coverage. Updated fix_data.yaml to auto-migrate users via `dart fix`.

[9.0.1] - 2025-11-14

### Fixes

- **Enhanced fix_data.yaml**: Added comprehensive coverage for all Command subclasses (`CommandAsync`, `CommandSync`, `UndoableCommand`) to ensure `dart fix` properly migrates deprecated API usage when commands are accessed through property getters

[9.0.0] - 2025-11-14

### Breaking Changes - API Terminology Migration (execute → run)

**This release renames the primary API from "execute" terminology to "run" for better Flutter ecosystem consistency.**

#### API Changes (with deprecation period until v10.0.0):

**Methods:**
- `execute([TParam? param])` → `run([TParam? param])`
- `executeWithFuture([TParam? param])` → `runAsync([TParam? param])`

**Properties:**
- `isExecuting` → `isRunning` (async notifications for UI)
- `isExecutingSync` → `isRunningSync` (sync notifications for command coordination)
- `canExecute` → `canRun`
- `thrownExceptions` → `errors`

**Parameters:**
- `ifRestrictedExecuteInstead:` → `ifRestrictedRunInstead:` (12 factory methods)
- `whileExecuting:` → `whileRunning:` (CommandBuilder and toWidget methods)

#### Migration Guide:

**Automated migration:** Run `dart fix --apply` to automatically update most usages via data-driven fixes.

**Manual search/replace patterns:**
```
.execute(             → .run(
.executeWithFuture(   → .runAsync(
.isExecuting          → .isRunning
.isExecutingSync      → .isRunningSync
.canExecute           → .canRun
.thrownExceptions     → .errors
ifRestrictedExecuteInstead:  → ifRestrictedRunInstead:
whileExecuting:       → whileRunning:
```

**Old API remains functional with deprecation warnings until v10.0.0.**

See [BREAKING_CHANGE_EXECUTE_TO_RUN.md](BREAKING_CHANGE_EXECUTE_TO_RUN.md) for complete migration details.

### New Features (from 8.1.0)
* Added `errorFilterFn` parameter for function-based error filtering - provides simple inline alternative to object-based `ErrorFilter` system
* Return `ErrorReaction` directly or `ErrorReaction.defaulErrorFilter` to delegate to default
* Assertion prevents using both `errorFilter` and `errorFilterFn` simultaneously
* Available on all 12 command factory methods and MockCommand

### Bug Fixes (from 8.1.0)
* Fixed unsafe ValueNotifier type casts in `_canExecute` field - changed to ValueListenable<bool> with safe disposal
* Fixed parameter order in CommandBuilder.onError callback - now (error, lastData, paramData) for consistency
* Fixed MockCommand type signature from `Command<TParam, TResult?>` to `Command<TParam, TResult>` to match real Commands

### Documentation
* Added comprehensive documentation to run() method (formerly execute())
* Improved error handling documentation in README with configuration examples
* Fixed image URLs to use flutter-it organization
* Updated all examples to use new "run" terminology
* Added data-driven fixes for automatic migration (fix_data.yaml)

[8.0.2]
### Maintenance
* Fixed analyzer issues in example_command_results (broken package imports, missing http version)
* Updated both examples to use latest dependencies (listen_it ^5.3.0, http ^1.0.0)

[8.0.1]
### Maintenance
* Updated listen_it dependency to ^5.3.0
* Updated GitHub Actions workflow with modern action versions and codecov v5
* Fixed workflow to trigger on main branch
* Fixed badges to point to flutter-it organization
* Fixed test pollution issue by adding proper setUp/tearDown

[8.0.0] - 19.07.2025
* although this doesn't add any new functionality because of the rebranding from flutter_command to command_it we use the next major version

[7.2.2] - 25.12.2024 >> from here all entries reference the old flutter_command package
* another fix
[7.2.1] - 25.12.2024
* logic fix
[7.2.0] - 25.12.2024
* adding `onSuccess` builder to the `CommandBuilder` and `isSuccess` to the `CommandResults` to make them easiery to use
if the Command doesn't return a value. 
[7.1.0] 27.11.2024
* adding `isExecutingSync` to allow better chaining of commands 
[7.0.1] 27.11.2024
* ensure that isExecuting is set back to false before we notify any result listeners.
[7.0.0] 14.11.2024
* add stricter static type checks. this is a breaking change because the `globalExceptionHandler` correctly has to accept `CommandError<dynamic>` instead of `CommandError<Object>`
[6.0.1] 29.09.2024
* Update to latest version of listen_it to fix a potential bug when removing the last listener from `canExecute`
[6.0.0] 
* official new release
[6.0.0+pre2] 
* fixing asssert in CommandBuilder
[6.0.0+pre1] 
* breaking changes: Command.debugName -> Command.name, ErrorReaction.defaultHandler -> ErrorReaction.defaulErrorFilter
* unless an error filter returns none or throwException all errors will be published on the `resultsProperty` including
the result of the error filter. This alloes you  if you use the `results` property to reject on any error with a generic action like popping a page while doing
the specific handlign of the error in the local or global handler.
* if an error handler itself throws an exception, that is now also reported to the `globalExceptionHandler` 
[5.0.0+20] - 18.07.2024
* undoing the last one as it makes merging of `errors` of multiple commands impossible
[5.0.0+19] - 18.07.2024
* added TParam in the defintion of the `errors` property
[5.0.0+18] - 18.07.2024
* adding precaution to make disposing of a command from one of its own handlers more robust
[5.0.0+17] - 08.11.2023
* https://github.com/escamoteur/flutter_command/issues/20 
[5.0.0+16] - 18.9.2023
* added experimental global setting `useChainCapture` which can lead to better stacktraces in async commands functions 
[5.0.0+15] - 30.08.2023 
* improved assertion error messages
[5.0.0+14] - 15.8.2023
* made commands more robust against disposing while still running which should be totally valid 
because the user could close a page where a command is running
[5.0.0+12] - 14.8.2023
* added check in dispose if the command hasn't finished yet
[5.0.0+11] - 13.8.2023
* fixed bub in UndoableCommand and disabled the Chain.capture for now
[5.0.0+10] - 11.8.2023
* general refactoring to reduce code duplication
* improving stack traces 
* adding new `reportAllExceptions` global override
[5.0.0+9] - 02.08.2023
* `clearErrors()` will now notify its listeners with a `null` value.
[5.0.0+8] - 31.07.2023
* made sure that while undo is running `isExecuting` is true and will block any parallel call of the command
[5.0.0+7] - 29.07.2023
* added `clearErrors` method to the `Command` class which resets the `errors` property to null without notifying listeners
* fix for Exception `Bad state: Future already completed` 
[5.0.0+6] - 20.06.2023
* added two more ErrorFilter types
[5.0.0+5] - 18.06.2023
* release candidate but missing docs
[5.0.0+4] - 18.05.2023
* bug fix of a too arrow assertion
[5.0.0+2] - 21.04.2023

* bug fix in the factory functions of UndoableCommand

[5.0.0+1] - 28.03.2023

* beta version of the new UndoableCommand

[5.0.0] - 24.03.2023

* Another breaking change but one that hopefully will be appreciated by most of you. When this package was originally written you could pass a `ValueListenable<bool> canExecute` when you created a Command that could decide if a Command could be executed at runtime. As the naming was am reminiscent of the .Net version of RxUIs Command but confusing because Commands have a property named `canExecute` too I renamed it to `restriction` but didn't change the meaning of its bool values. Which meant that `restriction==false` meant that the Command couldn't be executed which absolutely isn't intuitive.
After falling myself for this illogic use of bool values I know inverted the meaning so that `restriction==true` means 
that you cannot execute the Command.

* To add to the declarative power of defining behaviour with Command, they now got an optional handler that will be called 
if a Command is restricted but one tries to execute it anyway (from the source docs):

```dart
  /// [ifRestrictedExecuteInstead] if  [restriction] is set for the command and its value is `true`
  /// this function will be called instead of the wrapped function.
  /// This is useful if you want to execute a different function when the command
  /// is restricted. For example you could show a dialog to let the user logg in
  /// if the restriction is because the user is not logged in.
  /// If you don't set this function, the command will just do nothing when it's
  /// restricted.
```

[4.0.0] - 01.03.2023

* Two breaking changes in two days :-) I know that is a lot but I encountered a problem in one of my projects, that you might encounter too if you are using flutter_command. If your UI would change depending on the state of `isExecuting` and that change was triggered from within the build function, you could get an exception telling you, that `setState` was called while a rebuild was already running. In this new version async Commands now wait a frame before notifying any listeners. I don't expect, that you will see any difference in your existing apps. If this latest change has any negative side effects, please open an issue immediately. As the philosophy of Commands is that your UI should always only react on state changes and not expect synchronous data, this shouldn't make any trouble.

[3.0.0] - 24.02.2023

* Breaking change: In the past the Command only triggered listeners when the resulting value of a Command execution changed. However in many case you
want to always update your UI even if the result hasn't changed. Therefore Commands now always notify the listeners even if the result hasn't changed.
you can change that behaviour by setting [notifyOnlyWhenValueChanges] to true when creating your Commands.

## [2.0.1] - 07.03.2021

* Fixed small nullability bug in the signature of 

```Dart
  static Command<TParam, TResult> createAsync<TParam, TResult>(
      Future<TResult> Function(TParam? x) func, TResult initialValue
```

the type of `func` has to be correctly `Future<TResult> Function(TParam x)` so now it looks like
```dart
  static Command<TParam, TResult> createAsync<TParam, TResult>(
      Future<TResult> Function(TParam x) func, TResult initialValue,
```
You could probably call this a breaking change but as it won't change the behaviour, just that you probably will have to remove some '!' from your code I won't do a major version here.

## [2.0.0] - 03.03.2021

* finished null safety migration
* thrownExceptions only notifies its listeners now when a error happens and not also when it is reset to null at the beginning of a command

## [1.0.0-nullsafety.1] - 15.02.2021

* Added `toWidget()` extension method on `CommandResult`

## [0.9.2] - 25.10.2020

* Added `executeWithFuture` to use with `RefreshIndicator`
* Added `toWidget()` method

## [0.9.1] - 24.08.2020

* Shortened package description in pubspec

## [0.9.0] - 24.08.2020

* Initial official release
