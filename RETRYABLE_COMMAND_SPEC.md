# RetryableCommand - Flexible Retry Decorator Specification

**Date**: November 12, 2025
**Version Target**: v9.0.0
**Status**: Design Phase

---

## Overview

RetryableCommand is a **decorator** that wraps any Command to add flexible retry capabilities with complete control over retry strategies.

**Design Principles**:
- ✅ Decorator pattern - wraps any existing command
- ✅ Zero overhead if not used
- ✅ Flexible retry strategies (simple retry, parameter adjustment, command switching)
- ✅ Composable with other features

---

## Problem It Solves

You want to **automatically retry failed operations** with:
- Different retry strategies per command (not global)
- Ability to adjust parameters between retries
- Ability to switch to fallback commands
- Exponential backoff, jitter, circuit breakers
- Full control over when and how to retry

**Why not global middleware?**
- ❌ Some commands should never retry (delete, payment, logout)
- ❌ Different commands need different strategies
- ❌ Retry logic is command-specific, not cross-cutting

---

## API

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

// Decide what to do on each retry attempt
typedef RetryStrategy<TParam, TResult> = RetryAction<TParam, TResult> Function(
  Object error,
  TParam? originalParam,
  int attemptNumber,
);

// What action to take
class RetryAction<TParam, TResult> {
  // Retry same command with same parameter
  RetryAction.simple({Duration? delay});

  // Retry same command with modified parameter
  RetryAction.withParam(TParam? param, {Duration? delay});

  // Call different command
  RetryAction.withCommand(
    Command<TParam, TResult> command,
    TParam? param,
    {Duration? delay}
  );

  // Give up (don't retry)
  RetryAction.giveUp();
}
```

---

## Usage Example 1: Simple Retry

**Problem**: "Retry network calls up to 3 times with 2 second delay"

```dart
final fetchUserCommand = RetryableCommand(
  Command.createAsync(fetchUserFromAPI, null),
  maxAttempts: 3,
  delay: Duration(seconds: 2),
  shouldRetry: (error, attempt) => error is NetworkException,
);

// Usage is identical to normal command
fetchUserCommand('userId123');

// Execution flow on failure:
// Attempt 1 → NetworkException
//   (wait 2s)
// Attempt 2 → NetworkException
//   (wait 2s)
// Attempt 3 → NetworkException
//   (give up, error propagates)
```

**Note**: If no `onRetry` strategy provided, defaults to simple retry with same param.

---

## Usage Example 2: Exponential Backoff

**Problem**: "Retry with exponential backoff: 1s, 2s, 4s, 8s"

```dart
final apiCommand = RetryableCommand(
  Command.createAsync(callAPI, null),
  maxAttempts: 5,
  shouldRetry: (error, attempt) => error is ServerException,
  onRetry: (error, param, attempt) {
    // Exponential: 2^attempt seconds
    final backoffDelay = Duration(
      seconds: math.pow(2, attempt).toInt(),
    );

    return RetryAction.simple(delay: backoffDelay);
  },
);

// Execution flow:
// Attempt 1 → fails (wait 1s)
// Attempt 2 → fails (wait 2s)
// Attempt 3 → fails (wait 4s)
// Attempt 4 → fails (wait 8s)
// Attempt 5 → give up
```

---

## Usage Example 3: Exponential Backoff with Jitter

**Problem**: "Prevent thundering herd problem with random jitter"

```dart
final apiCommand = RetryableCommand(
  Command.createAsync(callAPI, null),
  maxAttempts: 5,
  shouldRetry: (error, attempt) => error is RateLimitException,
  onRetry: (error, param, attempt) {
    // Base exponential backoff
    final baseDelay = Duration(seconds: math.pow(2, attempt).toInt());

    // Add random jitter (0-1000ms)
    final jitter = Duration(milliseconds: Random().nextInt(1000));

    return RetryAction.simple(delay: baseDelay + jitter);
  },
);

