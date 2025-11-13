# Implementation Plan: v8.x Series

**Versions Covered**: v8.0.3 (patch), v8.1.0 (minor), v9.0.0 (major)
**Total Estimated Time**: 17.5-19.5 hours
**Status**: v8.0.3 complete, v8.1.0 pending

---

## Overview

This plan covers two releases incorporating both new features and critical fixes from the November 2025 code review:

### v8.0.3 - Critical Fixes (1.5 hours)
- Fix unsafe type casts
- Improve documentation of core methods
- Improve error handling documentation

### v8.1.0 - Feature Release (16-20 hours)
1. **Hybrid Error Filtering** - Function-based error filters with type safety
2. **Test Coverage** - Comprehensive tests for UndoableCommand, CommandBuilder, disposal
3. **Performance** - Optimize error handling and stack trace capture
4. **API Enhancements** - ErrorFilter composition utilities and common filters

### v9.0.0 - Breaking Changes (Future)
See `COMMAND_EXTENSIONS_DESIGN.md` and `API_PROPOSAL_v8.1_v9.0.md` for lifecycle hooks, ErrorHandlerRegistry, and RetryableCommand.

---

## v8.0.3: Critical Fixes (Code Review P0 Items)

**Estimated Time**: 1.5 hours
**Complexity**: Low
**Breaking Changes**: None

### Fix 1: Unsafe ValueNotifier Casts

**File**: `lib/command_it.dart`
**Lines**: 232, 236
**Time**: 5 minutes
**Severity**: HIGH - Runtime crash risk

**Current Code**:
```dart
_canExecute = (_restriction == null)
    ? _isExecuting.map((val) => !val) as ValueNotifier<bool>
    : _restriction.combineLatest<bool, bool>(
        _isExecuting,
        (restriction, isExecuting) => !restriction && !isExecuting,
      ) as ValueNotifier<bool>;
```

**Fix**: Change internal field type
```dart
// Line 555 - Change field type
late ValueListenable<bool> _canExecute;  // Was: ValueNotifier<bool>

// Lines 232, 236 - Remove casts
_canExecute = (_restriction == null)
    ? _isExecuting.map((val) => !val)
    : _restriction.combineLatest<bool, bool>(
        _isExecuting,
        (restriction, isExecuting) => !restriction && !isExecuting,
      );
```

**Impact**: None - getters already return ValueListenable<bool>

**Status**: ✅ COMPLETED

**Note on Future Completion Safety**: This fix was initially planned but rejected after analysis. The success and error paths are mutually exclusive (try/catch), and there's no code path that could complete the same future twice. Adding `isCompleted` checks would mask bugs (double disposal, reentrancy issues) that should fail loudly during development. The dispose path (line 538) legitimately has the check because it's cleanup code.

**Note on Print Statements**: MockCommand print statements were also considered for removal but rejected. They serve legitimate debugging purposes (execution confirmation + misconfiguration warnings) and are already marked as intentional with `// ignore: avoid_print`. Not worth the breaking change to MockCommand API.

---

### Fix 2: Add Documentation to execute() Method

**File**: `lib/command_it.dart`
**Line**: 245
**Time**: 30 minutes
**Severity**: MEDIUM - Critical method lacks docs
**Status**: ✅ COMPLETED

**Add comprehensive doc comment**:
```dart
/// Executes the wrapped command function with optional [param].
///
/// The execution follows this flow:
/// 1. Checks if command is disposed
/// 2. Validates restriction (if any)
/// 3. Ensures not already executing (async commands only)
/// 4. Executes wrapped function
/// 5. Updates all ValueListenables with results
/// 6. Handles any errors via ErrorFilter system
///
/// For async commands, this method:
/// - Sets [isExecuting] to true before execution
/// - Updates [results] with loading state
/// - Sets [isExecuting] to false after completion
///
/// For sync commands:
/// - Executes immediately
/// - No [isExecuting] updates (throws assertion if accessed)
///
/// Errors are handled according to [errorFilter] configuration.
/// See [ErrorReaction] for available error handling strategies.
///
/// Use [executeWithFuture] if you need to await the result.
void execute([TParam? param]) async {
  // ...
}
```

**Also document**: `_handleErrorFiltered`, `_mandatoryErrorHandling`, `_improveStacktrace`

---

### Fix 3: Document Error Handling Flow

**File**: `README.md`
**Time**: 1 hour
**Severity**: MEDIUM - Complex flow undocumented
**Status**: ✅ COMPLETED

