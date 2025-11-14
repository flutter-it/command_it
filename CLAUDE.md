# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**command_it** is a Flutter package that implements the Command design pattern using `ValueListenable` for reactive state management. It wraps functions (sync/async) as callable objects that provide automatic execution state tracking, error handling, and UI integration.

**Key concept**: A Command wraps a function and makes it observable - the UI can react to execution state, results, and errors without tight coupling.

## Dependencies

- **listen_it** (^5.3.0): Provides `ValueListenable` operators (map, debounce, where, etc.) - critical dependency
- **stack_trace** (^1.11.0): Enhanced error stack traces
- **quiver** (^3.0.0): Utility functions

## Development Commands

### Testing

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/flutter_command_test.dart

# Run specific test file (error tests)
flutter test test/error_test.dart

# Run with coverage
flutter test --coverage
```

### Code Quality

```bash
# Analyze code
flutter analyze

# Format code (REQUIRED before commits per user instructions)
dart format .

# Dry-run publish check
flutter pub publish --dry-run
```

### Example App

```bash
cd example
flutter run
```

## Architecture

### Core Classes

**Command<TParam, TResult>** (abstract base in `command_it.dart`)
- `TParam`: Type of parameter the wrapped function expects
- `TResult`: Return type of the wrapped function
- Extends `CustomValueNotifier<TResult>` from listen_it
- Implements callable class pattern - can be invoked directly: `myCommand(param)`

**CommandSync<TParam, TResult>** (`sync_command.dart`)
- Wraps synchronous functions
- **Does NOT support `isRunning`** - will assert if accessed (sync functions don't give UI time to react)
- Execution happens immediately on call

**CommandAsync<TParam, TResult>** (`async_command.dart`)
- Wraps asynchronous functions
- Full support for `isRunning` tracking
- Updates UI progressively: before execution → during → after completion

**UndoableCommand<TParam, TResult, TUndoState>** (`undoable_command.dart`)
- Extends CommandAsync with undo capability
- Maintains `UndoStack<TUndoState>` for state snapshots
- Optional auto-undo on execution failure via `undoOnExecutionFailure` parameter

### Factory Functions Pattern

Commands are created via static factory functions, not constructors:

```dart
// Sync commands
Command.createSyncNoParamNoResult(action)
Command.createSyncNoResult<TParam>(action)
Command.createSyncNoParam<TResult>(func, initialValue)
Command.createSync<TParam, TResult>(func, initialValue)

// Async commands
Command.createAsyncNoParamNoResult(action)
Command.createAsyncNoResult<TParam>(action)
Command.createAsyncNoParam<TResult>(func, initialValue)
Command.createAsync<TParam, TResult>(func, initialValue)

// Undoable commands
Command.createUndoableNoParamNoResult<TUndoState>(action, undo)
Command.createUndoableNoResult<TParam, TUndoState>(action, undo)
Command.createUndoableNoParam<TResult, TUndoState>(func, undo, initialValue)
Command.createUndoable<TParam, TResult, TUndoState>(func, undo, initialValue)
```

**Why this matters**: Type inference works better with factory functions than constructors for generic types.

### ValueListenable Properties

Every Command exposes multiple `ValueListenable` interfaces for different aspects:

1. **Command itself** (`ValueListenable<TResult>`): Emits function results
2. **`.results`** (`ValueListenable<CommandResult<TParam?, TResult>>`): Combined state object containing:
   - `data`: The result value
   - `paramData`: Parameter passed to command
   - `error`: Any error that occurred
   - `isRunning`: Current execution state
3. **`.isRunning`** (`ValueListenable<bool>`): Async only, updated asynchronously
4. **`.isRunningSync`** (`ValueListenable<bool>`): Synchronous version for use as restrictions
5. **`.canRun`** (`ValueListenable<bool>`): Computed as `!restriction && !isRunning`
6. **`.errors`** (`ValueListenable<CommandError<TParam>?>`): Error-specific notifications

### Error Handling System

**ErrorFilter** (defined in `error_filters.dart`) - determines error reaction strategy:

**ErrorReaction enum values**:
- `none`: Swallow errors silently
- `throwException`: Rethrow immediately
- `localHandler`: Call listeners on `.errors` or `.results`
- `globalHandler`: Call `Command.globalExceptionHandler`
- `localAndGlobalHandler`: Call both
- `firstLocalThenGlobalHandler`: Try local, fallback to global (default)
- `noHandlersThrowException`: Throw if no handlers present
- `throwIfNoLocalHandler`: Throw if no local listeners

**Built-in ErrorFilter implementations**:
- `ErrorHandlerGlobalIfNoLocal`: Default behavior
- `ErrorHandlerLocal`: Local only
- `ErrorHandlerLocalAndGlobal`: Both handlers
- `TableErrorFilter`: Map error types to reactions
- `PredicatesErrorFilter`: Chain of predicate functions
- `ErrorFilterExcemption<T>`: Special handling for specific type

**Global configuration**:
```dart
Command.errorFilterDefault = const ErrorHandlerGlobalIfNoLocal();
Command.globalExceptionHandler = (error, stackTrace) { /* log */ };
Command.assertionsAlwaysThrow = true; // AssertionErrors bypass filters
Command.reportAllExceptions = false; // Override filters, report everything
Command.detailedStackTraces = true; // Capture enhanced traces
```

### Restriction Mechanism

Commands can be conditionally disabled via `restriction` parameter:

```dart
final restriction = ValueNotifier<bool>(false); // false = can run
final cmd = Command.createAsync<String, List<Data>>(
  fetchData,
  [],
  restriction: restriction, // Command disabled when true
  ifRestrictedRunInstead: (param) {
    // Optional: handle restricted execution (e.g., show login)
  },
);
```

**Important**: `restriction: true` means DISABLED, `false` means enabled.

The `.canRun` property automatically combines restriction with execution state.

### Widget Integration

**CommandBuilder** (`command_builder.dart`):
```dart
CommandBuilder<String, List<Data>>(
  command: myCommand,
  whileRunning: (context, _) => CircularProgressIndicator(),
  onData: (context, data, _) => DataList(data),
  onError: (context, error, param) => ErrorWidget(error),
  onSuccess: (context, _) => SuccessWidget(), // For void result commands
)
```

**Extension method** for use with get_it_mixin/provider/flutter_hooks:
```dart
result.toWidget(
  whileRunning: (lastValue, _) => LoadingWidget(),
  onResult: (data, _) => DataWidget(data),
  onError: (error, lastValue, paramData) => ErrorWidget(error),
)
```

## Testing Patterns

### Test Structure

Tests use a `Collector<T>` helper class to accumulate ValueListenable emissions:

```dart
final Collector<bool> canRunCollector = Collector<bool>();
final Collector<CommandResult> cmdResultCollector = Collector<CommandResult>();