// Multiple clients won't all retry at exact same time
```

---

## Usage Example 4: Reduce Batch Size on Timeout

**Problem**: "If batch processing times out, retry with smaller batches"

```dart
final batchCommand = RetryableCommand(
  Command.createAsync(processBatch, null),
  maxAttempts: 4,
  shouldRetry: (error, attempt) => error is TimeoutException,
  onRetry: (error, originalParam, attempt) {
    // Halve batch size on each retry
    final newBatchSize = originalParam.batchSize ~/ math.pow(2, attempt);

    if (newBatchSize < 10) {
      return RetryAction.giveUp();  // Too small, give up
    }

    return RetryAction.withParam(
      originalParam.copyWith(batchSize: newBatchSize),
      delay: Duration(seconds: 1),
    );
  },
);

// Execution flow:
// Attempt 1: batchSize=100 → timeout
// Attempt 2: batchSize=50 → timeout
// Attempt 3: batchSize=25 → success!
```

---

## Usage Example 5: Fallback to Different API

**Problem**: "If primary API fails, switch to backup API"

```dart
final primaryAPI = Command.createAsync(fetchFromPrimary, null);
final backupAPI = Command.createAsync(fetchFromBackup, null);

final fetchCommand = RetryableCommand(
  primaryAPI,
  maxAttempts: 3,
  shouldRetry: (error, attempt) => error is ServerException,
  onRetry: (error, param, attempt) {
    if (attempt == 1) {
      // First retry: try primary again after delay
      return RetryAction.simple(delay: Duration(seconds: 2));
    } else {
      // Second+ retry: switch to backup API
      return RetryAction.withCommand(
        backupAPI,
        param,
        delay: Duration(seconds: 1),
      );
    }
  },
);

// Execution flow:
// Attempt 1: primary → ServerException
//   (wait 2s)
// Attempt 2: primary → ServerException
//   (wait 1s)
// Attempt 3: backup → success!
```

---

## Usage Example 6: Adjust Timeout on Retry

**Problem**: "First attempt uses short timeout, retries use longer timeout"

```dart
final apiCommand = RetryableCommand(
  Command.createAsync(callAPI, null),
  maxAttempts: 3,
  shouldRetry: (error, attempt) => error is TimeoutException,
  onRetry: (error, originalParam, attempt) {
    // Increase timeout on each retry
    final newTimeout = originalParam.timeout * (attempt + 1);

    return RetryAction.withParam(
      originalParam.copyWith(timeout: newTimeout),
      delay: Duration(seconds: 2),
    );
  },
);

// Execution flow:
// Attempt 1: timeout=5s → TimeoutException
// Attempt 2: timeout=10s → TimeoutException
// Attempt 3: timeout=15s → success!
```

---

## Usage Example 7: Circuit Breaker Pattern

**Problem**: "After too many failures, switch to cached data instead of retrying"

```dart
final apiCommand = Command.createAsync(fetchFromAPI, null);
final cacheCommand = Command.createAsync(fetchFromCache, null);

int consecutiveFailures = 0;
const circuitOpenThreshold = 10;

final fetchCommand = RetryableCommand(
  apiCommand,
  maxAttempts: 3,
  shouldRetry: (error, attempt) {
    // Don't retry if circuit is open
    if (consecutiveFailures >= circuitOpenThreshold) {
      return false;
    }
    return error is NetworkException;
  },
  onRetry: (error, param, attempt) {
    consecutiveFailures++;

    if (consecutiveFailures >= circuitOpenThreshold) {
      // Circuit open - use cache instead
      return RetryAction.withCommand(cacheCommand, param);
    }

    // Circuit closed - retry normally
    return RetryAction.simple(delay: Duration(seconds: 2));
  },
);

// Reset circuit on success
fetchCommand.results.listen((result) {
  if (result.hasData) {
    consecutiveFailures = 0;  // Circuit closed
  }
});