**Add section after line ~264** (after Error Handling section):

```markdown
### Error Handling Flow

When a command throws an error, it flows through multiple stages:

```
Error Occurs in Command
  ↓
1. Mandatory Error Handling
   ├─ AssertionError? → Throw (if assertionsAlwaysThrow)
   ├─ reportAllExceptions? → Call globalExceptionHandler
   └─ Continue to filtering
  ↓
2. Error Filter Evaluation
   ├─ Call command's errorFilter
   ├─ If returns defaulErrorFilter → Use errorFilterDefault
   └─ Get ErrorReaction
  ↓
3. React Based on ErrorReaction
   ├─ none → Swallow error
   ├─ throwException → Rethrow
   ├─ localHandler → Notify .errors listeners
   ├─ globalHandler → Call globalExceptionHandler
   ├─ localAndGlobalHandler → Both
   ├─ firstLocalThenGlobalHandler → Local, fallback to global
   └─ ... (see ErrorReaction enum)
  ↓
4. Update State
   ├─ Push to .results (if configured)
   └─ Emit to .errors (if local handling)
```

**Key points:**
- Errors always update `.results.value.hasError`
- Local handlers subscribe to `.errors` ValueListenable
- Global handler is the static `Command.globalExceptionHandler`
- `ErrorFilter` controls routing, not handling
```

---

### v8.0.3 Summary

**Files Modified**: 2
- `lib/command_it.dart` (2 changes: unsafe casts, execute() documentation)
- `README.md` (2 changes: error handling config section, image URL fix)

**Breaking Changes**: None

**Testing**:
- All existing tests must pass
- No new tests required (fixes only)

---

## v8.1.0: Feature Release

**Estimated Time**: 16-20 hours
**Complexity**: Medium
**Breaking Changes**: None

This release contains three major areas:
1. **Hybrid Error Filtering** (6.5 hours) - Function-based error filters
2. **Test Coverage Improvements** (6-7 hours) - Fill gaps from code review
3. **Performance & API Enhancements** (3-4 hours) - Optimizations and utilities

---

## Part A: Hybrid Error Filtering (6.5 hours)

### Phase 1: Define Function Type and Update Command Base Class

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

### Hybrid Error Filtering Time Summary

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

## Part B: Test Coverage Improvements (6-7 hours)

**Goal**: Address critical test gaps identified in code review

### Test Suite 1: UndoableCommand Comprehensive Tests

**File**: `test/undoable_command_test.dart` (new file)
**Time**: 3-4 hours
**Coverage Target**: 90%+

**Tests to Add**:

1. **Undo operation error handling**
   ```dart
   test('Undo operation that throws exception', () async {
     // Verify error from undo operation is handled properly
     // Should it call error filter? Should it rollback?
   });
   ```

2. **Multiple undo operations**
   ```dart
   test('Multiple consecutive undo operations', () async {
     // Execute → undo → execute → undo → execute
     // Verify undo stack state at each step
   });

   test('Undo all operations until stack empty', () async {
     // Perform 5 executions, then 5 undos
     // Verify final state matches initial state
   });
   ```

3. **Undo stack limits**
   ```dart
   test('Undo stack overflow behavior', () async {
     // Execute 1000+ operations
     // Verify memory doesn't explode
     // Check oldest entries are removed
   });

   test('Undo stack with max size parameter', () async {
     // If we add maxUndoStackSize parameter
     // Verify circular buffer behavior
   });
   ```

4. **undoOnExecutionFailure variations**
   ```dart
   test('undoOnExecutionFailure = false, error occurs', () async {
     // Verify undo is NOT called
   });

   test('undoOnExecutionFailure = true, error occurs', () async {
     // Verify undo IS called
     // Verify undo state is pushed
   });
   ```

5. **Concurrent execution attempts**
   ```dart
   test('Attempt execution while previous execution pending', () async {
     // Should be blocked by isExecuting
   });

   test('Attempt undo while execution pending', () async {
     // What should happen? Error? Queue? Block?
   });
   ```

6. **Undo with complex state**
   ```dart
   test('Undo with large/complex TUndoState objects', () async {
     // Test serialization if needed
   });

   test('Undo callback receives correct state snapshot', () async {
     // Verify state passed to undo callback matches execution snapshot
   });
   ```

**Estimated Breakdown**:
- Test file setup: 30 min
- 6 test categories × 30 min each: 3 hours
- Edge case coverage: 30 min
- **Total**: 4 hours

