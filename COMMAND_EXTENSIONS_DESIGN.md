# Command Extensions - Unified Design Document

**Date**: November 12, 2025 (Updated with pattern-based hooks)
**Version Target**: v9.0.0
**Status**: Design Phase - Pattern-Based Hooks Finalized

---

## Overview

This document consolidates the design decisions for extending command_it with:
1. **Global Error Handling** (ErrorHandlerRegistry with priority-based routing)
2. **Retry Capability** (RetryableCommand decorator with flexible strategies)
3. **Lifecycle Hooks** (4 hook types with HookPolicy system)

**Core Principles Established:**
- ✅ **Observation** → Use existing listeners (no new system needed)
- ✅ **Behavior modification** → Use decorators (wrapping pattern) or lifecycle hooks
- ✅ **Global error routing** → Use ErrorHandlerRegistry with priorities
- ✅ **Lifecycle hooks** → 4 types (guard, validate, recover, observe) with policy control
- ✅ **Zero overhead** → Features are opt-in, enum switch + empty list checks only
- ✅ **Flexibility** → HookPolicy enables testing, production, and strict enforcement modes

---

## Design Decisions Summary

### What We Rejected

❌ **CommandTracker** - Redundant with existing listeners
- Commands already have `results`, `thrownExceptions`, `isExecuting` ValueListenables
- Users can attach listeners directly for observation
- No need for separate tracker concept

❌ **ErrorMiddleware (complex version)** - Too much for global observation
- Would require iteration through list
- Commands would couple to middleware system
- Behavior modification should use decorators instead

❌ **Global Interceptors with lifecycle hooks** - Redundant with listeners
- If they only observe → use listeners
- If they modify behavior → use decorators
- No middle ground needed

❌ **Command Registry** - No use case identified
- Event-driven architecture (push, not pull)
- Commands notify hooks, not pulled from registry
- Would add overhead for no clear benefit

❌ **Chaining Multiple Hooks** - Complexity without clear benefit
- Hard to debug transformation pipelines
- Performance overhead of multiple iterations
- Unclear semantics (should all hooks agree?)
- Pattern-based routing (first match wins) is cleaner

### What We Kept

✅ **ErrorHandlerRegistry** - Declarative global error routing with priorities
✅ **RetryableCommand** - Decorator for retry behavior with flexible strategies
✅ **Lifecycle Hooks** - Pattern-based routing with 4 hook types:
   - `onBeforeExecute` - Execution guards (throws to block)
   - `onBeforeSuccess` - Result validation/transformation (throws to convert to error)
   - `onBeforeError` - Error recovery/transformation (returns to convert to success)
   - `onAfterExecute` - Side effects only (analytics, logging)
   - **First match wins** - Hooks register with `when` predicate, first matching hook runs
   - **No chaining** - Only one hook executes per command per lifecycle point

---

## Feature 1: ErrorHandlerRegistry (Global Error Routing)

### Purpose
Route different error types to different handlers declaratively, without if/else chains.

### API

```dart
// Register handler for specific error type
Command.errorRegistry.on<ErrorType>(
  void Function(ErrorType error, CommandError context) handler,
  {
    bool Function(ErrorType error)? when,  // Optional predicate
    HandlerPriority priority,               // Execution order
    String? name,                           // For removal
  }
);

enum HandlerPriority {
  critical(1000),
  high(100),
  normal(50),
  low(10),
}
```

### Implementation

```dart
class ErrorHandlerRegistry {
  final List<ErrorHandlerEntry> _handlers = [];

  void on<E>(
    void Function(E error, CommandError context) handler,
    {bool Function(E error)? when, HandlerPriority priority, String? name}
  ) {
    _handlers.add(ErrorHandlerEntry<E>(...));
    _handlers.sort((a, b) => b.priority.value.compareTo(a.priority.value));
  }

  bool tryHandle(Object error, CommandError context) {
    for (final handler in _handlers) {
      if (handler.matches(error)) {
        handler.handle(error, context);
      }
    }
  }
}

// Static registry on Command class
class Command {
  static final ErrorHandlerRegistry errorRegistry = ErrorHandlerRegistry();

  // Called by command when error should go to global handler
  void _notifyGlobalError(CommandError error) {
    errorRegistry.tryHandle(error.error, error);
    globalExceptionHandler?.call(error, error.stackTrace);
  }
}
```

### Usage

