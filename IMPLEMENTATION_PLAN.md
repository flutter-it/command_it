# Implementation Plan: Hybrid Error Filter API

**Version**: v8.1.0 (non-breaking addition)
**Estimated Time**: 4-6 hours
**Complexity**: Medium

---

## Overview

Add support for function-based error filters alongside existing object-based filters by:
1. Adding `ErrorFilterFn` typedef
2. Adding `errorFilterFn` parameter to all factory methods
3. Converting both inputs to internal function representation
4. Maintaining backward compatibility

---

## Phase 1: Define Function Type and Update Command Base Class

**Files**: `lib/command_it.dart`
**Time**: 30 minutes
**Status**: Not started

### Step 1.1: Add ErrorFilterFn typedef

**Location**: `lib/command_it.dart` (after imports, before ErrorReaction enum)

```dart
// Add after imports, around line 13
typedef ErrorFilterFn = ErrorReaction? Function(
  Object error,
  StackTrace stackTrace,
);
```

**Rationale**: Define function signature explicitly for type safety.

### Step 1.2: Update Command constructor

**Location**: `lib/command_it.dart:169` (Command constructor)

**Current code**:
```dart
Command({
  required TResult initialValue,
  required ValueListenable<bool>? restriction,
  required ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
  required bool includeLastResultInCommandResults,
  required bool noReturnValue,
  required bool notifyOnlyWhenValueChanges,
  ErrorFilter? errorFilter,  // ← Current parameter
  required String? name,
  required bool noParamValue,
})  : _errorFilter = errorFilter ?? errorFilterDefault,
      // ...
```

**New code**:
```dart
Command({
  required TResult initialValue,
  required ValueListenable<bool>? restriction,
  required ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
  required bool includeLastResultInCommandResults,
  required bool noReturnValue,
  required bool notifyOnlyWhenValueChanges,
  ErrorFilter? errorFilter,      // ← Keep for backward compatibility
  ErrorFilterFn? errorFilterFn,  // ← Add new parameter
  required String? name,
  required bool noParamValue,
})  : _errorFilterFn = _resolveErrorFilter(errorFilter, errorFilterFn),
      _restriction = restriction,
      _ifRestrictedExecuteInstead = ifRestrictedExecuteInstead,
      _noReturnValue = noReturnValue,
      _noParamValue = noParamValue,
      _includeLastResultInCommandResults = includeLastResultInCommandResults,
      _name = name,
      super(
        initialValue,
        mode: notifyOnlyWhenValueChanges
            ? CustomNotifierMode.normal
            : CustomNotifierMode.always,
      ) {
    assert(
      errorFilter == null || errorFilterFn == null,
      'Cannot provide both errorFilter and errorFilterFn. '
      'Use errorFilter for objects (e.g., RetryErrorFilter) or '
      'errorFilterFn for functions.',
    );

    // ... rest of constructor body (lines 193-243 unchanged)
  }
```

### Step 1.3: Replace `_errorFilter` field with `_errorFilterFn`

**Location**: `lib/command_it.dart:555`

**Current code**:
```dart
final ErrorFilter _errorFilter;
```

**New code**:
```dart
final ErrorFilterFn _errorFilterFn;
```

### Step 1.4: Add `_resolveErrorFilter` static method

**Location**: `lib/command_it.dart` (after constructor, before execute method)

**Insert after line ~243, before `void execute([TParam? param])`**:

```dart
/// Converts either ErrorFilter object or ErrorFilterFn function to
/// internal function representation.
///
/// Priority:
/// 1. If [objectFilter] provided, convert it to function
/// 2. Else if [functionFilter] provided, use it directly
/// 3. Else use global default filter
static ErrorFilterFn _resolveErrorFilter(
  ErrorFilter? objectFilter,
  ErrorFilterFn? functionFilter,
) {
  if (objectFilter != null) {
    // Convert object to function
    return (error, stackTrace) {
      final reaction = objectFilter.filter(error, stackTrace);
      // Convert defaulErrorFilter to null for consistency
      return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
    };
  }

  if (functionFilter != null) {
    // Use function directly
    return functionFilter;
  }

  // Use global default
  return (error, stackTrace) {
    final reaction = errorFilterDefault.filter(error, stackTrace);
    return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
  };
}
```

### Step 1.5: Update `_handleErrorFiltered` method

**Location**: `lib/command_it.dart:608`