---

### Test Suite 2: CommandBuilder Comprehensive Tests

**File**: `test/command_builder_test.dart` (expand existing)
**Time**: 2 hours
**Coverage Target**: 90%+

**Current State**: Only 1 minimal test exists (line 1162)

**Tests to Add**:

1. **State transition tests**
   ```dart
   testWidgets('Builder shows whileExecuting during execution', (tester) async {
     // Verify loading indicator appears
   });

   testWidgets('Builder shows onData after success', (tester) async {
     // Verify data widget appears with correct value
   });

   testWidgets('Builder shows onError after error', (tester) async {
     // Verify error widget appears with error object
   });

   testWidgets('Builder shows onSuccess for void commands', (tester) async {
     // Verify success widget for commands with no return value
   });
   ```

2. **Error cases**
   ```dart
   testWidgets('Builder with no onData or onSuccess throws', (tester) async {
     // Currently assertion-only, should be runtime error
   });

   testWidgets('Builder handles null lastValue correctly', (tester) async {
     // First execution, no previous value
   });
   ```

3. **includeLastResultInCommandResults**
   ```dart
   testWidgets('Builder retains last value during error', (tester) async {
     // Show stale data with error indicator
   });

   testWidgets('Builder retains last value during loading', (tester) async {
     // Show stale data with loading indicator
   });
   ```

4. **Rebuild optimization**
   ```dart
   testWidgets('Builder only rebuilds when command state changes', (tester) async {
     // Verify no unnecessary rebuilds
   });
   ```

**Estimated Breakdown**:
- Expand test file: 15 min
- 4 test categories × 30 min each: 2 hours
- **Total**: 2 hours

---

### Test Suite 3: Disposal Edge Cases

**File**: `test/disposal_test.dart` (new file)
**Time**: 1 hour
**Coverage Target**: 95%+

**Tests to Add**:

1. **Dispose during execution**
   ```dart
   test('Dispose async command while executing', () async {
     // Start long-running command
     // Dispose command
     // Verify: isDisposing flag prevents notifications
     // Verify: Future completion handled gracefully
   });

   test('Dispose sync command (immediate)', () {
     // Verify disposal completes immediately
   });
   ```

2. **Double disposal**
   ```dart
   test('Call dispose() twice', () {
     // Should not throw
     // Should not dispose twice
   });
   ```

3. **Access after disposal**
   ```dart
   test('Execute after disposal throws', () {
     // Should throw clear error
   });

   test('Read properties after disposal', () {
     // What happens? Throw? Return stale? Define behavior
   });
   ```

4. **Listener memory leaks**
   ```dart
   test('Listeners cleaned up after disposal', () async {
     // Add 100 listeners
     // Dispose command
     // Verify all listeners removed (no memory leak)
     // Use package:leak_tracker if available
   });
   ```

**Estimated Breakdown**:
- Test file setup: 15 min
- 4 test categories × 15 min each: 45 min
- **Total**: 1 hour

---

### Test Suite 4: Performance/Stress Tests (Optional)

**File**: `test/performance_test.dart` (new file)
**Time**: 1 hour (if included)
**Coverage Target**: N/A (performance benchmarks)

**Tests to Add**:

1. **Rapid execution**
   ```dart
   test('1000 rapid executions complete successfully', () async {
     // Stress test ValueListenable notifications
   });
   ```

2. **Many listeners**
   ```dart
   test('100 concurrent listeners on one command', () async {
     // Verify no performance degradation
   });
   ```

3. **Large parameters/results**
   ```dart
   test('Command with 10MB parameter object', () async {
     // Verify memory handling
   });
   ```

4. **Memory leak detection**
   ```dart
   test('No memory leaks after 1000 command create/dispose cycles', () async {
     // Create command, use it, dispose, repeat
     // Monitor memory usage
   });
   ```

**Note**: These tests require performance monitoring infrastructure. Consider optional for v8.1.0.

---

### Test Coverage Summary

| Test Suite | Time | Priority | New Tests |
|------------|------|----------|-----------|
| UndoableCommand | 4 hours | **High** | ~15 tests |
| CommandBuilder | 2 hours | **High** | ~8 tests |
| Disposal | 1 hour | **High** | ~6 tests |
| Performance | 1 hour | Low (optional) | ~4 tests |
| **Total** | **6-7 hours** | - | **~30 tests** |

---

## Part C: Performance & API Enhancements (3-4 hours)

**Goal**: Optimize hot paths and add missing ErrorFilter utilities