```dart
void setupErrorHandling() {
  // Route by type
  Command.errorRegistry.on<AuthException>((error, context) {
    showLoginDialog();
  });

  // Route with predicate
  Command.errorRegistry.on<HttpException>(
    (error, context) => showError('Unauthorized'),
    when: (e) => e.statusCode == 401,
    priority: HandlerPriority.high,
  );

  // Catch-all
  Command.errorRegistry.on<Object>(
    (error, context) => showGenericError(),
    priority: HandlerPriority.low,
  );
}
```

### Key Points
- All matching handlers execute (not exclusive)
- Handlers run in priority order (high to low)
- Backward compatible with existing `globalExceptionHandler`
- No middleware - just registry lookup

---

## Feature 2: RetryableCommand (Decorator Pattern)

### Purpose
Add flexible retry capabilities to any command through wrapping/decoration.

### Why Decorator?
- ❌ Not middleware - retry is command-specific, not global
- ✅ Decorator - wraps specific commands that need retry
- ✅ Composable - can combine with other decorators
- ✅ Explicit - clear what's being retried

### API

```dart
class RetryableCommand<TParam, TResult> extends Command<TParam, TResult> {
  RetryableCommand(
    Command<TParam, TResult> wrappedCommand,
    {
      int maxAttempts = 3,
      Duration delay = const Duration(seconds: 2),
      bool Function(Object error, int attempt)? shouldRetry,
      RetryStrategy<TParam, TResult>? onRetry,
    }
  );
}

typedef RetryStrategy<TParam, TResult> = RetryAction<TParam, TResult> Function(
  Object error,
  TParam? originalParam,
  int attemptNumber,
);

class RetryAction<TParam, TResult> {
  RetryAction.simple({Duration? delay});
  RetryAction.withParam(TParam? param, {Duration? delay});
  RetryAction.withCommand(Command<TParam, TResult> command, TParam? param, {Duration? delay});
  RetryAction.giveUp();
}
```

### Usage Examples

**Simple retry:**
```dart
final command = RetryableCommand(
  Command.createAsync(fetchUser, null),
  maxAttempts: 3,
  delay: Duration(seconds: 2),
  shouldRetry: (error, attempt) => error is NetworkException,
);
```

**Exponential backoff:**
```dart
final command = RetryableCommand(
  Command.createAsync(apiCall, null),
  maxAttempts: 5,
  onRetry: (error, param, attempt) {
    final backoff = Duration(seconds: math.pow(2, attempt).toInt());
    return RetryAction.simple(delay: backoff);
  },
);
```

**Fallback to different API:**
```dart
final primary = Command.createAsync(fetchFromPrimary, null);
final backup = Command.createAsync(fetchFromBackup, null);

final command = RetryableCommand(
  primary,
  maxAttempts: 2,
  onRetry: (error, param, attempt) {
    if (attempt == 1) {
      return RetryAction.simple();  // Retry primary
    } else {
      return RetryAction.withCommand(backup, param);  // Switch to backup
    }
  },
);
```

**Reduce batch size on timeout:**
```dart
final command = RetryableCommand(
  Command.createAsync(processBatch, null),
  onRetry: (error, param, attempt) {
    final newSize = param.batchSize ~/ math.pow(2, attempt);
    return RetryAction.withParam(param.copyWith(batchSize: newSize));
  },
);
```

### Built-in Strategies

```dart
RetryStrategies.exponentialBackoff()
RetryStrategies.exponentialBackoffWithJitter(maxJitterMs: 1000)
RetryStrategies.linearBackoff(baseDelay: Duration(seconds: 1))
RetryStrategies.constantDelay(delay: Duration(seconds: 2))
```

---

## Feature 3: Lifecycle Hooks (Execution Guards & Transformations)

### Purpose
Global hooks at key lifecycle points for guards, transformations, and side effects.

### Why This Pattern?
- **Execution guards**: Block execution imperatively (different from reactive `restriction`)
- **Result transformation**: Validate results, recover from errors, transform data
- **Side effects**: Analytics, logging without coupling to command logic
- **Global control**: Apply cross-cutting concerns consistently across all commands

### API