**Current code**:
```dart
void _handleErrorFiltered(
  TParam? param,
  Object error,
  StackTrace stackTrace,
) {
  var errorReaction = _errorFilter.filter(error, stackTrace);
  if (errorReaction == ErrorReaction.defaulErrorFilter) {
    errorReaction = errorFilterDefault.filter(error, stackTrace);
  }
  // ... rest of method
}
```

**New code**:
```dart
void _handleErrorFiltered(
  TParam? param,
  Object error,
  StackTrace stackTrace,
) {
  // Call filter function (works for both converted objects and raw functions)
  var errorReaction = _errorFilterFn(error, stackTrace);

  // null means no match, apply default filter
  if (errorReaction == null) {
    final defaultReaction = errorFilterDefault.filter(error, stackTrace);
    // Default filter should never return defaulErrorFilter, but handle it just in case
    errorReaction = defaultReaction == ErrorReaction.defaulErrorFilter
        ? ErrorReaction.firstLocalThenGlobalHandler
        : defaultReaction;
  }

  // ... rest of method unchanged (lines 617-705)
}
```

**Testing checkpoint**: After these changes, existing tests should still pass.

---

## Phase 2: Update All 12 Factory Methods

**Files**: `lib/command_it.dart`
**Time**: 1 hour
**Status**: Not started

### Pattern for Updates

Each factory method needs:
1. Add `ErrorFilterFn? errorFilterFn` parameter (after `ErrorFilter? errorFilter`)
2. Pass both to constructor

### Step 2.1: Update `createSyncNoParamNoResult`

**Location**: `lib/command_it.dart:800`

**Current signature**:
```dart
static Command<void, void> createSyncNoParamNoResult(
  void Function() action, {
  ValueListenable<bool>? restriction,
  void Function()? ifRestrictedExecuteInstead,
  ErrorFilter? errorFilter,
  bool notifyOnlyWhenValueChanges = false,
  String? debugName,
})
```

**New signature**:
```dart
static Command<void, void> createSyncNoParamNoResult(
  void Function() action, {
  ValueListenable<bool>? restriction,
  void Function()? ifRestrictedExecuteInstead,
  ErrorFilter? errorFilter,
  ErrorFilterFn? errorFilterFn,  // ← Add this
  bool notifyOnlyWhenValueChanges = false,
  String? debugName,
})
```

**Constructor call update**:
```dart
return CommandSync<void, void>(
  funcNoParam: action,
  initialValue: null,
  restriction: restriction,
  ifRestrictedExecuteInstead: ifRestrictedExecuteInstead != null
      ? (_) => ifRestrictedExecuteInstead()
      : null,
  includeLastResultInCommandResults: false,
  noReturnValue: true,
  errorFilter: errorFilter,
  errorFilterFn: errorFilterFn,  // ← Add this
  notifyOnlyWhenValueChanges: notifyOnlyWhenValueChanges,
  name: debugName,
  noParamValue: true,
);
```

### Step 2.2-2.12: Repeat for Remaining 11 Methods

Apply same pattern to:

1. ✅ `createSyncNoParamNoResult` (line 800)
2. `createSyncNoResult<TParam>` (line 849)
3. `createSyncNoParam<TResult>` (line 898)
4. `createSync<TParam, TResult>` (line 952)
5. `createAsyncNoParamNoResult` (line 1000)
6. `createAsyncNoResult<TParam>` (line 1046)
7. `createAsyncNoParam<TResult>` (line 1092)
8. `createAsync<TParam, TResult>` (line 1142)
9. `createUndoableNoParamNoResult<TUndoState>` (line 1191)
10. `createUndoableNoResult<TParam, TUndoState>` (line 1244)
11. `createUndoableNoParam<TResult, TUndoState>` (line 1296)
12. `createUndoable<TParam, TResult, TUndoState>` (line 1352)

**Script to help** (can be run manually):
```bash
# Search for all factory methods
cd /home/escamoteur/dev/flutter_it/command_it
grep -n "static Command.*create" lib/command_it.dart
```

---

## Phase 3: Update CommandSync and CommandAsync Subclasses

**Files**: `lib/sync_command.dart`, `lib/async_command.dart`
**Time**: 20 minutes
**Status**: Not started

### Step 3.1: Update CommandSync constructor

**File**: `lib/sync_command.dart:13`

