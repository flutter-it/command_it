# Declarative Error Handling - Feature Specification

**Date**: November 12, 2025
**Version Target**: v9.0.0
**Status**: Design Phase

---

## Overview

This specification extends command_it's error handling from a simple global callback to a comprehensive declarative system with two complementary features:

1. **ErrorHandlerRegistry** - Declarative type-based error routing with priorities
2. **ErrorMiddleware** - Composable error processing pipeline

**Design Principles**:
- ✅ Zero overhead by default (opt-in features)
- ✅ Full backward compatibility with existing `globalExceptionHandler`
- ✅ Type-safe and composable
- ✅ Each feature solves a distinct problem

---

## Feature 1: ErrorHandlerRegistry (Declarative Type-Based Routing)

### Problem It Solves

You want to **route different error types to different handlers** declaratively, rather than writing big if/else blocks in `globalExceptionHandler`.

### API

```dart
// Static registry on Command class
Command.errorRegistry.on<ErrorType>(
  void Function(ErrorType error, CommandError context) handler,
  {
    bool Function(ErrorType error)? when,  // Optional predicate
    HandlerPriority priority,               // Execution order
    String? name,                           // For removal
  }
);

// Priorities
enum HandlerPriority {
  critical(1000),
  high(100),
  normal(50),
  low(10),
}
```

### How Priority Works

**Priority controls execution order** - higher values run FIRST:

```dart
Command.errorRegistry
  // Runs FIRST (priority 1000)
  ..on<NetworkException>(
    (e, ctx) => print('1. Critical'),
    priority: HandlerPriority.critical,
  )

  // Runs SECOND (priority 100)
  ..on<NetworkException>(
    (e, ctx) => print('2. High'),
    priority: HandlerPriority.high,
  )

  // Runs THIRD (priority 50, default)
  ..on<NetworkException>(
    (e, ctx) => print('3. Normal'),
  )

  // Runs LAST (priority 10)
  ..on<NetworkException>(
    (e, ctx) => print('4. Low'),
    priority: HandlerPriority.low,
  );

// Output when NetworkException occurs:
// 1. Critical
// 2. High
// 3. Normal
// 4. Low
```

**Important**: Priority does NOT stop other handlers from running. All matching handlers execute in priority order.

**Common use cases**:

1. **Critical actions run first**
   ```dart
   // Ensure logout happens before showing UI
   Command.errorRegistry.on<AuthException>(
     (e, ctx) => authService.signOut(),  // Must run first
     priority: HandlerPriority.critical,
   );

   Command.errorRegistry.on<AuthException>(
     (e, ctx) => showLoginDialog(),
     priority: HandlerPriority.normal,
   );
   ```

2. **Catch-all handlers run last**
   ```dart
   // Specific handlers (normal priority)
   Command.errorRegistry.on<NetworkException>(...);
   Command.errorRegistry.on<AuthException>(...);

   // Generic catch-all (low priority - runs last)
   Command.errorRegistry.on<Object>(
     (e, ctx) => showGenericError(),
     priority: HandlerPriority.low,
   );
   ```

**Note**: If you want to stop other handlers from running, use `stopPropagation()` in middleware (see ErrorMiddleware section below).

---

### Usage Example 1: Simple Type Routing

**Problem**: "Show login dialog for auth errors, snackbar for network errors"

```dart
void setupErrorHandling() {
  // Handle authentication errors
  Command.errorRegistry.on<AuthException>(
    (error, context) {
      showLoginDialog();
      navigateToLogin();
    },
  );

  // Handle network errors
  Command.errorRegistry.on<NetworkException>(
    (error, context) {
      showSnackBar('Connection issue: ${error.message}');
    },
  );

  // Catch-all for unexpected errors
  Command.errorRegistry.on<Object>(
    (error, context) {
      logToSentry(error);
      showGenericErrorDialog();
    },
    priority: HandlerPriority.low,
  );
}
```

---

### Usage Example 2: Conditional Routing with Predicates

**Problem**: "Different handling for different HTTP status codes"

