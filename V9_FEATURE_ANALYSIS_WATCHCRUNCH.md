# v9.0 Feature Analysis - WatchCrunch Case Study

**Source**: Production Flutter app with 164 command instances
**Date**: November 2025
**Purpose**: Evaluate planned v9.0 features against real-world usage patterns

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Pain Points Analysis](#pain-points-analysis)
3. [Planned Features Evaluation](#planned-features-evaluation)
4. [Features NOT Addressed by v9.0](#features-not-addressed-by-v90)
5. [Recommended Design Changes](#recommended-design-changes)
6. [Impact Assessment](#impact-assessment)
7. [Before/After Examples](#beforeafter-examples)
8. [Breaking vs Non-Breaking Changes](#breaking-vs-non-breaking-changes)

---

## Executive Summary

### Key Findings

The WatchCrunch mobile app reveals that **current v9.0 design addresses ~60% of identified pain points**, but misses critical opportunities:

**✅ What v9.0 Gets Right**:
- ErrorHandlerRegistry solves type-based routing (eliminates custom filter classes)
- Lifecycle hooks provide declarative approach (but design needs refinement)
- Pattern-based matching is good architectural choice

**⚠️ What v9.0 Misses**:
1. **No unified error handling** - errorFilter + listener pattern still exists
2. **No context access** - Error handlers can't access BuildContext for localization
3. **No standard error filters** - 80% of custom filters could be built-in
4. **No optimistic update helper** - Undoable commands still require boilerplate
5. **RetryableCommand solves wrong problem** - Zero commands in app need automatic retry

**💡 Top Recommendations**:
1. Add `onError` callback parameter to replace errorFilter + error listener
2. Add context injection mechanism for error handlers
3. Include 6-8 standard error filters in the package
4. Add `Command.createOptimistic<T>()` factory for undoable commands
5. Make RetryableCommand opt-in, not core feature (low demand)

### Impact Summary

**Current Pain**:
- 63 error listeners with repetitive code (~315 lines of boilerplate)
- 8 custom error filter classes (~200 lines)
- 20+ undoable commands with manual snapshot/restore (~300 lines)
- ~64 commands missing debugName (harder debugging)

**Potential with v9.0 + Recommendations**:
- **50-60% reduction** in error handling boilerplate
- **75% reduction** in custom filter code
- **40% reduction** in undoable command boilerplate
- **100% coverage** of debug names

---

## Pain Points Analysis

### Pain Point 1: Boilerplate Error Listeners ⭐⭐⭐⭐⭐

**Impact**: Critical (affects 63/164 commands, ~38%)

**Current State**:
```dart
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  _deletePaymentMethod,
  errorFilter: const Api404ToSentry403LocalErrorFilter(),
)..errors.listen((ex, _) {
  final context = di<InteractionManager>().stableContext;
  handleMarketplaceApiError(
    ex,
    custom404Message: context.l10n.paymentMethodNotFound,
    custom403GenericMessage: context.l10n.cannotDeletePaymentMethod,
  );
});
```

**Problems**:
- errorFilter and error listener are disconnected
- Need to access external context service
- Repeated pattern across 30+ marketplace commands
- 5-8 lines of boilerplate per command

**v9.0 Lifecycle Hooks Help?**: ⚠️ Partial

The `onBeforeError` hook helps but still has issues:
```dart
// v9.0 approach
Command.addBeforeErrorHook(
  when: (cmd) => cmd.name?.contains('marketplace'),
  hook: (cmd, error, stack, param) {
    if (error is ApiException) {
      // 🚫 NO ACCESS TO CONTEXT for localization!
      // 🚫 NO ACCESS TO COMMAND-SPECIFIC MESSAGES
      return null;
    }
  },
);
```

**What's Needed**: Unified error handling with context access

### Pain Point 2: Custom Error Filter Classes ⭐⭐⭐⭐

**Impact**: High (8 custom classes, used in 75+ commands)

**Current State**:
```dart
// Custom filter for marketplace operations
class Api404ToSentry403LocalErrorFilter implements ErrorFilter {
  const Api404ToSentry403LocalErrorFilter();

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    _reportDeserializationError(error);
    _checkForLockedAccountState(error);

    if (error is ApiException) {
      if (error.code == 404) {
        return ErrorReaction.localAndGlobalHandler;
      } else if (error.code == 403) {
        return ErrorReaction.localHandler;
      }
    }

    return ErrorReaction.globalHandler;
  }
}
```

Used in 10+ commands for marketplace operations.

**v9.0 ErrorHandlerRegistry Help?**: ⚠️ Partial

ErrorHandlerRegistry handles type-based routing but not status codes:
```dart
// v9.0 approach
Command.errorRegistry.on<ApiException>((error, context) {
  // 🚫 Can't distinguish 404 vs 403 in handler signature
  // Need to check status code inside handler
});
```

**What's Needed**: Built-in status code filters + ErrorHandlerRegistry for types

### Pain Point 3: Optimistic Update Boilerplate ⭐⭐⭐⭐

**Impact**: High (20+ undoable commands, ~15 lines each)

**Current State**:
```dart
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<int>(
  () async {
    final favoriteCountSnapshot = favoriteCount;  // 1. Snapshot

    // 2. Optimistic update
    _isFavoriteOverride = !isFavorite;
    notifyListeners();

    // 3. API call
    await api.toggleFavorite(id);

    // 4. Return snapshot
    return favoriteCountSnapshot;
  },
  undo: (stack, error) {
    // 5. Restore snapshot
    final originalCount = stack.pop();
    _favoriteCountOverride = originalCount;
    _isFavoriteOverride = null;
    notifyListeners();
  },
);
```

**Problems**:
- Manual snapshot/restore (6 lines of boilerplate)
- Easy to forget `notifyListeners()` calls
- Snapshot logic scattered between execute and undo
- No type safety on snapshot structure

**v9.0 Help?**: ❌ Not addressed

RetryableCommand is about retrying on failure, not optimistic updates.

**What's Needed**: Helper for optimistic pattern with automatic state tracking

### Pain Point 4: Context Access in Error Handlers ⭐⭐⭐⭐

**Impact**: High (affects all error handlers that need localized messages)

**Current Workarounds**:
1. Global `InteractionManager.stableContext` service
2. Pass context as command parameter
3. Store context in widget/manager

**Problems with Each**:
- StableContext: Not available during initialization, can be stale
- Parameter: Clutters API, context may be stale on completion
- Storage: Memory leaks if not careful

**Example**:
```dart
)..errors.listen((error, _) {
  final context = di<InteractionManager>().stableContext; // 🚫 External dependency
  showToast(context, context.l10n.errorMessage);
});
```

**v9.0 ErrorHandlerRegistry Help?**: ❌ No

CommandError context parameter doesn't include BuildContext:
```dart
Command.errorRegistry.on<ApiException>((error, context) {
  // context is CommandError, not BuildContext!
  // 🚫 Can't access localization
});
```

**What's Needed**: Context injection mechanism for error handlers

### Pain Point 5: No Built-in Retry Logic ⭐⭐

**Impact**: Medium (affects user experience, but zero commands currently retry)

**Reality Check**: **0 out of 164 commands use retry logic**

**Why?**:
- Most errors are non-retryable (403, 404, 422)
- Network errors are rare in production
- Retry adds complexity users don't want
- Manual retry via "try again" button is sufficient

**v9.0 RetryableCommand**: ✅ Good feature, but lower priority than expected

The decorator pattern is well-designed, but demand is low. Real-world usage suggests:
- Retry is opt-in for specific scenarios (background sync, critical operations)
- Most commands don't need automatic retry
- User-initiated retry (button) is more common

**Recommendation**: Keep RetryableCommand but don't prioritize over other features

### Pain Point 6: Command Error Merging ⭐⭐⭐

**Impact**: Medium (6-8 instances of merging errors from multiple commands)

**Current Pattern**:
```dart
class PostProxy extends ChangeNotifier {
  late final ValueListenable<CommandError?> _commandErrors;
  late final StreamSubscription _errorSubscription;

  PostProxy() {
    // Merge errors from 6 different commands
    _commandErrors = pollVoteCommand.errorsDynamic.mergeWith([
      toggleInterestedCommand.errorsDynamic,
      toggleAttendCommand.errorsDynamic,
      toggleFavoriteCommand.errorsDynamic,
      togglePinnedCommand.errorsDynamic,
      toggleReactionCommand.errorsDynamic,
    ]);

    _errorSubscription = _commandErrors.listen((ex, sub) {
      if (ex!.error is ApiException) {
        final error = ex.error as ApiException;
        if (error.code == 403 || error.code == 404) {
          handlePostAccessError(error);
        }
      }
    });
  }

  @override
  void dispose() {
    _errorSubscription.cancel();
    // ... dispose all commands
    super.dispose();
  }
}
```

**Problems**:
- Manual merging with listen_it
- Subscription management
- Repeated pattern across proxy classes

**v9.0 Help?**: ❌ Not addressed

**What's Needed**: CommandGroup or similar abstraction

### Pain Point 7: Debug Name Coverage ⭐⭐⭐

**Impact**: Medium (affects debugging and crash reporting)

**Current State**: ~60% have debugName, ~40% don't

**v9.0 Help?**: ❌ Not addressed

**What's Needed**: Automatic name generation or required parameter

---

## Planned Features Evaluation

### Feature 1: ErrorHandlerRegistry ✅ Helpful

**What It Solves**:
- Type-based error routing
- Priority-based handler execution
- Eliminates some custom filter classes

**Example**:
```dart
// Instead of custom filter for auth errors
Command.errorRegistry.on<AuthException>((error, context) {
  showLoginDialog();
});

Command.errorRegistry.on<UnauthorizedException>((error, context) {
  showAuthRequiredModal();
});
```

**Impact**: Would eliminate ~2-3 of the 8 custom filter classes

**What It Doesn't Solve**:
- HTTP status code routing (404 vs 403 have different meanings)
- Command-specific error messages
- Context access for localization
- Still need errorFilter parameter on commands

**Grade**: B+ (Good, but incomplete)

### Feature 2: RetryableCommand ⚠️ Over-Engineered

**What It Solves**:
- Automatic retry with exponential backoff
- Fallback to different APIs
- Batch size reduction on timeout

**Reality**: Zero commands in WatchCrunch use retry

**Why?**:
- Most API errors are permanent (403, 404, 422)
- Network transient errors are rare
- Users prefer manual "try again" button
- Automatic retry can be confusing UX

**Example of what's actually needed**:
```dart
// Not automatic retry, but user-initiated retry
RefreshIndicator(
  onRefresh: () => command.executeWithFuture(), // Manual retry
  child: ...,
)

// Or retry button in error UI
ElevatedButton(
  onPressed: () => command.execute(lastParam), // Manual retry
  child: Text('Try Again'),
)
```

**Recommendation**:
- Keep RetryableCommand as optional decorator
- Don't prioritize over more pressing needs
- Consider simpler API: `retry: RetryPolicy.exponential()`

**Grade**: C+ (Well-designed, but low demand)

### Feature 3: Lifecycle Hooks ⚠️ Good Concept, Needs Refinement

**What It Solves**:
- Declarative execution guards
- Result validation
- Error recovery
- Analytics/logging

**Current Design Issues**:

#### Issue 1: No Context Access
```dart
Command.addBeforeErrorHook(
  when: (cmd) => cmd.name?.startsWith('marketplace'),
  hook: (cmd, error, stack, param) {
    // 🚫 Can't access BuildContext for localization
    // 🚫 Can't show localized toast
    return null;
  },
);
```

#### Issue 2: Pattern Matching vs Command-Specific Handlers

Pattern matching works for cross-cutting concerns:
```dart
Command.addBeforeExecuteHook(
  when: (cmd) => cmd.name?.startsWith('admin'),
  hook: (cmd, param) {
    if (!authService.isAdmin) throw PermissionDeniedException();
  },
);
```

But 90% of error handling is **command-specific**, not pattern-based:
```dart
// This is the actual pattern in WatchCrunch (63 instances)
deletePaymentMethodCommand..errors.listen((error, _) {
  // Command-specific error handling
  if (error.code == 404) {
    showToast(context.l10n.paymentMethodNotFound); // Specific message
  }
});
```

**Recommendation**:
- Keep pattern-based hooks for cross-cutting concerns (auth, logging)
- Add command-level callbacks for command-specific handling
- Provide context injection

**Grade**: B- (Right direction, implementation needs work)

---

## Features NOT Addressed by v9.0

### 1. Unified Error Handling (Critical) ⭐⭐⭐⭐⭐

**Problem**: errorFilter + error listener are disconnected

**Current**:
```dart
errorFilter: const Api404ToSentry403LocalErrorFilter(),
)..errors.listen((ex, _) {
  // Disconnected from filter, no type relationship
  handleError(ex);
});
```

**What's Needed**: Single `onError` callback
```dart
onError: (error, context) {
  if (error is ApiException) {
    switch (error.code) {
      case 404:
        showToast(context, context.l10n.notFound);
        return ErrorAction.alsoLogToSentry;
      case 403:
        showToast(context, context.l10n.forbidden);
        return ErrorAction.handled;
    }
  }
  return ErrorAction.useGlobalHandler;
}
```

**Impact**: Would eliminate ~315 lines of boilerplate (63 listeners × 5 lines avg)

### 2. Standard Error Filter Library (High Priority) ⭐⭐⭐⭐

**Problem**: 80% of custom filters follow common patterns

**What's Needed**:
```dart
// Built-in filters
ErrorFilter.onStatusCode(404, ErrorReaction.localHandler)
ErrorFilter.onStatusCodes({404: local, 403: local, 422: local})
ErrorFilter.localOnly
ErrorFilter.globalOnly
ErrorFilter.when(condition: () => ..., then: ..., otherwise: ...)
```

**Impact**: Would eliminate 6 of 8 custom filter classes (~150 lines)

### 3. Optimistic Update Helper (High Priority) ⭐⭐⭐⭐

**Problem**: Manual snapshot/restore is error-prone

**What's Needed**:
```dart
Command.createOptimistic<int>(
  execute: (currentCount) async {
    return await api.toggleFavorite(id);
  },
  optimisticValue: (currentCount) => currentCount + 1,
  stateNotifier: _favoriteCount, // Automatic snapshot/restore
)
```

**Impact**: Would reduce undoable command boilerplate by ~40%

### 4. Command Groups (Medium Priority) ⭐⭐⭐

**Problem**: Manually merging errors from related commands

**What's Needed**:
```dart
final postCommands = CommandGroup([
  pollVoteCommand,
  toggleFavoriteCommand,
  togglePinnedCommand,
]);

// Automatic merged errors
postCommands.errors.listen((error, _) {
  handlePostError(error);
});
```

**Impact**: Would simplify 6-8 proxy classes

### 5. Automatic Debug Names (Medium Priority) ⭐⭐⭐

**Problem**: Easy to forget debugName parameter

**What's Needed**:
```dart
// Option A: Macro/analyzer
late final loadUserCommand = Command.createAsync(...); // Auto-named 'loadUserCommand'

// Option B: Required parameter with lint rule
late final loadUserCommand = Command.createAsync(
  ...,
  debugName: 'loadUser', // ❌ Lint error if omitted
);
```

**Impact**: 100% coverage vs current 60%

### 6. Context-Aware Error Handling (Critical) ⭐⭐⭐⭐⭐

**Problem**: Error handlers need BuildContext for localization

**What's Needed**:
```dart
// Option A: Context injection
Command.setContextProvider(() => navigatorKey.currentContext);

Command.errorRegistry.on<ApiException>((error, cmdContext, buildContext) {
  showToast(buildContext, buildContext.l10n.errorMessage);
});

// Option B: Deferred execution
late final command = Command.createAsync(
  ...,
  onError: (error) => (context) {
    // Executed when error occurs with current context
    showToast(context, context.l10n.error);
  },
);
```

**Impact**: Eliminates dependency on global context service

---

## Recommended Design Changes

### Recommendation 1: Add onError Callback (Breaking)

**Replace**: errorFilter + error listener pattern
**With**: Single onError callback

```dart
// Current (v8.1)
late final command = Command.createAsync(
  _execute,
  null,
  errorFilter: const ErrorHandlerLocal(),
)..errors.listen((error, _) {
  handleError(error);
});

// Proposed (v9.0/v10.0)
late final command = Command.createAsync(
  _execute,
  null,
  onError: (error, context) {
    handleError(error);
    return ErrorAction.handled;
  },
);
```

**Benefits**:
- Unified error handling
- Type-safe error → action mapping
- Access to BuildContext
- Cleaner API

**Migration Path**:
- v9.0: Add onError, keep errorFilter + errors deprecated
- v10.0: Remove errorFilter + errors stream

### Recommendation 2: Add Standard Filter Library (Non-Breaking)

**Add to command_it**:

```dart
abstract class ErrorFilter {
  // Existing method
  ErrorReaction filter(Object error, StackTrace stackTrace);

  // NEW: Factory constructors
  factory ErrorFilter.onStatusCode(int code, ErrorReaction reaction) = ...;
  factory ErrorFilter.onStatusCodes(Map<int, ErrorReaction> map) = ...;
  factory ErrorFilter.onErrorType<T>(ErrorReaction reaction) = ...;
  factory ErrorFilter.localOnly() = LocalOnlyErrorFilter;
  factory ErrorFilter.globalOnly() = GlobalOnlyErrorFilter;
  factory ErrorFilter.predicates(List<...> predicates) = PredicatesErrorFilter;
}
```

**Impact**: Immediate reduction in custom filter code

### Recommendation 3: Add Optimistic Command Factory (Non-Breaking)

**Add new factory method**:

```dart
class Command {
  static Command<void, TResult> createOptimistic<TResult>({
    required Future<TResult> Function() execute,
    required TResult Function(TResult current) optimisticValue,
    required ValueNotifier<TResult> stateNotifier,
  }) {
    return Command.createUndoableNoParam<TResult, TResult>(
      () async {
        final snapshot = stateNotifier.value;
        stateNotifier.value = optimisticValue(snapshot);
        final result = await execute();
        stateNotifier.value = result;
        return snapshot;
      },
      undo: (stack, error) {
        stateNotifier.value = stack.pop();
      },
      stateNotifier.value,
    );
  }
}
```

**Usage**:
```dart
late final toggleFavoriteCommand = Command.createOptimistic<int>(
  execute: () => api.toggleFavorite(id),
  optimisticValue: (current) => current + 1,
  stateNotifier: _favoriteCount,
);
```

### Recommendation 4: Add Context Injection (Non-Breaking)

**Add global context provider**:

```dart
class Command {
  static BuildContext? Function()? _contextProvider;

  static void setContextProvider(BuildContext? Function() provider) {
    _contextProvider = provider;
  }

  static BuildContext? get currentContext => _contextProvider?.call();
}
```

**Usage**:
```dart
// Setup in main()
void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  Command.setContextProvider(() => navigatorKey.currentContext);

  runApp(MyApp(navigatorKey: navigatorKey));
}

// Use in error handlers
Command.errorRegistry.on<ApiException>((error, cmdContext) {
  final context = Command.currentContext;
  if (context != null) {
    showToast(context, context.l10n.errorMessage);
  }
});
```

### Recommendation 5: Make Lifecycle Hooks Per-Command (Non-Breaking)

**Add callback parameters to factory methods**:

```dart
Command.createAsync<TParam, TResult>(
  func,
  initialValue,
  {
    // NEW: Per-command lifecycle callbacks
    void Function(TParam? param)? onBeforeExecute,
    void Function(TResult result, TParam? param)? onSuccess,
    ErrorAction Function(Object error, BuildContext? context)? onError,
    void Function()? onFinally,

    // Keep global hooks for cross-cutting concerns
    bool? callGlobalHooks,
  },
)
```

**Rationale**:
- 90% of error handling is command-specific
- Pattern-based hooks are good for cross-cutting concerns (auth, logging)
- Command-level callbacks for command-specific logic

### Recommendation 6: Add CommandGroup (Non-Breaking)

**New class**:

```dart
class CommandGroup {
  final List<Command> commands;

  CommandGroup(this.commands);

  ValueListenable<CommandError?> get errors {
    return commands.first.errors.mergeWith(
      commands.skip(1).map((c) => c.errors).toList(),
    );
  }

  ValueListenable<bool> get isExecuting {
    // True if ANY command is executing
    return commands.map((c) => c.isExecuting).reduce((a, b) => a.or(b));
  }

  void dispose() {
    for (final cmd in commands) {
      cmd.dispose();
    }
  }
}
```

### Recommendation 7: Simplify RetryableCommand (Non-Breaking)

**Current Design**: Decorator with complex RetryStrategy

**Simplified Alternative**: Parameter on factory methods

```dart
Command.createAsync<TParam, TResult>(
  func,
  initialValue,
  {
    // NEW: Simple retry parameter
    RetryPolicy? retry,
  },
)

// Usage
late final command = Command.createAsync(
  _fetch,
  null,
  retry: RetryPolicy.exponentialBackoff(
    maxAttempts: 3,
    on: [NetworkException],
  ),
);
```

**Rationale**: Simpler API for the 1-2% of commands that need retry

---

## Impact Assessment

### Quantified Improvements

| Area | Current State | With v9.0 Only | With v9.0 + Recommendations |
|------|--------------|----------------|----------------------------|
| Error listeners | 63 (315 LOC) | 63 (315 LOC) | 0 (eliminated) |
| Custom filters | 8 classes (200 LOC) | 2 classes (50 LOC) | 0 (use built-ins) |
| Undoable boilerplate | 20 commands (300 LOC) | 20 commands (300 LOC) | 20 commands (180 LOC) |
| Debug names | 60% coverage | 60% coverage | 100% coverage |
| Context access | Global service | Global service | Injected |

### Boilerplate Reduction

**Current Total**: ~815 lines of error/undo boilerplate

**With v9.0 Only**: ~665 lines (18% reduction)
- ErrorHandlerRegistry eliminates some custom filters
- Lifecycle hooks provide declarative patterns

**With v9.0 + Recommendations**: ~280 lines (66% reduction)
- onError eliminates error listeners
- Standard filters eliminate custom classes
- Optimistic helper reduces undoable boilerplate
- Context injection simplifies handlers

### Developer Experience

**Current State**:
- Write errorFilter class or use existing
- Add errorFilter parameter
- Write `.errors.listen()` callback
- Access context from global service
- Write snapshot/restore for optimistic updates
- Remember to add debugName

**With v9.0 + Recommendations**:
- Use built-in ErrorFilter factories (80% of cases)
- Write onError callback with context
- Use Command.createOptimistic() for optimistic updates
- debugName auto-generated

**Estimated Time Savings**: ~5-10 minutes per command with error handling

---

## Before/After Examples

### Example 1: Marketplace Command

**Before (Current)**:
```dart
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  (paymentMethodId) async {
    await api.deletePaymentMethod(paymentMethodId);
    getPaymentMethodsCommand.execute();
  },
  debugName: cmdDeletePaymentMethod,
  errorFilter: const Api404ToSentry403LocalErrorFilter(),
)..errors.listen((ex, _) {
  final context = di<InteractionManager>().stableContext;
  handleMarketplaceApiError(
    ex,
    custom404Message: context.l10n.paymentMethodNotFound,
    custom403GenericMessage: context.l10n.cannotDeletePaymentMethod,
  );
});

// Requires custom filter class (20 lines)
class Api404ToSentry403LocalErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    _reportDeserializationError(error);
    _checkForLockedAccountState(error);
    if (error is ApiException) {
      if (error.code == 404) return ErrorReaction.localAndGlobalHandler;
      if (error.code == 403) return ErrorReaction.localHandler;
    }
    return ErrorReaction.globalHandler;
  }
}
```

**Total**: ~35 lines (command + filter + helper)

**After (v9.0 + Recommendations)**:
```dart
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  (paymentMethodId) async {
    await api.deletePaymentMethod(paymentMethodId);
    getPaymentMethodsCommand.execute();
  },
  debugName: 'deletePaymentMethod', // Auto-generated in future
  onError: (error, context) {
    if (error is ApiException) {
      switch (error.code) {
        case 404:
          showToast(context, context.l10n.paymentMethodNotFound);
          return ErrorAction.alsoLogToSentry;
        case 403:
          showToast(context, context.l10n.cannotDeletePaymentMethod);
          return ErrorAction.handled;
      }
    }
    return ErrorAction.useGlobalHandler;
  },
);
```

**Total**: ~18 lines (53% reduction)

### Example 2: Optimistic Update

**Before (Current)**:
```dart
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<int>(
  () async {
    final favoriteCountSnapshot = favoriteCount;

    _isFavoriteOverride = !isFavorite;
    notifyListeners();

    await api.toggleFavorite(id);

    return favoriteCountSnapshot;
  },
  undo: (stack, error) {
    final originalCount = stack.pop();
    _favoriteCountOverride = originalCount;
    _isFavoriteOverride = null;
    notifyListeners();
  },
  debugName: cmdToggleFavorite,
  errorFilter: const LocalOnlyErrorFilter(),
);
```

**Total**: ~18 lines

**After (v9.0 + Recommendations)**:
```dart
late final toggleFavoriteCommand = Command.createOptimistic<int>(
  execute: () => api.toggleFavorite(id),
  optimisticValue: (current) => current + (isFavorite ? -1 : 1),
  stateNotifier: _favoriteCount,
  onError: (error, context) {
    showToast(context, context.l10n.favoriteFailed);
    return ErrorAction.handled;
  },
);
```

**Total**: ~7 lines (61% reduction)

### Example 3: Complex Multi-Library Error Handling

**Before (Current)**:
```dart
late final setupPaymentMethodCommand = Command.createAsyncNoParamNoResult(
  () async {
    final setupIntent = await api.createSetupIntent();
    await Stripe.instance.initPaymentSheet(...);
    await Stripe.instance.presentPaymentSheet();
    await api.storePaymentMethod(...);
    getPaymentMethodsCommand.execute();
  },
  debugName: 'setupPaymentMethod',
  errorFilter: WcPredicatesErrorFilter([
    (e, s) => e is StripeException && e.error.code == FailureCode.Canceled
        ? ErrorReaction.none
        : null,
    (e, s) => e is StripeException
        ? ErrorReaction.localHandler
        : null,
    (e, s) => e is ApiException
        ? ErrorReaction.localAndGlobalHandler
        : null,
    (e, s) => ErrorReaction.globalHandler,
  ]),
)..errors.listen((ex, _) {
  final context = di<InteractionManager>().stableContext;
  if (ex!.error is StripeException) {
    final error = ex.error as StripeException;
    showToast(context, getStripeErrorMessage(context, error));
  } else if (ex.error is ApiException) {
    showToast(context, context.l10n.paymentSetupFailed);
  }
});

// Requires predicate filter class (30 lines)
```

**Total**: ~40 lines

**After (v9.0 + Recommendations)**:
```dart
late final setupPaymentMethodCommand = Command.createAsyncNoParamNoResult(
  () async {
    final setupIntent = await api.createSetupIntent();
    await Stripe.instance.initPaymentSheet(...);
    await Stripe.instance.presentPaymentSheet();
    await api.storePaymentMethod(...);
    getPaymentMethodsCommand.execute();
  },
  onError: (error, context) {
    if (error is StripeException) {
      if (error.code == FailureCode.Canceled) {
        return ErrorAction.silent;
      }
      showToast(context, getStripeErrorMessage(context, error));
      return ErrorAction.handled;
    }
    if (error is ApiException) {
      showToast(context, context.l10n.paymentSetupFailed);
      return ErrorAction.alsoLogToSentry;
    }
    return ErrorAction.useGlobalHandler;
  },
);
```

**Total**: ~18 lines (55% reduction)

### Example 4: Command Group

**Before (Current)**:
```dart
class PostProxy extends ChangeNotifier {
  late final pollVoteCommand = Command.createUndoable<...>(...);
  late final toggleFavoriteCommand = Command.createUndoable<...>(...);
  late final togglePinnedCommand = Command.createUndoable<...>(...);

  late final ValueListenable<CommandError?> _commandErrors;
  late final StreamSubscription _errorSubscription;

  PostProxy() {
    _commandErrors = pollVoteCommand.errorsDynamic.mergeWith([
      toggleFavoriteCommand.errorsDynamic,
      togglePinnedCommand.errorsDynamic,
    ]);

    _errorSubscription = _commandErrors.listen((ex, sub) {
      if (ex!.error is ApiException) {
        final error = ex.error as ApiException;
        if (error.code == 403 || error.code == 404) {
          handlePostAccessError(error);
        }
      }
    });
  }

  @override
  void dispose() {
    _errorSubscription.cancel();
    pollVoteCommand.dispose();
    toggleFavoriteCommand.dispose();
    togglePinnedCommand.dispose();
    super.dispose();
  }
}
```

**Total**: ~30 lines

**After (v9.0 + Recommendations)**:
```dart
class PostProxy extends ChangeNotifier {
  late final pollVoteCommand = Command.createUndoable<...>(...);
  late final toggleFavoriteCommand = Command.createUndoable<...>(...);
  late final togglePinnedCommand = Command.createUndoable<...>(...);

  late final CommandGroup _commandGroup;

  PostProxy() {
    _commandGroup = CommandGroup([
      pollVoteCommand,
      toggleFavoriteCommand,
      togglePinnedCommand,
    ]);

    _commandGroup.errors.listen((error, _) {
      if (error is ApiException && (error.code == 403 || error.code == 404)) {
        handlePostAccessError(error);
      }
    });
  }

  @override
  void dispose() {
    _commandGroup.dispose();
    super.dispose();
  }
}
```

**Total**: ~20 lines (33% reduction)

---

## Breaking vs Non-Breaking Changes

### Non-Breaking (Can be v9.0)

✅ **Add to existing API without removing**:

1. **ErrorHandlerRegistry** - Additive
   ```dart
   Command.errorRegistry.on<T>(handler); // NEW
   ```

2. **Standard Error Filter Library** - Factory constructors
   ```dart
   ErrorFilter.onStatusCode(...); // NEW
   ErrorFilter.localOnly(); // NEW
   ```

3. **RetryableCommand** - Decorator class
   ```dart
   RetryableCommand(wrappedCommand, ...); // NEW
   ```

4. **Lifecycle Hooks** - Global registration
   ```dart
   Command.addBeforeExecuteHook(...); // NEW
   Command.addBeforeErrorHook(...); // NEW
   ```

5. **Context Provider** - Optional global
   ```dart
   Command.setContextProvider(...); // NEW
   ```

6. **CommandGroup** - New helper class
   ```dart
   CommandGroup([...]); // NEW
   ```

7. **Optimistic Factory** - New factory method
   ```dart
   Command.createOptimistic<T>(...); // NEW
   ```

8. **Per-Command Callbacks** - Optional parameters
   ```dart
   Command.createAsync(
     ...,
     onSuccess: ..., // NEW (optional)
     onError: ..., // NEW (optional)
   );
   ```

### Breaking (Would be v10.0)

❌ **Requires migration**:

1. **Remove errorFilter parameter** - Replaced by onError
   ```dart
   // Old (v8.x)
   errorFilter: const ErrorHandlerLocal(),

   // New (v10.0)
   onError: (error, context) => ErrorAction.handled,
   ```

2. **Remove .errors stream** - Replaced by onError
   ```dart
   // Old (v8.x)
   )..errors.listen((error, _) { ... });

   // New (v10.0)
   onError: (error, context) { ... },
   ```

3. **Make debugName required** - Better error reporting
   ```dart
   // Old (v8.x)
   Command.createAsync(_execute, null); // OK

   // New (v10.0)
   Command.createAsync(_execute, null); // ❌ Lint error: debugName required
   ```

### Recommended Rollout Strategy

**v9.0 (Non-Breaking Release)**:
- Add ErrorHandlerRegistry
- Add standard ErrorFilter library
- Add RetryableCommand decorator
- Add lifecycle hooks system
- Add context provider
- Add CommandGroup
- Add Command.createOptimistic()
- Add onSuccess/onError/onFinally optional parameters
- Deprecate errorFilter + .errors (show warnings)

**v9.x (Transition Period)**:
- Encourage migration via deprecation warnings
- Provide migration guide
- Add codemod/migration tool

**v10.0 (Breaking Release)**:
- Remove errorFilter parameter
- Remove .errors stream
- Make debugName required (or auto-generate)
- Simplify API based on v9.x feedback

---

## Conclusion

### Key Takeaways

1. **v9.0 design is solid but incomplete**
   - ErrorHandlerRegistry solves type-based routing
   - Lifecycle hooks provide declarative approach
   - RetryableCommand is well-designed but low-demand

2. **Critical missing pieces**:
   - Unified error handling (onError callback)
   - Context access for localization
   - Standard error filter library
   - Optimistic update helper

3. **Impact potential**:
   - Current approach: ~66% boilerplate reduction
   - With recommendations: Could eliminate error listeners entirely

4. **Breaking vs Non-Breaking**:
   - Most improvements can be non-breaking (v9.0)
   - Major API cleanup can wait (v10.0)

### Prioritization

**Must-Have for v9.0**:
1. ErrorHandlerRegistry (already planned)
2. Standard error filter library (NEW)
3. Context injection mechanism (NEW)
4. Per-command onError callback (NEW, deprecate old approach)

**Nice-to-Have for v9.0**:
1. Command.createOptimistic() helper
2. CommandGroup for error merging
3. Lifecycle hooks (keep, refine based on feedback)

**Consider for Later**:
1. RetryableCommand (good design, low demand - make opt-in)
2. Automatic debug names (tooling challenge)
3. Full breaking changes (v10.0)

### Final Recommendation

**Ship v9.0 as non-breaking release with**:
- All planned features (ErrorHandlerRegistry, hooks, retry)
- Standard error filter library (high impact, low effort)
- Context provider (high impact, low effort)
- onError callback parameter (additive, deprecate old)
- Command.createOptimistic() factory (high impact, medium effort)

**Result**: 50-60% boilerplate reduction, no migration pain

**Then evaluate for v10.0**: Breaking cleanup based on v9.x adoption feedback
