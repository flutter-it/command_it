# command_it Expert - Command Pattern with Reactive States

**What**: Wrap functions as command objects with automatic loading/error/result states. Built on listen_it.

## CRITICAL RULES

- Use `run()` to execute commands, NOT `execute()` (deprecated)
- Sync commands ASSERT on `isRunning` access - use async commands for loading states
- `restriction.value == true` means command is DISABLED (cannot run)
- Factory constructors with `TResult` require `initialValue` parameter
- Error filters return `ErrorReaction` enum, NOT bool

## Factory Constructors

Choose the right one based on parameter/result combinations:

```dart
// ASYNC - Most common
Command.createAsyncNoParamNoResult(() async { ... });
Command.createAsyncNoResult<TParam>((param) async { ... });
Command.createAsyncNoParam<TResult>(() async { ... }, initialValue: defaultValue);
Command.createAsync<TParam, TResult>((param) async { ... }, initialValue: defaultValue);

// SYNC - No isRunning support
Command.createSyncNoParamNoResult(() { ... });
Command.createSyncNoResult<TParam>((param) { ... });
Command.createSyncNoParam<TResult>(() { ... }, initialValue: defaultValue);
Command.createSync<TParam, TResult>((param) { ... }, initialValue: defaultValue);

// UNDOABLE - With undo stack
Command.createUndoableNoResult<TParam, TUndoState>(
  (param, undoStack) async { undoStack.push(currentState); ... },
  undo: (undoStack, error) async { final prev = undoStack.pop(); restore(prev); },
);

// WITH PROGRESS - Progress tracking
Command.createAsyncNoParamWithProgress<TResult>(
  (handle) async {
    handle.updateProgress(0.5);
    handle.updateStatusMessage('Loading...');
    if (handle.isCanceled.value) return defaultValue;
    ...
  },
  initialValue: defaultValue,
);
```

## Execution

```dart
command.run();                    // Fire and forget (returns void)
command.run(param);               // With parameter
command(param);                   // Callable class syntax (alias for run)
final result = await command.runAsync(param);  // Await result (async commands only)
```

## Observable Properties (all ValueListenable)

```dart
command.isRunning        // ValueListenable<bool> - ASYNC ONLY (asserts on sync), use for UI
command.isRunningSync    // ValueListenable<bool> - ONLY for restrictions, NOT for UI updates
command.canRun           // ValueListenable<bool> - !restriction && !isRunning
command.errors           // ValueListenable<CommandError<TParam>?>
command.errorsDynamic    // ValueListenable<CommandError<dynamic>?>
command.results          // ValueListenable<CommandResult<TParam?, TResult>>

// WithProgress commands only:
command.progress         // ValueListenable<double> - 0.0 to 1.0
command.statusMessage    // ValueListenable<String?>
command.isCanceled       // ValueListenable<bool>
```

## CommandResult Properties

```dart
final result = command.results.value;
result.data          // TResult? - the return value
result.error         // Object? - exception if failed
result.isRunning     // bool
result.paramData     // TParam? - parameter passed to command
result.hasError      // bool
result.hasData       // bool
result.isSuccess     // bool
result.stackTrace    // StackTrace?
```

## Restrictions

`restriction` takes `ValueListenable<bool>` - when `true`, command CANNOT run:

```dart
// Disable command while another is running
final saveCommand = Command.createAsyncNoParamNoResult(
  () async { ... },
  restriction: loadCommand.isRunning,  // Can't save while loading
);

// Custom restriction
final isOffline = ValueNotifier<bool>(false);
final fetchCommand = Command.createAsyncNoParamNoResult(
  () async { ... },
  restriction: isOffline,  // Can't fetch when offline
);

// ifRestrictedRunInstead - alternative action when restricted
final cmd = Command.createAsyncNoParamNoResult(
  () async { ... },
  restriction: someCondition,
  ifRestrictedRunInstead: () => showToast('Cannot run now'),
);
```

## Error Handling

**ErrorFilter** returns `ErrorReaction` enum:

```dart
enum ErrorReaction {
  none,                        // Swallow error
  throwException,              // Rethrow
  globalHandler,               // Only global handler
  localHandler,                // Only local listeners
  localAndGlobalHandler,       // Both
  firstLocalThenGlobalHandler, // Local first, global if no local (DEFAULT)
  noHandlersThrowException,    // Throw if no handlers at all
  throwIfNoLocalHandler,       // Throw if no local handler
}
```