```dart
// Result wrapper for transformation hooks
class CommandHookResult<T> {
  final T data;
  CommandHookResult(this.data);
}

// Hook type definitions
typedef BeforeExecuteHook = void Function(
  Command command,
  dynamic param,
);

typedef BeforeSuccessHook<TResult> = CommandHookResult<TResult>? Function(
  Command command,
  TResult result,
  dynamic param,
);

typedef BeforeErrorHook<TResult> = CommandHookResult<TResult>? Function(
  Command command,
  Object error,
  StackTrace stackTrace,
  dynamic param,
);

typedef AfterExecuteHook = void Function(
  Command command,
  CommandResult result,
);

// Hook predicate for pattern matching
typedef HookPredicate = bool Function(Command command);

// Hook policy controls global behavior
enum HookPolicy {
  call,              // Always call hooks (strict, no override)
  neverCall,         // Never call hooks (strict, no override)
  defaultCall,       // Default yes (commands can override)
  defaultNeverCall,  // Default no (commands can override)
}

class Command {
  // Global hook configuration (applies to ALL hook types)
  static HookPolicy hookPolicy = HookPolicy.defaultCall;

  // Hook registries (internal entry objects with predicate + hook)
  static final List<_HookEntry> _beforeExecuteHooks = [];
  static final List<_HookEntry> _beforeSuccessHooks = [];
  static final List<_HookEntry> _beforeErrorHooks = [];
  static final List<_HookEntry> _afterExecuteHooks = [];

  // Registration methods with pattern matching
  static void addBeforeExecuteHook({
    required HookPredicate when,
    required BeforeExecuteHook hook,
    String? name,  // For removal
  });

  static void addBeforeSuccessHook<TResult>({
    required HookPredicate when,
    required BeforeSuccessHook<TResult> hook,
    String? name,
  });

  static void addBeforeErrorHook<TResult>({
    required HookPredicate when,
    required BeforeErrorHook<TResult> hook,
    String? name,
  });

  static void addAfterExecuteHook({
    required HookPredicate when,
    required AfterExecuteHook hook,
    String? name,
  });
}

// All factory methods get per-command override parameters
Command.createAsync<TParam, TResult>(
  func,
  initialValue,
  {
    bool? callBeforeExecuteHook,   // null = use policy, true/false = override
    bool? callBeforeSuccessHook,   // null = use policy, true/false = override
    bool? callBeforeErrorHook,     // null = use policy, true/false = override
    bool? callAfterExecuteHook,    // null = use policy, true/false = override
    // ... other parameters
  }
)
```

### Implementation