```dart
void setupErrorHandling() {
  // 401 - Show login
  Command.errorRegistry.on<HttpException>(
    (error, context) => showLoginDialog(),
    when: (e) => e.statusCode == 401,
    priority: HandlerPriority.high,
  );

  // 403 - Show permission denied
  Command.errorRegistry.on<HttpException>(
    (error, context) => showPermissionDenied(),
    when: (e) => e.statusCode == 403,
    priority: HandlerPriority.high,
  );

  // 5xx - Show server error
  Command.errorRegistry.on<HttpException>(
    (error, context) => showServerError(),
    when: (e) => e.statusCode >= 500,
  );

  // Retryable network errors
  Command.errorRegistry.on<NetworkException>(
    (error, context) => scheduleRetry(context.command),
    when: (e) => e.isRetryable,
  );
}
```

---

### Usage Example 3: Dynamic Enable/Disable

**Problem**: "Enable debug logging only in debug mode"

```dart
void enableDebugMode() {
  Command.errorRegistry.on<Object>(
    (error, context) {
      print('=== DEBUG ERROR ===');
      print('Command: ${context.commandName}');
      print('Error: $error');
      print('Stack: ${context.stackTrace}');
    },
    name: 'debug_logger',
    priority: HandlerPriority.critical, // First
  );
}

void disableDebugMode() {
  Command.errorRegistry.remove('debug_logger');
}

// Usage
if (kDebugMode) {
  enableDebugMode();
}
```

---

### Usage Example 4: Multiple Handlers

**Problem**: "Both log to Sentry AND show UI for same error"

```dart
void setupErrorHandling() {
  // Log all network errors to analytics
  Command.errorRegistry.on<NetworkException>(
    (error, context) {
      analytics.logError('network_error', error.code);
    },
    name: 'analytics_logger',
  );

  // Show UI for network errors
  Command.errorRegistry.on<NetworkException>(
    (error, context) {
      showSnackBar('Connection issue');
    },
    name: 'network_ui',
  );

  // Both handlers will execute!
}
```

---

### API Methods

```dart
// Register handler
Command.errorRegistry.on<MyException>(...);

// Remove by name
Command.errorRegistry.remove('handler_name');

// Remove all handlers for a type
Command.errorRegistry.removeType<MyException>();

// Clear all
Command.errorRegistry.clear();
```

**Key Point**: Registry runs **for all commands globally**. Use predicates to filter which errors to handle.

---

## Feature 2: ErrorMiddleware (Composable Error Processing)

### Problem It Solves

You want to apply **cross-cutting error processing** (logging, deduplication, retry) to **all errors** before they reach handlers.

### API

```dart
abstract class ErrorMiddleware {
  void process(ErrorContext context);
}

class ErrorContext {
  final CommandError error;
  final Map<String, dynamic> data;  // Share data between middleware
  bool shouldContinue = true;

  void stopPropagation();  // Stop middleware chain
}

// Static middleware chain on Command class
Command.errorMiddleware.use(MyMiddleware());
```

---

### Usage Example 1: Logging

**Problem**: "Log all errors to console in debug mode"

```dart
void main() {
  if (kDebugMode) {
    Command.errorMiddleware.use(
      LoggingMiddleware(verbose: true),
    );
  }

  runApp(MyApp());
}
```

**Built-in LoggingMiddleware**:
```dart
LoggingMiddleware({
  bool verbose = false,
  bool logToConsole = true,
})
```

---

### Usage Example 2: Deduplication

**Problem**: "Don't spam user with same error repeatedly"

```dart
void main() {
  Command.errorMiddleware.use(
    DeduplicationMiddleware(
      window: Duration(seconds: 5),  // Ignore duplicates within 5s
    ),
  );

  runApp(MyApp());
}
```

**How it works**: If same error type from same command occurs within 5 seconds, it stops propagation (no handlers called).

---

### Usage Example 3: Custom Middleware

**Problem**: "Send all errors to Sentry"

```dart
class SentryMiddleware extends ErrorMiddleware {
  @override
  void process(ErrorContext context) {
    Sentry.captureException(
      context.error.error,
      stackTrace: context.error.stackTrace,
    );
    // Don't stop propagation - let other middleware/handlers run
  }
}

// Usage
Command.errorMiddleware.use(SentryMiddleware());
```