**Current code**:
```dart
CommandSync({
  TResult Function(TParam)? func,
  TResult Function()? funcNoParam,
  required super.initialValue,
  required super.restriction,
  required super.ifRestrictedExecuteInstead,
  required super.includeLastResultInCommandResults,
  required super.noReturnValue,
  required super.errorFilter,
  required super.notifyOnlyWhenValueChanges,
  required super.name,
  required super.noParamValue,
})  : _func = func,
      _funcNoParam = funcNoParam;
```

**New code**:
```dart
CommandSync({
  TResult Function(TParam)? func,
  TResult Function()? funcNoParam,
  required super.initialValue,
  required super.restriction,
  required super.ifRestrictedExecuteInstead,
  required super.includeLastResultInCommandResults,
  required super.noReturnValue,
  required super.errorFilter,
  required super.errorFilterFn,  // ← Add this
  required super.notifyOnlyWhenValueChanges,
  required super.name,
  required super.noParamValue,
})  : _func = func,
      _funcNoParam = funcNoParam;
```

### Step 3.2: Update CommandAsync constructor

**File**: `lib/async_command.dart:7`

Apply same change as CommandSync.

---

## Phase 4: Update UndoableCommand

**Files**: `lib/undoable_command.dart`
**Time**: 15 minutes
**Status**: Not started

### Step 4.1: Update UndoableCommand constructor

**Location**: `lib/undoable_command.dart:54`

**Current constructor parameters**:
```dart
UndoableCommand({
  // ... other params
  required super.errorFilter,
  // ... other params
})
```

**New constructor parameters**:
```dart
UndoableCommand({
  // ... other params
  required super.errorFilter,
  required super.errorFilterFn,  // ← Add this
  // ... other params
})
```

---

## Phase 5: Update MockCommand

**Files**: `lib/mock_command.dart`
**Time**: 10 minutes
**Status**: Not started

### Step 5.1: Update MockCommand constructor

**Location**: `lib/mock_command.dart:15`

Add `super.errorFilterFn` parameter similar to other subclasses.

---

## Phase 6: Add Comprehensive Tests

**Files**: `test/error_filter_function_test.dart` (new file)
**Time**: 1.5 hours
**Status**: Not started

### Step 6.1: Create new test file

**File**: `test/error_filter_function_test.dart`