```dart
// Internal hook entry with predicate
class _HookEntry<T> {
  final HookPredicate when;
  final T hook;
  final String? name;

  _HookEntry({required this.when, required this.hook, this.name});

  bool matches(Command command) => when(command);
}

class Command {
  static HookPolicy hookPolicy = HookPolicy.defaultCall;
  static final List<_HookEntry<BeforeExecuteHook>> _beforeExecuteHooks = [];
  static final List<_HookEntry<BeforeSuccessHook>> _beforeSuccessHooks = [];
  static final List<_HookEntry<BeforeErrorHook>> _beforeErrorHooks = [];
  static final List<_HookEntry<AfterExecuteHook>> _afterExecuteHooks = [];

  // Per-command overrides
  final bool? callBeforeExecuteHook;
  final bool? callBeforeSuccessHook;
  final bool? callBeforeErrorHook;
  final bool? callAfterExecuteHook;

  void execute(TParam? param) {
    // 1. Before execute hooks - FIRST MATCH WINS
    if (_shouldCallHooks(callBeforeExecuteHook) && _beforeExecuteHooks.isNotEmpty) {
      try {
        for (final entry in _beforeExecuteHooks) {
          if (entry.matches(this)) {
            entry.hook(this, param);
            break;  // First match wins, stop checking
          }
        }
      } catch (error, stackTrace) {
        _handleError(error, stackTrace, param);
        return;  // Block execution
      }
    }

    // 2. Execute the command
    try {
      final result = _executeFunction(param);
      _publishSuccess(result, param);
    } catch (error, stackTrace) {
      _publishError(error, stackTrace, param);
    }
  }

  void _publishSuccess(TResult result, TParam? param) {
    TResult finalResult = result;

    // 3. Before success hooks - FIRST MATCH WINS
    if (_shouldCallHooks(callBeforeSuccessHook) && _beforeSuccessHooks.isNotEmpty) {
      try {
        for (final entry in _beforeSuccessHooks) {
          if (entry.matches(this)) {
            final transformed = entry.hook(this, finalResult, param);
            if (transformed != null) {
              finalResult = transformed.data;  // Apply transformation
            }
            break;  // First match wins, stop checking
          }
        }
      } catch (error, stackTrace) {
        // Hook threw - convert success to error
        _publishError(error, stackTrace, param);
        return;
      }
    }

    // Update .value and .results
    value = finalResult;

    // 4. After execute hooks - FIRST MATCH WINS
    if (_shouldCallHooks(callAfterExecuteHook) && _afterExecuteHooks.isNotEmpty) {
      try {
        for (final entry in _afterExecuteHooks) {
          if (entry.matches(this)) {
            entry.hook(this, results.value);
            break;  // First match wins
          }
        }
      } catch (error, stackTrace) {
        // Log but don't affect result
        print('AfterExecuteHook threw: $error');
      }
    }
  }

  void _publishError(Object error, StackTrace stackTrace, TParam? param) {
    Object finalError = error;
    StackTrace finalStack = stackTrace;
    bool recovered = false;
    TResult? recoveredValue;

    // 3. Before error hooks - FIRST MATCH WINS
    if (_shouldCallHooks(callBeforeErrorHook) && _beforeErrorHooks.isNotEmpty) {
      try {
        for (final entry in _beforeErrorHooks) {
          if (entry.matches(this)) {
            final result = entry.hook(this, finalError, finalStack, param);
            if (result != null) {
              // Hook returned success value - recover!
              recovered = true;
              recoveredValue = result.data;
            }
            break;  // First match wins, stop checking
          }
        }
      } catch (newError, newStack) {
        // Hook threw - transform error
        finalError = newError;
        finalStack = newStack;
      }
    }

    if (recovered) {
      // Convert error to success
      _publishSuccess(recoveredValue!, param);
      return;
    }

    // Handle error normally
    _handleError(finalError, finalStack, param);

    // 4. After execute hooks - FIRST MATCH WINS
    if (_shouldCallHooks(callAfterExecuteHook) && _afterExecuteHooks.isNotEmpty) {
      try {
        for (final entry in _afterExecuteHooks) {
          if (entry.matches(this)) {
            entry.hook(this, results.value);
            break;  // First match wins
          }
        }
      } catch (error, stackTrace) {
        // Log but don't affect result
        print('AfterExecuteHook threw: $error');
      }
    }
  }

  bool _shouldCallHooks(bool? override) {
    switch (hookPolicy) {
      case HookPolicy.call:
        return true;  // Always call (override ignored)
      case HookPolicy.neverCall:
        return false;  // Never call (override ignored)
      case HookPolicy.defaultCall:
        return override ?? true;  // Default yes, can override
      case HookPolicy.defaultNeverCall:
        return override ?? false;  // Default no, can override
    }
  }
}
```

### Usage

**Example 1: Execution Guards (onBeforeExecute)**
```dart
void setupExecutionGuards() {
  Command.hookPolicy = HookPolicy.defaultCall;

  // Specific: Admin commands need extra permission check
  Command.addBeforeExecuteHook(
    when: (cmd) => cmd.name?.startsWith('admin') ?? false,
    hook: (cmd, param) {
      if (!authService.isAdmin) {
        throw PermissionDeniedException('admin');
      }
    },
  );

  // Specific: API commands need network check
  Command.addBeforeExecuteHook(
    when: (cmd) => cmd is ApiCommand,
    hook: (cmd, param) {
      if (!networkService.isOnline) throw OfflineException();
    },
  );

  // Catch-all: All other commands need basic auth (added LAST)
  Command.addBeforeExecuteHook(
    when: (cmd) => true,  // Matches all
    hook: (cmd, param) {
      if (!authService.isLoggedIn) throw NotLoggedInException();
    },
  );

  // Handle exceptions through error registry
  Command.errorRegistry.on<NotLoggedInException>((e, ctx) => showLoginDialog());
  Command.errorRegistry.on<OfflineException>((e, ctx) => showOfflineError());
}
```

**Example 2: Result Validation (onBeforeSuccess)**
```dart
void setupResultValidation() {
  // Specific: Validate User objects from fetch commands
  Command.addBeforeSuccessHook<User>(
    when: (cmd) => cmd.name?.startsWith('fetch'),
    hook: (cmd, user, param) {
      if (user.id.isEmpty) {
        // Invalid result - convert to error
        throw ValidationException('User ID cannot be empty');
      }

      // Transform result if needed
      if (user.name.isEmpty) {
        return CommandHookResult(user.copyWith(name: 'Anonymous'));
      }

      return null;  // Pass through unchanged
    },
  );

  // Catch-all: Basic validation for all other results
  Command.addBeforeSuccessHook<Object>(
    when: (cmd) => true,
    hook: (cmd, result, param) {
      // Generic validation logic
      return null;  // Usually just passthrough
    },
  );
}
```