// Execution flow (when circuit is open):
// Attempt 1: API → NetworkException
// Retry: Cache → success (stale data, but available)
```

---

## Usage Example 8: Conditional Retry Based on Error Type

**Problem**: "Different retry strategies for different error types"

```dart
final command = RetryableCommand(
  Command.createAsync(complexOperation, null),
  maxAttempts: 5,
  shouldRetry: (error, attempt) {
    // Retry different errors differently
    if (error is NetworkException) return true;
    if (error is RateLimitException) return true;
    if (error is TimeoutException && attempt < 3) return true;
    return false;
  },
  onRetry: (error, param, attempt) {
    if (error is NetworkException) {
      // Quick retry for network errors
      return RetryAction.simple(delay: Duration(seconds: 1));
    } else if (error is RateLimitException) {
      // Long delay for rate limits
      return RetryAction.simple(delay: Duration(seconds: 30));
    } else if (error is TimeoutException) {
      // Increase timeout for timeout errors
      return RetryAction.withParam(
        param.copyWith(timeout: param.timeout * 2),
        delay: Duration(seconds: 2),
      );
    }

    return RetryAction.giveUp();
  },
);
```

---

## Usage Example 9: Retry with Authentication Refresh

**Problem**: "On 401 error, refresh token and retry"

```dart
final apiCommand = RetryableCommand(
  Command.createAsync(callProtectedAPI, null),
  maxAttempts: 2,
  shouldRetry: (error, attempt) =>
    error is HttpException && error.statusCode == 401 && attempt == 1,
  onRetry: (error, param, attempt) async {
    // Refresh authentication token
    await authService.refreshToken();

    // Retry with new token
    return RetryAction.simple(delay: Duration(milliseconds: 500));
  },
);

// Execution flow:
// Attempt 1: API → 401 Unauthorized
//   (refresh token)
// Attempt 2: API → success with new token
```

---

## Built-in Retry Strategies (Provided by Package)

```dart
// Simple exponential backoff
RetryableCommand(
  baseCommand,
  maxAttempts: 5,
  onRetry: RetryStrategies.exponentialBackoff(),
);

// Exponential backoff with jitter
RetryableCommand(
  baseCommand,
  maxAttempts: 5,
  onRetry: RetryStrategies.exponentialBackoffWithJitter(
    maxJitterMs: 1000,
  ),
);

// Linear backoff (1s, 2s, 3s, 4s)
RetryableCommand(
  baseCommand,
  maxAttempts: 5,
  onRetry: RetryStrategies.linearBackoff(
    baseDelay: Duration(seconds: 1),
  ),
);

// Constant delay
RetryableCommand(
  baseCommand,
  maxAttempts: 3,
  onRetry: RetryStrategies.constantDelay(
    delay: Duration(seconds: 2),
  ),
);
```

---

## Composing with Other Features

### With CommandTracker

```dart
// Track retry attempts
final tracker = FailureCountTracker<String, User>();
final retryableCommand = RetryableCommand(
  Command.createAsync(fetchUser, null),
  maxAttempts: 3,
);

tracker.attach(retryableCommand);

// Tracker sees all attempts (including retries)
```

### With ErrorHandlerRegistry

```dart
// Global handler sees final error (after all retries exhausted)
Command.errorRegistry.on<NetworkException>((e, ctx) {
  showErrorDialog('Network unavailable after retries');
});

final command = RetryableCommand(
  Command.createAsync(fetchData, null),
  maxAttempts: 3,
);

// Only calls global handler after attempt 3 fails
```

### Nested Decorators

```dart
// Wrap retryable command with another decorator
final loggingCommand = LoggingCommand(
  RetryableCommand(
    Command.createAsync(fetchData, null),
    maxAttempts: 3,
  ),
);

// Logs each retry attempt
```

---

## Design Decisions

### 1. Decorator Pattern

**Decision**: Use decorator rather than built-in retry config

**Reasons**:
- ✅ Keeps Command class simple
- ✅ Fully opt-in (zero overhead if not used)
- ✅ Composable (can wrap any command)
- ✅ Follows single responsibility principle

### 2. Flexible RetryStrategy

**Decision**: Allow strategy to change command and parameters

**Reasons**:
- ✅ Enables powerful patterns (fallback APIs, batch size reduction)
- ✅ Not limited to "retry same thing"
- ✅ Users can implement custom logic

### 3. Attempt Number in shouldRetry

**Decision**: Pass attempt number to shouldRetry predicate

**Reasons**:
- ✅ Can stop retrying after N attempts per error type
- ✅ Different logic for first vs subsequent retries
- ✅ More flexible than just maxAttempts

### 4. Async onRetry?

**Decision**: TBD - Should onRetry be async?

```dart
// Current: Sync
RetryStrategy<TParam, TResult> = RetryAction<TParam, TResult> Function(...);