```dart
// ignore_for_file: avoid_print

import 'package:command_it/command_it.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ErrorFilterFn - Basic Functionality', () {
    test('Function filter works with simple lambda', () async {
      int executionCount = 0;

      final command = Command.createAsync<void, int>(
        () async {
          executionCount++;
          throw Exception('Test error');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) {
          return error is Exception
              ? ErrorReaction.localHandler
              : null;
        },
      );

      bool errorHandlerCalled = false;
      command.errors.listen((error, _) {
        if (error != null) {
          errorHandlerCalled = true;
        }
      });

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(errorHandlerCalled, true);
      expect(executionCount, 1);
    });

    test('Function filter returns null for no match', () async {
      final command = Command.createAsync<void, int>(
        () async {
          throw ArgumentError('Test error');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) {
          // Only handle Exception, not ArgumentError
          return error is Exception && error is! ArgumentError
              ? ErrorReaction.localHandler
              : null;
        },
      );

      // Should fall back to default filter
      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      // Default behavior should apply
      expect(command.results.value.hasError, true);
    });

    test('Named function works as filter', () async {
      ErrorReaction? myFilter(Object error, StackTrace stackTrace) {
        if (error is TimeoutException) {
          return ErrorReaction.globalHandler;
        }
        return null;
      }

      bool globalHandlerCalled = false;
      Command.globalExceptionHandler = (error, stackTrace) {
        globalHandlerCalled = true;
      };

      final command = Command.createAsync<void, int>(
        () async {
          throw TimeoutException('Timeout');
        },
        initialValue: 0,
        errorFilterFn: myFilter,
      );

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(globalHandlerCalled, true);

      Command.globalExceptionHandler = null; // Cleanup
    });
  });

  group('ErrorFilterFn - Type Safety', () {
    test('Correct function signature compiles', () {
      // This should compile
      final command = Command.createAsync<void, int>(
        () async => 42,
        initialValue: 0,
        errorFilterFn: (Object error, StackTrace stackTrace) {
          return ErrorReaction.localHandler;
        },
      );

      expect(command, isNotNull);
    });

    test('Dynamic parameters work (covariant)', () {
      // dynamic is supertype of Object, should work
      final command = Command.createAsync<void, int>(
        () async => 42,
        initialValue: 0,
        errorFilterFn: (dynamic error, dynamic stackTrace) {
          return ErrorReaction.localHandler;
        },
      );

      expect(command, isNotNull);
    });

    // Note: Wrong signatures will cause compile errors, not runtime errors
    // These are tested by attempting to compile and verifying errors
  });

  group('ErrorFilterFn - Integration with ErrorFilter', () {
    test('Cannot provide both errorFilter and errorFilterFn', () {
      expect(
        () => Command.createAsync<void, int>(
          () async => 42,
          initialValue: 0,
          errorFilter: const ErrorHandlerLocal(),
          errorFilterFn: (e, s) => ErrorReaction.global,
        ),
        throwsAssertionError,
      );
    });

    test('errorFilter still works (backward compatibility)', () async {
      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilter: const ErrorHandlerLocal(),
      );

      bool errorHandlerCalled = false;
      command.errors.listen((error, _) {
        if (error != null) {
          errorHandlerCalled = true;
        }
      });

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(errorHandlerCalled, true);
    });

    test('errorFilterFn takes precedence when only it is provided', () async {
      bool functionFilterUsed = false;

      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) {
          functionFilterUsed = true;
          return ErrorReaction.localHandler;
        },
      );

      command.errors.listen((error, _) {});
      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(functionFilterUsed, true);
    });
  });

  group('ErrorFilterFn - All ErrorReaction Types', () {
    test('ErrorReaction.none works', () async {
      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) => ErrorReaction.none,
      );

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      // Error should be swallowed
      expect(command.results.value.hasError, false);
    });

    test('ErrorReaction.throwException works', () async {
      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) => ErrorReaction.throwException,
      );

      // Should rethrow
      expect(
        () => command.execute(),
        throwsA(isA<Exception>()),
      );
    });

    test('ErrorReaction.globalHandler works', () async {
      bool globalCalled = false;
      Command.globalExceptionHandler = (error, stackTrace) {
        globalCalled = true;
      };

      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) => ErrorReaction.globalHandler,
      );

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(globalCalled, true);

      Command.globalExceptionHandler = null; // Cleanup
    });

    test('ErrorReaction.localHandler works', () async {
      bool localCalled = false;

      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) => ErrorReaction.localHandler,
      );

      command.errors.listen((error, _) {
        if (error != null) localCalled = true;
      });

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(localCalled, true);
    });
  });

  group('ErrorFilterFn - Composition Patterns', () {
    test('Can compose multiple filter functions', () async {
      ErrorFilterFn filter1 = (e, s) =>
          e is TimeoutException ? ErrorReaction.global : null;
      ErrorFilterFn filter2 = (e, s) =>
          e is ArgumentError ? ErrorReaction.local : null;

      ErrorFilterFn combined = (e, s) => filter1(e, s) ?? filter2(e, s);

      final command = Command.createAsync<void, int>(
        () async {
          throw TimeoutException('Test');
        },
        initialValue: 0,
        errorFilterFn: combined,
      );

      bool globalCalled = false;
      Command.globalExceptionHandler = (error, stackTrace) {
        globalCalled = true;
      };

      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      expect(globalCalled, true);

      Command.globalExceptionHandler = null;
    });
  });

  group('ErrorFilterFn - Edge Cases', () {
    test('Null return falls back to default filter', () async {
      final command = Command.createAsync<void, int>(
        () async {
          throw Exception('Test');
        },
        initialValue: 0,
        errorFilterFn: (error, stackTrace) => null, // Always return null
      );

      command.errors.listen((error, _) {});
      command.execute();
      await Future.delayed(Duration(milliseconds: 100));

      // Default filter should handle it
      expect(command.results.value.hasError, true);
    });

    test('Function filter works with all command types', () {
      // Sync
      expect(
        () => Command.createSync<void, int>(
          (x) => 42,
          initialValue: 0,
          errorFilterFn: (e, s) => ErrorReaction.local,
        ),
        returnsNormally,
      );

      // Async
      expect(
        () => Command.createAsync<void, int>(
          (x) async => 42,
          initialValue: 0,
          errorFilterFn: (e, s) => ErrorReaction.local,
        ),
        returnsNormally,
      );

      // Undoable
      expect(
        () => Command.createUndoable<void, int, String>(
          (x, stack) async => 42,
          initialValue: 0,
          undo: (stack, result) async {},
          errorFilterFn: (e, s) => ErrorReaction.local,
        ),
        returnsNormally,
      );
    });
  });
}
```