**Example 3: Error Recovery (onBeforeError)**
```dart
void setupErrorRecovery() {
  // Specific: Recover network errors with cache for list commands
  Command.addBeforeErrorHook<List<Item>>(
    when: (cmd) => cmd.name?.contains('List') ?? false,
    hook: (cmd, error, stack, param) {
      if (error is NetworkException && cacheService.hasData(param)) {
        // Recover with cached data
        return CommandHookResult(cacheService.getData(param));
      }
      return null;  // Can't handle, pass through
    },
  );

  // Catch-all: Transform timeout errors for all commands
  Command.addBeforeErrorHook<Object>(
    when: (cmd) => true,
    hook: (cmd, error, stack, param) {
      if (error is TimeoutException) {
        throw UserFriendlyException('Request timed out, please try again');
      }
      return null;  // Pass through unchanged
    },
  );
}
```

**Example 4: Analytics & Logging (onAfterExecute)**
```dart
void setupAnalytics() {
  // Specific: Track admin commands separately
  Command.addAfterExecuteHook(
    when: (cmd) => cmd.name?.startsWith('admin') ?? false,
    hook: (cmd, result) {
      auditLog.record('admin_action', {
        'command': cmd.name,
        'success': result.hasData,
      });
    },
  );

  // Catch-all: Track all other commands
  Command.addAfterExecuteHook(
    when: (cmd) => true,
    hook: (cmd, result) {
      if (result.hasData) {
        analytics.logEvent('command_success', {
          'command': cmd.name,
          'duration': result.executionTime,
        });
      } else if (result.hasError) {
        analytics.logEvent('command_error', {
          'command': cmd.name,
          'error_type': result.error.runtimeType.toString(),
        });
        sentry.captureException(result.error, stackTrace: result.stackTrace);
      }
    },
  );
}
```

**Example 5: Complete Setup**
```dart
void main() {
  setupExecutionGuards();
  setupResultValidation();
  setupErrorRecovery();
  setupAnalytics();

  runApp(MyApp());
}
```

**Example 6: Per-Command Overrides**
```dart
// Most commands use global hooks (policy is defaultCall)
final normalCommand = Command.createAsync(fetchData, null);

// Specific command opts out of specific hooks
final internalCommand = Command.createAsync(
  internalHelper,
  null,
  callBeforeExecuteHook: false,   // Skip execution guards
  callBeforeSuccessHook: false,   // Skip validation
  callAfterExecuteHook: true,     // Still track in analytics
);

// Disable all hooks for specific command
final systemCommand = Command.createAsync(
  systemOperation,
  null,
  callBeforeExecuteHook: false,
  callBeforeSuccessHook: false,
  callBeforeErrorHook: false,
  callAfterExecuteHook: false,
);
```

### Hook Types Summary

| Hook | When Called | Purpose | Return Value | Throw Effect |
|------|-------------|---------|--------------|--------------|
| `onBeforeExecute` | Before function runs | Execution guard | void | Block execution |
| `onBeforeSuccess` | After success, before publish | Validate/transform | `CommandHookResult<T>?` or null | Convert to error |
| `onBeforeError` | After error, before publish | Recover/transform | `CommandHookResult<T>?` or null | Transform error |
| `onAfterExecute` | After publish (success or error) | Side effects | void | Logged only |

### Hook Matching Behavior

**IMPORTANT: First match wins!**

Hooks are checked in registration order. The **first hook whose `when` predicate returns true** is executed, then iteration stops.

```dart
// Order matters - register specific patterns first, catch-all last
Command.addBeforeExecuteHook(
  when: (cmd) => cmd.name == 'adminDeleteUser',  // Most specific - checked first
  hook: strictPermissionCheck,
);

Command.addBeforeExecuteHook(
  when: (cmd) => cmd.name?.startsWith('admin'),  // More specific
  hook: adminCheck,
);

Command.addBeforeExecuteHook(
  when: (cmd) => true,  // Catch-all - add LAST
  hook: defaultAuthCheck,
);
```