**Built-in filters**:
```dart
// Default - local first, global as fallback
errorFilter: const GlobalIfNoLocalErrorFilter(),

// Local listeners only, no Sentry/global
errorFilter: const LocalErrorFilter(),

// Both local and global always
errorFilter: const LocalAndGlobalErrorFilter(),

// Global only (e.g., Sentry logging, no UI)
errorFilter: const GlobalErrorFilter(),
```

**Custom filter function**:
```dart
errorFilterFn: (Object error, StackTrace stackTrace) {
  if (error is ApiException && error.code == 404) {
    return ErrorReaction.localHandler;  // UI handles 404
  }
  return ErrorReaction.firstLocalThenGlobalHandler;  // Default for rest
},
```

**Custom filter class**:
```dart
class MyErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ApiException && error.code == 404) {
      return ErrorReaction.localAndGlobalHandler;
    }
    return ErrorReaction.globalHandler;
  }
}
```

**Global exception handler** (static property, not method):
```dart
Command.globalExceptionHandler = (CommandError error, StackTrace stackTrace) {
  Sentry.captureException(error.error, stackTrace: stackTrace);
};
```

**Global error stream** - `Command.globalErrors` is a `Stream<CommandError>` of all globally-handled errors. Use `registerStreamHandler` in your root widget to show toasts for errors not handled locally:
```dart
// In root widget (e.g. MyApp)
registerStreamHandler(
  target: Command.globalErrors,
  handler: (context, snapshot, cancel) {
    if (snapshot.hasData) showErrorToast(context, snapshot.data!.error);
  },
);
```

**Listening to errors**:
`.errors` only emits actual `CommandError` objects - no null check needed. Errors are automatically reset to null on each new `run()` without triggering handlers.
```dart
// With listen_it
command.errors.listen((error, subscription) {
  showErrorDialog(error.error);
});

// With watch_it registerHandler
registerHandler(
  select: (MyManager m) => m.deleteCommand.errors,
  handler: (context, error, cancel) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete failed: ${error.error}')),
    );
  },
);
```

## Static Configuration

```dart
Command.globalExceptionHandler = ...;          // Global error callback
Command.errorFilterDefault = LocalErrorFilter(); // Change default filter
Command.globalErrors;                          // Stream<CommandError> of all errors
Command.loggingHandler = (name, result) { };   // Log all command executions
Command.assertionsAlwaysThrow = true;          // Default: true
Command.reportAllExceptions = false;           // Default: false
Command.detailedStackTraces = true;            // Default: true
```

## Production Patterns

**Async command with error filter**:
```dart
late final getListingPreviewCommand =
    Command.createAsync<GetListingPreviewRequest, SellerFeesDto?>(
  (request) async {
    final api = MarketplaceApi(di<ApiClient>());
    return await api.getListingPreview(request);
  },
  debugName: 'getListingPreview',
  initialValue: null,
  errorFilter: const GlobalIfNoLocalErrorFilter(),
);
```

**Undoable delete with recovery**:
```dart
deletePostCommand = Command.createUndoableNoResult<PostProxy, PostProxy>(
  (post, undoStack) async {
    undoStack.push(post);
    await PostApi(di<ApiClient>()).deletePost(post.id);
  },
  undo: (stack, error) {
    final post = stack.pop();
    di<EventBus>().sendUndoDeletePostEvent(post);
  },
  errorFilter: const GlobalIfNoLocalErrorFilter(),
);
```

**Restriction chaining**:
```dart
late final updateAvatarCommand = Command.createAsyncNoResult<File>(
  (file) async { ... },
  restriction: updateFromBackendCommand.isRunning,
);
```

**Custom error filter hierarchy**:
```dart
class LocalOnlyErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return ErrorReaction.localHandler;
  }
}

class Api404ToSentry403LocalErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      if (error.code == 404) return ErrorReaction.localAndGlobalHandler;
      if (error.code == 403) return ErrorReaction.localHandler;
    }
    return ErrorReaction.globalHandler;
  }
}
```

## Anti-Patterns

```dart
// ❌ Using deprecated execute()
command.execute();
// ✅ Use run()
command.run();

// ❌ Accessing isRunning on sync command
final cmd = Command.createSyncNoParamNoResult(() => print('hi'));
cmd.isRunning;  // ASSERTION ERROR
// ✅ Use async command for loading states
final cmd = Command.createAsyncNoParamNoResult(() async => print('hi'));
cmd.isRunning;  // Works

// ❌ Error filter returning bool
errorFilter: (error, hasLocal) => true  // WRONG TYPE
// ✅ Return ErrorReaction enum
errorFilterFn: (error, stackTrace) => ErrorReaction.localHandler
```