void setupCollectors(Command command) {
  command.canRun.listen((b, _) => canRunCollector(b));
  command.results.listen((r, _) => cmdResultCollector(r));
  // ... etc
}

// In test:
setupCollectors(command);
command.run();
expect(canRunCollector.values, [true, false, true]);
```

### Async Test Utilities

- Use `fake_async` package for controlling time in tests
- Commands support `runAsync()` for testing with `await`
- Test both positive and error paths for each command type

### Running Individual Tests

```bash
# Run single test by name
flutter test --name "Run simple sync action No Param No Result"

# Run test group
flutter test --name "Synchronous Command Testing"
```

## Code Organization

```
lib/
├── command_it.dart          # Main export file + Command abstract class
├── async_command.dart       # CommandAsync implementation (part of)
├── sync_command.dart        # CommandSync implementation (part of)
├── undoable_command.dart    # UndoableCommand implementation (part of)
├── error_filters.dart       # ErrorFilter system (standalone export)
├── command_builder.dart     # CommandBuilder widget (part of)
├── mock_command.dart        # MockCommand for testing (part of)
└── code_for_docs.dart       # Documentation examples

test/
├── flutter_command_test.dart  # Main test suite
└── error_test.dart            # Error handling tests
```

**Note**: Most files use `part of './command_it.dart'` - they're not standalone libraries.

## Common Patterns

### Pattern 1: Convert events to ValueListenable

```dart
// Text field changes with debounce
final textChangedCommand = Command.createSync<String, String>((s) => s, '');
textChangedCommand.debounce(Duration(milliseconds: 500)).listen((text, _) {
  fetchDataCommand.run(text);
});
```

### Pattern 2: Chaining commands via restrictions

```dart
final saveCmd = Command.createAsync<Data, void>(
  saveData,
  null,
  restriction: loadCmd.isRunningSync, // Can't save while loading
);
```

### Pattern 3: Using includeLastResultInCommandResults

```dart
final cmd = Command.createAsync<String, List<Item>>(
  fetchItems,
  [],
  includeLastResultInCommandResults: true, // Keep showing old data while loading/on error
);
```

### Pattern 4: RefreshIndicator integration

```dart
RefreshIndicator(
  onRefresh: () => updateCommand.runAsync(), // Returns Future<T>
  child: ListView(...),
)
```

## Important Behavioral Notes

1. **Commands always notify by default** (unlike ValueNotifier):
   - Set `notifyOnlyWhenValueChanges: true` to match ValueNotifier behavior
   - This ensures UI rebuilds on every execution, even if result is identical

2. **Disposal is async**:
   - `dispose()` waits 50ms before actually disposing to let async notifications complete
   - Guards against disposal during execution via `_isDisposing` flag

3. **Error value reset**:
   - `.errors` emits `null` at start of each execution to clear previous errors
   - Use `.where((x) => x != null)` from listen_it to filter these out

4. **Sync commands and isRunning**:
   - Accessing `.isRunning` on sync commands throws assertion
   - Use async commands if you need execution state tracking

5. **Global vs Local error handlers**:
   - Local handlers: listeners on `.errors` or `.results`
   - Global handler: `Command.globalExceptionHandler`
   - ErrorFilter determines which gets called

## Package-Specific Constraints

- **No code generation**: Pure runtime approach
- **ValueListenable-based**: All reactivity through ValueListenable interface
- **Type-safe**: Generic types `<TParam, TResult>` enforce compile-time checking
- **Callable class**: Commands can be called like functions: `cmd()` or `cmd(param)`

## Documentation

- **README.md**: Complete package documentation with examples (530 lines)
- **Documentation site**: https://flutter-it.dev/documentation/command_it/getting_started
- **API docs**: Extensive inline documentation in source code

## Integration with Ecosystem

- **get_it**: Commands work seamlessly with get_it service locator
- **watch_it**: Use with `watchX` functions for builder-free reactive UI
- **listen_it**: Commands ARE ValueListenables, use all listen_it operators
- Part of flutter_it ecosystem but each package is independent

## Common Pitfalls

1. **Forgetting initialValue**: Commands with return values require `initialValue` parameter
2. **Wrong restriction value**: `true` = disabled, `false` = enabled (counterintuitive!)
3. **Awaiting sync commands**: Don't use `runAsync()` with sync commands - will assert
4. **Not disposing**: Commands must be disposed to prevent memory leaks
5. **ErrorFilter confusion**: Custom filters must not return `ErrorReaction.defaulErrorFilter`