### Step 6.2: Add tests to existing test file

**File**: `test/flutter_command_test.dart`

Add section at end:

```dart
group('ErrorFilterFn Integration Tests', () {
  test('Function filter integrates with existing error test infrastructure', () {
    // Use existing Collector pattern
    final Collector<CommandError> errorCollector = Collector<CommandError>();

    final command = Command.createAsync<void, int>(
      () async {
        throw CustomException('Test');
      },
      initialValue: 0,
      errorFilterFn: (error, stackTrace) {
        return error is CustomException
            ? ErrorReaction.localHandler
            : null;
      },
    );

    command.errors.listen((error, _) => errorCollector(error!));

    command.execute();
    // Test continues...
  });
});
```

---

## Phase 7: Add Helper Functions for Filter Composition

**Files**: `lib/error_filters.dart`
**Time**: 45 minutes
**Status**: Not started

### Step 7.1: Add combine function

**Location**: End of `lib/error_filters.dart`

```dart
/// Combines multiple [ErrorFilterFn] functions into one.
///
/// Returns the first non-null [ErrorReaction] from the list of filters.
/// If all filters return null, returns null (falls back to default).
///
/// Example:
/// ```dart
/// errorFilterFn: combine([
///   (e, s) => e is NetworkException ? ErrorReaction.global : null,
///   (e, s) => e is TimeoutException ? ErrorReaction.local : null,
///   (e, s) => ErrorReaction.firstLocalThenGlobalHandler, // Fallback
/// ])
/// ```
ErrorFilterFn combine(List<ErrorFilterFn> filters) {
  return (error, stackTrace) {
    for (final filter in filters) {
      final reaction = filter(error, stackTrace);
      if (reaction != null) return reaction;
    }
    return null;
  };
}

/// Converts an [ErrorFilter] object to [ErrorFilterFn] function.
///
/// Useful for mixing objects and functions in compositions.
///
/// Example:
/// ```dart
/// errorFilterFn: combine([
///   toFunction(const ErrorHandlerLocal()),
///   (e, s) => e is NetworkException ? ErrorReaction.global : null,
/// ])
/// ```
ErrorFilterFn toFunction(ErrorFilter filter) {
  return (error, stackTrace) {
    final reaction = filter.filter(error, stackTrace);
    return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
  };
}

/// Converts an [ErrorFilterFn] function to [ErrorFilter] object.
///
/// Useful if you need an object but have a function.
ErrorFilter toObject(ErrorFilterFn fn) {
  return _FunctionErrorFilter(fn);
}

class _FunctionErrorFilter implements ErrorFilter {
  final ErrorFilterFn fn;
  const _FunctionErrorFilter(this.fn);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return fn(error, stackTrace) ?? ErrorReaction.defaulErrorFilter;
  }
}

/// Creates a filter that only handles errors of type [T].
///
/// Example:
/// ```dart
/// errorFilterFn: typeFilter<NetworkException>(ErrorReaction.global)
/// ```
ErrorFilterFn typeFilter<T>(ErrorReaction reaction) {
  return (error, stackTrace) {
    return error is T ? reaction : null;
  };
}

/// Creates a filter that handles errors matching a predicate.
///
/// Example:
/// ```dart
/// errorFilterFn: predicateFilter(
///   (e) => e is NetworkException && e.statusCode == 401,
///   ErrorReaction.localHandler,
/// )
/// ```
ErrorFilterFn predicateFilter(
  bool Function(Object error) predicate,
  ErrorReaction reaction,
) {
  return (error, stackTrace) {
    return predicate(error) ? reaction : null;
  };
}
```

### Step 7.2: Export new helpers

**File**: `lib/command_it.dart`

Ensure these are exported:
```dart
export 'package:command_it/error_filters.dart';
```

Already exported, so new functions will be available automatically.

---

## Phase 8: Update Documentation

**Files**: `README.md`, `CHANGELOG.md`, inline docs
**Time**: 1 hour
**Status**: Not started

### Step 8.1: Update CHANGELOG.md

**Location**: Top of `CHANGELOG.md`

```markdown
## [8.1.0] - 2025-11-XX

### Added
- **Function-based error filters**: You can now pass error filter functions directly via the new `errorFilterFn` parameter
  ```dart
  // New: Function filter
  errorFilterFn: (error, stackTrace) =>
    error is NetworkException ? ErrorReaction.global : null

  // Still supported: Object filter
  errorFilter: const RetryErrorFilter(maxRetries: 3)
  ```