**Execution for `adminDeleteUser` command:**
1. Check first hook: `cmd.name == 'adminDeleteUser'` → ✅ TRUE → Execute `strictPermissionCheck` → STOP
2. ❌ Second and third hooks never checked

### Hook Behavior Matrix

| Hook | Return null | Return CommandHookResult(value) | Throw exception |
|------|------------|--------------------------------|-----------------|
| `onBeforeExecute` | N/A | N/A | Block execution, trigger error handling |
| `onBeforeSuccess` | Pass through | Transform result | Convert success → error |
| `onBeforeError` | Pass through | Recover error → success | Transform error |
| `onAfterExecute` | N/A (void) | N/A (void) | Exception logged, doesn't affect result |

**Testing mode (disable all hooks):**
```dart
void main() {
  // In tests, disable all hooks globally
  Command.hookPolicy = HookPolicy.neverCall;

  test('command executes without auth check', () {
    final cmd = Command.createAsync(protectedOp, null);
    cmd();  // Runs even if not logged in
  });
}
```

**Strict enforcement (no opt-outs):**
```dart
void main() {
  // Production: force all commands to respect hooks
  Command.hookPolicy = HookPolicy.call;

  // This override is IGNORED:
  final cmd = Command.createAsync(
    fetch,
    null,
    callBeforeExecuteHook: false,  // Has no effect!
  );
  // cmd() will still call hooks
}
```

### Design Rationale

**Why pattern-based routing (first match wins)?**
- ✅ **No chaining overhead** - Only one hook runs per command
- ✅ **Declarative** - Clear which commands get which behavior
- ✅ **Similar to ErrorHandlerRegistry** - Consistent pattern across package
- ✅ **Easy to debug** - No complex transformation pipelines
- ✅ **Explicit ordering** - Specific patterns first, catch-all last

**Why not chain multiple hooks?**
- ❌ Hard to debug (which hook transformed what?)
- ❌ Performance overhead (multiple iterations)
- ❌ Unclear semantics (should all hooks agree?)
- ✅ If chaining needed → use decorators (RetryableCommand, CachedCommand, etc.)

**Why throw exceptions in hooks?**
- ✅ Exceptions carry context (NotLoggedInException, ValidationException)
- ✅ Routes through error handling (ErrorHandlerRegistry can handle by type)
- ✅ Dart-idiomatic (similar to validators, guards)

**Why separate before/after hooks?**
- ✅ Clear semantics: "before" can modify, "after" observes only
- ✅ Transformation hooks run before state changes (.value, .results)
- ✅ Side effect hooks run after state is published (analytics, logging)

**Why CommandHookResult wrapper?**
- ✅ Explicit intent: null = passthrough, value = transformed
- ✅ Type-safe: Ensures correct result type
- ✅ Simple: Just wraps the data, no complex fields

---

## Hook Policy Use Cases

### Production: Default with Selective Opt-Outs

**Use case**: Most commands should respect global checks, but a few internal/system commands need to bypass them.

```dart
void main() {
  Command.hookPolicy = HookPolicy.defaultCall;

  // Global auth check (catch-all)
  Command.addBeforeExecuteHook(
    when: (cmd) => true,
    hook: (cmd, param) {
      if (!authService.isLoggedIn) throw NotLoggedInException();
    },
  );

  runApp(MyApp());
}

// Most commands use hooks automatically
final userCommand = Command.createAsync(fetchUserData, null);

// Special internal command opts out
final systemCommand = Command.createAsync(
  fetchSystemConfig,
  null,
  callBeforeExecuteHook: false,  // Runs even when not logged in
);
```

### Testing: Globally Disabled

**Use case**: Tests should run without triggering auth/network checks.

```dart
void main() {
  setUp(() {
    Command.hookPolicy = HookPolicy.neverCall;
  });

  test('command logic works', () {
    final cmd = Command.createAsync(businessLogic, null);
    cmd();  // Runs without hooks
  });
}
```

### Strict Production: No Exceptions

**Use case**: Security-critical app where NO command should bypass auth.

```dart
void main() {
  Command.hookPolicy = HookPolicy.call;  // Strict enforcement

  // Global permission check (catch-all)
  Command.addBeforeExecuteHook(
    when: (cmd) => true,
    hook: (cmd, param) {
      if (!securityService.hasPermission()) throw UnauthorizedException();
    },
  );

  // All commands respect hooks, no exceptions
  runApp(SecureApp());
}
```

### Opt-In Mode: Default Disabled