// Alternative: Async
RetryStrategy<TParam, TResult> = Future<RetryAction<TParam, TResult>> Function(...);
```

**Pros of async**:
- ✅ Can refresh auth tokens before retry
- ✅ Can fetch fallback configuration

**Cons of async**:
- ❌ More complex
- ❌ Most retries don't need async

**Possible solution**: Both?
```dart
RetryableCommand(
  ...,
  onRetry: simpleStrategy,      // Sync
  onRetryAsync: asyncStrategy,  // Async (if needed)
);
```

---

## Error Flow

```
User calls command
  ↓
Command executes → Error occurs
  ↓
RetryableCommand intercepts error
  ↓
shouldRetry(error, 1) → true
  ↓
onRetry(error, param, 1) → RetryAction
  ↓
Execute action (wait delay)
  ↓
Command executes → Error occurs
  ↓
shouldRetry(error, 2) → true
  ↓
onRetry(error, param, 2) → RetryAction
  ↓
...repeat until maxAttempts or success...
  ↓
If max attempts reached:
  Final error propagates to ErrorFilter → ErrorHandlerRegistry → globalExceptionHandler
```

---

## Relationship to Other Features

| Feature | Purpose | Interaction |
|---------|---------|-------------|
| **RetryableCommand** | Automatic retry with flexible strategies | Intercepts errors before they propagate |
| **ErrorFilter** | Route errors to local vs global handlers | Sees final error after retries exhausted |
| **ErrorHandlerRegistry** | Global type-based error routing | Sees final error after retries exhausted |
| **ErrorMiddleware** | Cross-cutting error processing | Processes final error after retries exhausted |
| **CommandTracker** | Per-command metrics | Can track retry attempts if attached |

**Retry happens BEFORE error handling system**:
```
Error → Retry → (if exhausted) → ErrorFilter → Middleware → Registry → Global Handler
```

---

## Open Questions

1. **Should onRetry be async?**
   - Allow async token refresh, config fetching, etc.
   - Or provide separate `onRetryAsync` parameter?

2. **Should there be a way to cancel ongoing retries?**
   ```dart
   final retryable = RetryableCommand(...);
   retryable.execute('param');
   // Later: cancel retries
   retryable.cancelRetries();
   ```

3. **Should retry state be observable?**
   ```dart
   final retryable = RetryableCommand(...);
   retryable.currentAttempt;  // ValueListenable<int>
   retryable.isRetrying;      // ValueListenable<bool>
   ```

4. **Should there be retry events?**
   ```dart
   retryable.onRetryAttempt.listen((attempt) {
     print('Retry attempt $attempt');
   });
   ```

5. **Should RetryableCommand implement Command interface exactly?**
   - Or extend it with retry-specific properties?
   - Trade-off: purity vs convenience

---

## Next Steps

1. Review API design
2. Decide on open questions
3. Implement RetryableCommand decorator
4. Implement built-in retry strategies
5. Add comprehensive tests
6. Document best practices
7. Create examples
8. Update DECLARATIVE_ERROR_HANDLING_SPEC.md to remove RetryMiddleware

---

## Migration Note

**Removing RetryMiddleware from global middleware:**

RetryMiddleware was initially proposed as global middleware, but retry is command-specific rather than cross-cutting. This decorator approach provides:
- ✅ Per-command configuration (not global)
- ✅ More flexibility (parameter adjustment, command switching)
- ✅ Better separation of concerns

Global ErrorMiddleware should focus on truly cross-cutting concerns:
- ✅ Logging (all errors)
- ✅ Deduplication (prevent spam)
- ✅ Analytics/Sentry (reporting)
- ❌ Retry (command-specific - use RetryableCommand instead)