---

### Usage Example 4: Rate Limiting

**Problem**: "Track commands that error too frequently"

```dart
class RateLimitMiddleware extends ErrorMiddleware {
  final Map<String, int> _errorCounts = {};
  final int threshold;

  RateLimitMiddleware({this.threshold = 10});

  @override
  void process(ErrorContext context) {
    final key = context.error.commandName ?? 'unknown';
    final count = (_errorCounts[key] ?? 0) + 1;
    _errorCounts[key] = count;

    // Share count with downstream middleware
    context.data['errorCount'] = count;

    if (count > threshold) {
      // Too many errors - stop propagation to prevent spam
      // Note: Disabling the command would require new disable() API
      context.stopPropagation();
    }
  }
}

// Usage
Command.errorMiddleware.use(
  RateLimitMiddleware(threshold: 10),
);
```

---

### Usage Example 5: Data Sharing Between Middleware

**Problem**: "Alert user if error count is high"

```dart
class ErrorCountMiddleware extends ErrorMiddleware {
  final Map<String, int> _counts = {};

  @override
  void process(ErrorContext context) {
    final key = context.error.commandName ?? 'unknown';
    final count = (_counts[key] ?? 0) + 1;
    _counts[key] = count;

    // Share with downstream middleware
    context.data['errorCount'] = count;
  }
}

class AlertMiddleware extends ErrorMiddleware {
  @override
  void process(ErrorContext context) {
    final count = context.data['errorCount'] as int? ?? 0;

    if (count > 5) {
      showWarningBanner('High error rate detected');
    }
  }
}

// Usage - order matters!
Command.errorMiddleware
  ..use(ErrorCountMiddleware())  // Runs first, adds count
  ..use(AlertMiddleware());      // Runs second, reads count
```

---

### Built-in Middleware (Provided by Package)

```dart
// Logging
LoggingMiddleware(verbose: true)

// Deduplication
DeduplicationMiddleware(window: Duration(seconds: 5))
```

**Note**: For retry functionality, use `RetryableCommand` decorator instead of middleware. See `RETRYABLE_COMMAND_SPEC.md` for details.

**Key Point**: Middleware runs **for all commands globally**, in registration order. Use `context.stopPropagation()` to short-circuit.

---

## Complete Real-World Setup

```dart
void main() {
  setupErrorHandling();
  runApp(MyApp());
}

void setupErrorHandling() {
  // === MIDDLEWARE (all errors, in order) ===

  Command.errorMiddleware
    // 1. Log everything (debug only)
    ..use(LoggingMiddleware(verbose: kDebugMode))

    // 2. Deduplicate rapid errors
    ..use(DeduplicationMiddleware(window: Duration(seconds: 5)))

    // 3. Send to Sentry
    ..use(SentryMiddleware());

  // === REGISTRY (type-based routing) ===

  Command.errorRegistry
    // Auth errors → force logout
    ..on<AuthException>(
      (error, context) {
        authService.signOut();
        navigateToLogin();
      },
      when: (e) => e.statusCode == 401,
      priority: HandlerPriority.high,
    )

    // Network errors → show snackbar
    ..on<NetworkException>(
      (error, context) {
        showSnackBar('Connection issue: ${error.message}');
      },
    )

    // Validation errors → show in-place
    ..on<ValidationException>(
      (error, context) {
        showValidationErrors(error.errors);
      },
    )

    // Catch-all → generic error dialog
    ..on<Object>(
      (error, context) {
        showErrorDialog('Unexpected error occurred');
      },
      priority: HandlerPriority.low,
    );

  // === LEGACY HANDLER (still works!) ===

  Command.globalExceptionHandler = (error, stackTrace) {
    print('Legacy: $error');
  };
}
```

---

## Error Flow

```
Command executes → Error occurs
  ↓
Command's ErrorFilter decides local vs global routing
  ↓
If routed globally (ErrorReaction.globalHandler):
  ↓
  1. ErrorMiddleware chain processes
     - Each middleware can modify context or stopPropagation()
     - Runs in registration order
     - If stopped, skip to step 4
  ↓
  2. ErrorHandlerRegistry tries to handle
     - Handlers checked in priority order
     - Matching handlers execute (multiple can match)
  ↓
  3. globalExceptionHandler called (legacy, if exists)
  ↓
  4. Error emitted to command.thrownExceptions
```