**Use case**: Legacy codebase where you want to gradually add hooks to specific commands.

```dart
void main() {
  Command.hookPolicy = HookPolicy.defaultNeverCall;

  // Global logging (catch-all)
  Command.addBeforeExecuteHook(
    when: (cmd) => true,
    hook: (cmd, param) {
      logger.info('Executing: ${cmd.name}');
    },
  );

  runApp(MyApp());
}

// Most commands skip hooks (legacy behavior)
final oldCommand = Command.createAsync(legacyOp, null);

// New commands explicitly opt in
final newCommand = Command.createAsync(
  modernOp,
  null,
  callBeforeExecuteHook: true,  // This one uses hooks
);
```

### Policy Decision Matrix

| Policy | Default Behavior | Override Allowed? | Common Use Case |
|--------|-----------------|-------------------|-----------------|
| `call` | Always call | ❌ No | Security-critical apps |
| `neverCall` | Never call | ❌ No | Testing environments |
| `defaultCall` | Call by default | ✅ Yes | Production (opt-out) |
| `defaultNeverCall` | Skip by default | ✅ Yes | Legacy migration (opt-in) |

---

## Architecture Summary

### For Observation (Monitoring/Logging)
**Use existing listeners** - no new system needed

```dart
command.results.listen((result) {
  // Observe state changes
});

command.thrownExceptions.listen((error) {
  // Observe errors
});

command.isExecuting.listen((executing) {
  // Observe execution state
});
```

### For Behavior Modification
**Use decorators** - wrap commands

```dart
final wrapped = RetryableCommand(
  CachedCommand(
    CircuitBreakerCommand(
      Command.createAsync(fetch, null),
    ),
  ),
);
```

### For Global Error Routing
**Use ErrorHandlerRegistry** - declarative type-based routing

```dart
Command.errorRegistry.on<MyException>((error, context) {
  // Handle globally
});
```

### For Lifecycle Hooks
**Use 4 hook types with pattern matching** - guards, transformations, side effects

```dart
// Guard execution (pattern-based)
Command.addBeforeExecuteHook(
  when: (cmd) => cmd.name?.startsWith('admin') ?? false,
  hook: (cmd, param) {
    if (!canExecute) throw BlockedException();
  },
);

// Validate results (pattern-based)
Command.addBeforeSuccessHook<User>(
  when: (cmd) => cmd.name?.startsWith('fetch'),
  hook: (cmd, user, param) {
    if (!user.isValid) throw ValidationException();
    return null;  // Pass through
  },
);

// Recover from errors (pattern-based)
Command.addBeforeErrorHook<Data>(
  when: (cmd) => cmd is ApiCommand,
  hook: (cmd, error, stack, param) {
    if (error is NetworkException) {
      return CommandHookResult(cachedData);  // Recover
    }
    return null;  // Pass through
  },
);

// Track executions (catch-all)
Command.addAfterExecuteHook(
  when: (cmd) => true,
  hook: (cmd, result) {
    analytics.track(result);
  },
);
```

---

## Implementation Architecture

### Zero Overhead When Not Used

```dart
class Command {
  static HookPolicy hookPolicy = HookPolicy.defaultCall;
  static final List<_HookEntry> _beforeExecuteHooks = [];
  static final ErrorHandlerRegistry errorRegistry = ErrorHandlerRegistry();

  final bool? callBeforeExecuteHook;

  void execute(param) {
    // Cheap checks - policy enum switch + empty list check
    final shouldCallHooks = _shouldCallHooks(callBeforeExecuteHook);

    if (shouldCallHooks && _beforeExecuteHooks.isNotEmpty) {
      try {
        // First match wins - early termination on match
        for (final entry in _beforeExecuteHooks) {
          if (entry.matches(this)) {
            entry.hook(this, param);
            break;  // Stop after first match
          }
        }
      } catch (error, stack) {
        _handleError(error, stack, param);
        return;
      }
    }

    // ... execution
  }

  bool _shouldCallHooks(bool? override) {
    // Single switch statement - very fast
    switch (hookPolicy) {
      case HookPolicy.call: return true;
      case HookPolicy.neverCall: return false;
      case HookPolicy.defaultCall: return override ?? true;
      case HookPolicy.defaultNeverCall: return override ?? false;
    }
  }

  void _notifyGlobalError(CommandError error) {
    // Registry is always created, but empty = cheap
    errorRegistry.tryHandle(error.error, error);

    // Legacy handler (nullable)
    globalExceptionHandler?.call(error, error.stackTrace);
  }
}
```