### Enhancement 1: Optimize Exception Type Checking

**File**: `lib/error_filters.dart`
**Line**: 117
**Time**: 15 minutes
**Impact**: Eliminates object allocation on every error

**Current Code** (creates Exception on every call):
```dart
@override
ErrorReaction filter(Object error, StackTrace stackTrace) {
  if (error.runtimeType == Exception().runtimeType) {  // ← Bad!
    return _table[Exception] ?? ErrorReaction.firstLocalThenGlobalHandler;
  }
  return _table[error.runtimeType] ?? ErrorReaction.defaulErrorFilter;
}
```

**Optimized Code**:
```dart
class TableErrorFilter implements ErrorFilter {
  static final _exceptionRuntimeType = Exception().runtimeType;  // ← Cached

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error.runtimeType == _exceptionRuntimeType) {
      return _table[Exception] ?? ErrorReaction.firstLocalThenGlobalHandler;
    }
    return _table[error.runtimeType] ?? ErrorReaction.defaulErrorFilter;
  }
}
```

---

### Enhancement 2: Make Stack Trace Capture Lazy

**File**: `lib/command_it.dart`
**Line**: 253
**Time**: 1 hour
**Impact**: Reduces overhead when detailed traces not needed

**Current Code** (always captures if enabled):
```dart
if (Command.detailedStackTraces) {
  _traceBeforeExecute = Trace.current();  // ← Always happens
}
```

**Options**:

**Option A: Lazy capture**
```dart
// Don't capture unless error occurs
Trace? _getCapturedTrace() {
  if (Command.detailedStackTraces && _traceBeforeExecute != null) {
    return _traceBeforeExecute;
  } else if (Command.detailedStackTraces) {
    // Capture now (late, but better than nothing)
    return Trace.current();
  }
  return null;
}
```

**Option B: Lite mode**
```dart
static bool detailedStackTraces = true;
static bool liteStackTraces = false;  // NEW: Capture only on error

// In execute():
if (Command.detailedStackTraces && !Command.liteStackTraces) {
  _traceBeforeExecute = Trace.current();
}
```

**Recommendation**: Option B (lite mode) - opt-in performance boost

**Testing**: Measure before/after performance in tight loop

---

### Enhancement 3: ErrorFilter Composition Utilities

**File**: `lib/error_filters.dart`
**Time**: 1.5 hours
**Impact**: Make complex filters easier to build

**Add composition helpers** (already partially in plan Phase 7):

```dart
/// Combines multiple ErrorFilterFn functions with OR logic.
/// Returns first non-null reaction, or null if all return null.
ErrorFilterFn combineOr(List<ErrorFilterFn> filters) {
  return (error, stackTrace) {
    for (final filter in filters) {
      final reaction = filter(error, stackTrace);
      if (reaction != null) return reaction;
    }
    return null;
  };
}

/// Combines multiple ErrorFilterFn functions with AND logic.
/// All filters must agree (return same reaction) to match.
ErrorFilterFn combineAnd(List<ErrorFilterFn> filters) {
  return (error, stackTrace) {
    ErrorReaction? agreed;
    for (final filter in filters) {
      final reaction = filter(error, stackTrace);
      if (reaction == null) return null;  // One said no
      if (agreed == null) {
        agreed = reaction;
      } else if (agreed != reaction) {
        return null;  // Disagreement
      }
    }
    return agreed;
  };
}

/// Inverts a filter (NOT logic).
ErrorFilterFn not(ErrorFilterFn filter, ErrorReaction elseReaction) {
  return (error, stackTrace) {
    final reaction = filter(error, stackTrace);
    return reaction == null ? elseReaction : null;
  };
}
```

**Add tests** for composition logic (30 min)

---

### Enhancement 4: Common Error Filters

**File**: `lib/error_filters.dart`
**Time**: 45 minutes
**Impact**: Reduce boilerplate for common cases

**Add built-in filters for common scenarios**:

```dart
/// Filter for network-related errors.
class NetworkErrorFilter implements ErrorFilter {
  final ErrorReaction reaction;

  const NetworkErrorFilter({
    this.reaction = ErrorReaction.globalHandler,
  });

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is SocketException ||
        error is HttpException ||
        error.runtimeType.toString().contains('Network')) {
      return reaction;
    }
    return ErrorReaction.defaulErrorFilter;
  }
}

/// Filter for timeout errors.
class TimeoutErrorFilter implements ErrorFilter {
  final ErrorReaction reaction;

  const TimeoutErrorFilter({
    this.reaction = ErrorReaction.localHandler,
  });

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is TimeoutException) {
      return reaction;
    }
    return ErrorReaction.defaulErrorFilter;
  }
}

/// Filter for validation/argument errors.
class ValidationErrorFilter implements ErrorFilter {
  final ErrorReaction reaction;

  const ValidationErrorFilter({
    this.reaction = ErrorReaction.localHandler,
  });

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ArgumentError ||
        error is FormatException ||
        error is RangeError) {
      return reaction;
    }
    return ErrorReaction.defaulErrorFilter;
  }
}
```

**Add tests** for each filter (15 min)

---

### Performance & API Time Summary

| Enhancement | Time | Impact |
|-------------|------|--------|
| Exception type caching | 15 min | Low |
| Lazy stack traces | 1 hour | Medium |
| Composition utilities | 1.5 hours | High (usability) |
| Common error filters | 45 min | Medium (usability) |
| **Total** | **3-4 hours** | - |

---

## Dependencies

No new dependencies required. Uses existing:
- `flutter` SDK
- `listen_it` (already a dependency)
- `test` (dev dependency)

---

## v8.x Series: Complete Time Breakdown

### v8.0.3 (Patch Release)
| Task | Time |
|------|------|
| Fix unsafe casts | 5 min |
| Fix Future completion | 10 min |
| Remove print statements | 20 min |
| Document execute() | 30 min |
| Document error flow (README) | 1 hour |
| Remove deprecated code | 10 min |
| **Total** | **~2-3 hours** |

### v8.1.0 (Minor Release)
| Part | Time |
|------|------|
| Part A: Hybrid Error Filtering | 6.5 hours |
| Part B: Test Coverage | 6-7 hours |
| Part C: Performance & Enhancements | 3-4 hours |
| **Total** | **16-20 hours** |

### Grand Total: 18-23 hours

---

## Success Criteria

### v8.0.3
✅ Patch complete when:
1. All 6 critical fixes implemented
2. All existing tests pass
3. Documentation improved
4. Published to pub.dev

### v8.1.0
✅ Minor release complete when:
1. All factory methods accept `errorFilterFn` parameter
2. Type checking works at compile time
3. All existing tests pass
4. **30+ new tests added** with >90% coverage
5. **UndoableCommand**, **CommandBuilder**, **disposal** fully tested
6. Performance optimizations implemented
7. ErrorFilter composition utilities available
8. Common error filters implemented
9. Documentation includes examples for all new features
10. Helper functions available and documented
11. Backward compatible (no breaking changes)
12. Published to pub.dev as v8.1.0

---

## Implementation Order

**Recommended sequence:**

1. **v8.0.3 first** (2-3 hours) - Critical fixes
   - Get clean foundation
   - Improve documentation
   - Remove technical debt

2. **v8.1.0 Part A** (6.5 hours) - Hybrid error filtering
   - Core feature implementation
   - Enables function-based filters

3. **v8.1.0 Part C** (3-4 hours) - Performance & utilities
   - While hybrid filtering fresh in mind
   - Common filters use new errorFilterFn

4. **v8.1.0 Part B** (6-7 hours) - Test coverage
   - Test everything together
   - Catch integration issues
   - Stress test the complete package

**Total timeline**: Can be done in 2-3 dedicated days or 1-2 weeks part-time.

---

## Notes

### v8.0.3
- **Non-breaking** except for deprecated code removal
- MockCommand signature change only affects test code
- Safe to deploy immediately

### v8.1.0
- **Non-breaking** - all features are additive
- Function filters complement objects, don't replace them
- **No deprecations** in this version
- Maintains 100% backward compatibility
- Sets foundation for v9.0.0 breaking changes

### Future v9.0.0 Breaking Changes
- See `COMMAND_EXTENSIONS_DESIGN.md` for lifecycle hooks
- See `API_PROPOSAL_v8.1_v9.0.md` for complete API
- Will include ErrorHandlerRegistry, RetryableCommand, and lifecycle hooks
- Can remove typos (`defaulErrorFilter` → `defaultErrorFilter`)
- Can simplify factory method proliferation
- **Remove deprecated `debugErrorsThrowAlways`** (deprecated since v8.0.0 - July 2025, ~4 months)
  - Lines 369-371: Remove usage in error handling
  - Lines 471-474: Remove field declaration
  - Migration: Use `reportAllExceptions` instead