- New helper functions for filter composition:
  - `combine(List<ErrorFilterFn>)` - Combine multiple filters
  - `toFunction(ErrorFilter)` - Convert object to function
  - `toObject(ErrorFilterFn)` - Convert function to object
  - `typeFilter<T>(ErrorReaction)` - Type-based filtering
  - `predicateFilter(predicate, ErrorReaction)` - Predicate-based filtering
- Comprehensive compile-time type checking for function filters
- Function filters return `null` for "no match" instead of `ErrorReaction.defaulErrorFilter`

### Changed
- Internal error handling now uses function representation (transparent to users)
- Error filter resolution now supports both objects and functions

### Deprecated
- Nothing deprecated in this release (fully backward compatible)

### Fixed
- None

### Documentation
- Added section on function-based error filters to README
- Added examples showing both object and function approaches
- Updated API documentation with function filter signatures
```

### Step 8.2: Update README.md

**Location**: After "Error Handling" section (around line 264)

```markdown
### Error Filtering with Functions (New in v8.1.0)

In addition to error filter objects, you can now use functions for more concise error handling:

```dart
// Function filter - inline logic
final command = Command.createAsync<String, List<Data>>(
  fetchData,
  [],
  errorFilterFn: (error, stackTrace) {
    if (error is NetworkException) {
      if (error.statusCode == 401) {
        showLoginDialog();
        return ErrorReaction.localHandler;
      }
      return ErrorReaction.globalHandler;
    }
    return null; // No match, use default filter
  },
);
```

**When to use objects vs functions:**

Use `errorFilter` (objects) when:
- Filter has configuration parameters (e.g., `RetryErrorFilter(maxRetries: 3)`)
- Filter is reused across multiple commands
- You want const optimization

Use `errorFilterFn` (functions) when:
- One-off custom logic specific to this command
- Simple inline filtering is sufficient
- You prefer functional style

**Composition helpers:**

```dart
// Combine multiple filters
errorFilterFn: combine([
  typeFilter<NetworkException>(ErrorReaction.global),
  typeFilter<TimeoutException>(ErrorReaction.local),
  (e, s) => ErrorReaction.firstLocalThenGlobalHandler, // Fallback
])

// Mix objects and functions
errorFilterFn: combine([
  toFunction(const ErrorHandlerLocal()),
  (e, s) => e is NetworkException ? ErrorReaction.global : null,
])
```