### No Command Registry Needed

Event-driven architecture:
```
Command.execute() called
  ↓
1. onBeforeExecute hooks
   → Iterate entries until when(cmd) returns true
   → Execute FIRST matching hook → STOP
   → If throws: block execution
  ↓
Execute function
  ↓
Success?
  ├─ Yes ─→ 2. onBeforeSuccess hooks
  │           → Iterate entries until when(cmd) returns true
  │           → Execute FIRST matching hook → STOP
  │           → Transform or throw to convert to error
  │           ↓
  │         Update .value and .results
  │           ↓
  │         3. onAfterExecute hooks
  │            → Iterate entries until when(cmd) returns true
  │            → Execute FIRST matching hook → STOP
  │
  └─ No ──→ 2. onBeforeError hooks
              → Iterate entries until when(cmd) returns true
              → Execute FIRST matching hook → STOP
              → Return value to recover, or throw to transform
              ↓
            Recovered? ─→ Yes ─→ Go to success path
              ↓ No
            errorRegistry.tryHandle()
              ↓
            Update .results with error
              ↓
            3. onAfterExecute hooks
               → Iterate entries until when(cmd) returns true
               → Execute FIRST matching hook → STOP
```

No central registry tracking all commands.

---

## Open Questions

### 1. Should onRetry in RetryableCommand be async?

**Current**: Sync
```dart
RetryStrategy = RetryAction Function(...)
```

**Alternative**: Async (for token refresh, etc.)
```dart
RetryStrategy = Future<RetryAction> Function(...)
```

**Recommendation**: Start sync, add async variant if needed

### 2. Retry State Observable?

```dart
final retryable = RetryableCommand(...);
retryable.currentAttempt;  // ValueListenable<int>?
retryable.isRetrying;      // ValueListenable<bool>?
```

**Recommendation**: Not initially - can add if needed

---

## Backward Compatibility

All features are **fully backward compatible**:

✅ Existing `globalExceptionHandler` continues to work
```dart
Command.globalExceptionHandler = (error, stack) { ... };
```

✅ Existing error filters work unchanged
```dart
errorFilter: (error, stack) => ErrorReaction.localHandler
```

✅ New features are opt-in:
```dart
// Don't use them = zero overhead (just null checks)
Command.onBeforeExecute  // null by default
Command.errorRegistry    // empty by default
RetryableCommand         // only if you wrap
```

---

## Migration Path

**From current code:**
1. Keep using existing error handling (no changes needed)
2. Optionally add ErrorHandlerRegistry for type-based routing
3. Optionally wrap commands with RetryableCommand
4. Optionally add onBeforeExecute for global guards

**From proposed middleware (now rejected):**
- Don't implement middleware
- Use ErrorHandlerRegistry instead for global error routing
- Use decorators for behavior modification
- Use listeners for observation

---

## Next Steps

1. **Finalize remaining open questions** (async retry, observable state)
2. **Review complete API design**
3. **Create implementation plan** for each feature
4. **Implement in phases**:
   - Phase 1: ErrorHandlerRegistry
   - Phase 2: Lifecycle hooks (all 4 types) with HookPolicy system
   - Phase 3: RetryableCommand decorator
5. **Add tests** for each feature:
   - Hook transformation behaviors (passthrough, transform, throw)
   - Hook policy permutations (call, neverCall, defaultCall, defaultNeverCall)
   - Per-command overrides
   - Error recovery paths
6. **Update documentation**
7. **Create examples** showing all hook types and policies

---

## Files to Update/Remove

### Keep & Update:
- ✅ `RETRYABLE_COMMAND_SPEC.md` - Keep (decorator pattern is good)
- ✅ `DECLARATIVE_ERROR_HANDLING_SPEC.md` - Update (remove middleware, keep registry)

### Remove:
- ❌ `COMMAND_TRACKER_SPEC.md` - Remove (redundant with listeners)
- ❌ `DECLARATIVE_ERROR_HANDLING_PLAN.md` - Remove (old combined doc)

### Cleanup:
- ❌ `lib/enhanced_command_error.dart` - Delete (accidentally created)
- ❌ Export in `lib/command_it.dart` - Remove enhanced_command_error export

### New:
- ✅ This document (`COMMAND_EXTENSIONS_DESIGN.md`) - Consolidated design decisions