---

## Registry vs Middleware: When to Use Which?

| Feature | Use When | Example |
|---------|----------|---------|
| **Registry** | Route different error **types** to different handlers | "Auth errors → login, network errors → snackbar" |
| **Middleware** | Apply processing to **all** errors | "Log everything, deduplicate, auto-retry" |

They **compose together**:
- Middleware processes first (cross-cutting concerns)
- Registry routes by type (specific handling)

---

## Backward Compatibility

### Existing Code Continues to Work

```dart
// This still works exactly as before
Command.globalExceptionHandler = (error, stackTrace) {
  print('Error: $error');
};
```

### Migration is Gradual

```dart
// Keep using globalExceptionHandler
Command.globalExceptionHandler = myOldHandler;

// Add new features incrementally
Command.errorMiddleware.use(LoggingMiddleware());  // Add logging

Command.errorRegistry.on<AuthException>((e, ctx) {  // Add type routing
  showLogin();
});

// Eventually remove globalExceptionHandler when ready
```

### Zero Overhead

- If you don't use middleware: No middleware chain created
- If you don't use registry: No registry lookups
- Old code runs exactly as fast as before

---

## Design Decisions

### 1. Middleware Before Registry

**Decision**: Middleware runs before registry

**Reason**: Middleware is cross-cutting (logging, deduplication), should process all errors first. Registry is routing (type-specific handling), happens after.

### 2. Registry Allows Multiple Handlers

**Decision**: Multiple handlers can match and all execute

**Reason**: Common pattern: log to analytics AND show UI. Users can use `context.stopPropagation()` in middleware if they want exclusive handling.

### 3. No Automatic Error Enrichment

**Rejected**: Automatically add failure counts, timing to all errors

**Reason**: Overhead for all commands, unclear what to track, memory leaks

**Alternative**: Users can add tracking middleware if needed, or use CommandTracker for per-command metrics (see `COMMAND_TRACKER_SPEC.md`)

---

## Relationship to CommandTracker

ErrorHandlerRegistry and ErrorMiddleware are **independent** from CommandTracker.

**Different purposes**:
- **Error Handling** (this doc): Global error routing ("Where should THIS error go?")
- **CommandTracker**: Per-command metrics ("How is THIS command behaving?")

**They compose nicely**:
```dart
// Global error handling (all commands)
Command.errorRegistry.on<NetworkException>((e, ctx) => showSnackbar());
Command.errorMiddleware.use(LoggingMiddleware());

// Per-command tracking (specific command)
final tracker = CircuitBreakerTracker();
tracker.attach(myUnstableCommand);
```

See `COMMAND_TRACKER_SPEC.md` for metrics/monitoring details.

---

## Open Questions

1. **Should middleware have async support?**
   ```dart
   class AsyncMiddleware extends ErrorMiddleware {
     @override
     Future<void> process(ErrorContext context) async {
       await sendToServer();
     }
   }
   ```

2. **Should registry handlers return a value to indicate "handled"?**
   ```dart
   Command.errorRegistry.on<MyError>(
     (error, context) {
       showDialog();
       return true;  // ← "I handled it, don't call other handlers"
     },
   );
   ```

3. **Should there be a way to get all registered handlers?**
   ```dart
   final handlers = Command.errorRegistry.getHandlers<NetworkException>();
   ```

4. **Should middleware be able to modify the error itself?**
   ```dart
   class ErrorEnrichmentMiddleware extends ErrorMiddleware {
     @override
     void process(ErrorContext context) {
       // Wrap original error with additional context?
       context.error = EnhancedError(context.error, metadata: {...});
     }
   }
   ```

---

## Next Steps

1. Review API design
2. Decide on open questions
3. Implement ErrorHandlerRegistry
4. Implement ErrorMiddleware system
5. Implement built-in middleware (Logging, Deduplication, Retry)
6. Add comprehensive tests
7. Document best practices
8. Create examples