For more details, see the [error filtering documentation](https://flutter-it.dev/documentation/command_it/error-handling).
```

### Step 8.3: Update factory method documentation

**Location**: Each factory method doc comment

Add to each factory method's documentation (template):

```dart
/// [errorFilter] : ErrorFilter object for reusable error handling logic.
/// [errorFilterFn] : Function for inline error handling logic.
/// You can provide either [errorFilter] OR [errorFilterFn], not both.
///
/// The function signature is:
/// ```dart
/// ErrorReaction? Function(Object error, StackTrace stackTrace)
/// ```
/// Return [ErrorReaction] to handle the error, or `null` to delegate to default filter.
```

---

## Phase 9: Run Tests and Fix Issues

**Time**: 1 hour
**Status**: Not started

### Step 9.1: Run existing tests

```bash
cd /home/escamoteur/dev/flutter_it/command_it
flutter test
```

**Expected**: All existing tests should pass (backward compatible change).

### Step 9.2: Run new tests

```bash
flutter test test/error_filter_function_test.dart
```

**Expected**: All new tests should pass.

### Step 9.3: Run analyzer

```bash
flutter analyze
```

**Expected**: No errors or warnings.

### Step 9.4: Format code

```bash
dart format lib/ test/
```

### Step 9.5: Check coverage

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

**Goal**: Maintain or improve existing coverage (~80%+).

---

## Phase 10: Final Steps

**Time**: 30 minutes
**Status**: Not started

### Step 10.1: Update pubspec.yaml version

**File**: `pubspec.yaml`

```yaml
version: 8.1.0
```

### Step 10.2: Verify examples compile

```bash
cd example
flutter analyze
flutter run --no-pub
```

### Step 10.3: Create example showing new feature

**File**: `example/lib/function_filter_example.dart` (new)

```dart
import 'package:command_it/command_it.dart';

void main() {
  // Example 1: Simple type-based filtering
  final simpleCommand = Command.createAsync<String, String>(
    (param) async {
      // Simulate network call that might fail
      throw NetworkException('Connection failed');
    },
    initialValue: '',
    errorFilterFn: (error, stackTrace) {
      return error is NetworkException
          ? ErrorReaction.globalHandler
          : null;
    },
  );

  // Example 2: Complex custom logic
  final complexCommand = Command.createAsync<String, String>(
    (param) async {
      throw CustomException(401, 'Unauthorized');
    },
    initialValue: '',
    errorFilterFn: (error, stackTrace) {
      if (error is CustomException) {
        if (error.statusCode == 401) {
          // Show login dialog
          return ErrorReaction.localHandler;
        }
        if (error.statusCode >= 500) {
          // Server error - log it
          return ErrorReaction.globalHandler;
        }
      }
      return null; // Use default handling
    },
  );

  // Example 3: Composition
  final composedCommand = Command.createAsync<String, String>(
    (param) async => 'Success',
    initialValue: '',
    errorFilterFn: combine([
      typeFilter<NetworkException>(ErrorReaction.global),
      typeFilter<TimeoutException>(ErrorReaction.local),
      predicateFilter(
        (e) => e.toString().contains('auth'),
        ErrorReaction.localHandler,
      ),
      (e, s) => ErrorReaction.firstLocalThenGlobalHandler, // Fallback
    ]),
  );
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}

class CustomException implements Exception {
  final int statusCode;
  final String message;
  CustomException(this.statusCode, this.message);
}
```

### Step 10.4: Git commit

```bash
git add .
git commit -m "Add function-based error filter support

- Add ErrorFilterFn typedef for type-safe function filters
- Add errorFilterFn parameter to all factory methods
- Add composition helpers (combine, typeFilter, predicateFilter)
- Add comprehensive tests for function filters
- Update documentation and examples
- Fully backward compatible (non-breaking change)

Closes #XXX"
```

### Step 10.5: Create PR or publish

If in separate branch:
```bash
git push origin feature/function-error-filters
# Create PR
```

Or if ready to publish:
```bash
flutter pub publish --dry-run
# Review
flutter pub publish
```

---

## Testing Checklist

Before marking complete:

- [ ] All existing tests pass
- [ ] New function filter tests pass
- [ ] Analyzer shows no errors/warnings
- [ ] Code is formatted
- [ ] Documentation updated
- [ ] CHANGELOG updated
- [ ] Examples compile and run
- [ ] Manual testing done:
  - [ ] Object filter still works
  - [ ] Function filter works
  - [ ] Compilation error for wrong signature
  - [ ] Both parameters assertion fires
  - [ ] Composition helpers work
  - [ ] Default filter fallback works

---

## Rollback Plan

If issues are discovered after deployment:

1. **Revert the commit** if breaking issues found
2. **Hotfix version**: If minor issues, create 8.1.1 patch
3. **Documentation only**: If just doc issues, update without version bump

---

## Time Estimates Summary

| Phase | Time | Complexity |
|-------|------|------------|
| Phase 1: Base class | 30 min | Medium |
| Phase 2: Factory methods | 60 min | Low (repetitive) |
| Phase 3: Subclasses | 20 min | Low |
| Phase 4: UndoableCommand | 15 min | Low |
| Phase 5: MockCommand | 10 min | Low |
| Phase 6: Tests | 90 min | Medium |
| Phase 7: Helpers | 45 min | Medium |
| Phase 8: Documentation | 60 min | Low |
| Phase 9: Testing & fixes | 60 min | Variable |
| Phase 10: Final steps | 30 min | Low |
| **Total** | **6.5 hours** | **Medium** |

---

## Dependencies

No new dependencies required. Uses existing:
- `flutter` SDK
- `listen_it` (already a dependency)
- `test` (dev dependency)

---

## Success Criteria

✅ Feature is complete when:
1. All factory methods accept `errorFilterFn` parameter
2. Type checking works at compile time
3. All existing tests pass
4. New tests added with >90% coverage of new code
5. Documentation includes examples
6. Helper functions available and documented
7. Backward compatible (no breaking changes)
8. Published to pub.dev as v8.1.0

---

## Notes

- This is a **non-breaking change** - all existing code continues to work
- Function filters are **additive** - objects are still first-class
- **No deprecations** in this version
- Future v9.0.0 can remove `defaulErrorFilter` enum value
