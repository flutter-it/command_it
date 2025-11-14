# Command Patterns Knowledge Base

**Source**: Analysis of production Flutter application with 164 command instances
**Date**: November 2025
**Purpose**: Generic command_it usage patterns and best practices

---

## Table of Contents

1. [Command Usage Patterns](#command-usage-patterns)
2. [Error Handling Architecture](#error-handling-architecture)
3. [Common Error Filter Patterns](#common-error-filter-patterns)
4. [Error Type Handling Strategies](#error-type-handling-strategies)
5. [Undoable Command Patterns](#undoable-command-patterns)
6. [Command Lifecycle Management](#command-lifecycle-management)
7. [Command Chaining Patterns](#command-chaining-patterns)
8. [Cross-Cutting Concerns](#cross-cutting-concerns)
9. [Best Practices](#best-practices)
10. [Anti-Patterns](#anti-patterns)

---

## Command Usage Patterns

### Command Type Distribution

In production applications, async commands dominate:

- **Async NoParamNoResult** (~40%): Data refreshing, mutations without return
- **Async with full params** (~30%): Parameterized operations with results
- **Async NoParam with Result** (~15%): Fetching operations
- **Async NoResult with Param** (~10%): Mutations with parameter
- **Undoable commands** (~12%): Optimistic UI updates
- **Sync commands** (~3%): Event stream transformations only

### Where Commands Live

**Manager/Service Classes** (~60%)
- Centralized business logic
- Multiple related commands per manager
- Example: PaymentManager, UserManager, ChatManager

```dart
class PaymentManager {
  late final getPaymentMethodsCommand = Command.createAsyncNoParam<List<PaymentMethod>>(...);
  late final addPaymentMethodCommand = Command.createAsyncNoResult<PaymentMethodData>(...);
  late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(...);
  late final setDefaultPaymentMethodCommand = Command.createAsyncNoResult<String>(...);
}
```

**Proxy/Model Classes** (~30%)
- Commands tied to specific data objects
- Instance-specific operations
- Example: ItemProxy, OrderProxy, MessageProxy

```dart
class ItemProxy extends ChangeNotifier {
  final String id;

  late final loadDetailsCommand = Command.createAsyncNoParamNoResult(...);
  late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<int>(...);
  late final purchaseCommand = Command.createAsync<PurchaseParams, Order>(...);
}
```

**Data Source Classes** (~10%)
- Pagination and data loading
- Example: FeedDataSource, ListDataSource

```dart
class FeedDataSource {
  late final updateDataCommand = Command.createAsyncNoParamNoResult(...);
  late final requestNextPageCommand = Command.createAsyncNoParamNoResult(...);
}
```

### Debug Naming Patterns

**String Constant Approach**:
```dart
// command_names.dart
const String cmdGetPaymentMethods = 'getPaymentMethods';
const String cmdAddPaymentMethod = 'addPaymentMethod';

// usage
late final addPaymentMethodCommand = Command.createAsync(
  _addPaymentMethod,
  null,
  debugName: cmdAddPaymentMethod,
);
```

**Inline String Approach**:
```dart
late final addPaymentMethodCommand = Command.createAsync(
  _addPaymentMethod,
  null,
  debugName: 'addPaymentMethod',
);
```

**Reality**: ~60% of commands have debugName, ~40% omit it

---

## Error Handling Architecture

### Three-Layer Error Handling

#### Layer 1: Global Error Handler

**Purpose**: Catch-all for unhandled errors, centralized logging

```dart
void setupGlobalErrorHandler() {
  Command.globalExceptionHandler = (error, stackTrace) {
    // 1. Console logging (debug builds)
    if (kDebugMode) {
      print('Command Error: ${error.error}');
      print('Command Name: ${error.commandName}');
    }

    // 2. Crash reporting (all builds)
    crashReporter.captureException(
      error.error,
      stackTrace: stackTrace,
      extras: {'commandName': error.commandName},
    );

    // 3. Special case handling
    if (error.error is UnauthorizedException) {
      navigationService.showLoginModal();
      return;
    }

    if (error.error is ApiException) {
      final apiError = error.error as ApiException;

      // 401: Authentication required
      if (apiError.statusCode == 401) {
        navigationService.showLoginModal();
        return;
      }

      // 403: Log but don't show toast (local handlers provide context)
      if (apiError.statusCode == 403) {
        crashReporter.captureException(error.error);
        return;
      }

      // 404: Expected errors, log as messages
      if (apiError.statusCode == 404) {
        crashReporter.captureMessage('404 from ${error.commandName}');
        return;
      }
    }

    // 4. Generic error toast
    toastService.showError(
      getErrorMessage(error.error),
    );
  };
}
```

**Key Principles**:
- Differentiate error types (401, 403, 404 have different meanings)
- 403s often need local context, don't show generic message
- 404s may be "expected" in optimistic scenarios
- Always log to crash reporting with command context

#### Layer 2: Error Filters

**Purpose**: Route errors to appropriate handlers per command

```dart
// Route to local handler only (show in UI, don't toast)
errorFilter: const ErrorHandlerLocal()

// Route to global handler only (background operations)
errorFilter: const ErrorHandlerGlobalOnly()

// Try local, fallback to global (default behavior)
errorFilter: const ErrorHandlerGlobalIfNoLocal()

// HTTP status code routing
errorFilter: HttpStatusCodeErrorFilter([403, 404], ErrorReaction.localHandler)

// Complex multi-library routing
errorFilter: PredicatesErrorFilter([
  (e, s) => e is PaymentCancelledException ? ErrorReaction.none : null,
  (e, s) => e is PaymentException ? ErrorReaction.localHandler : null,
  (e, s) => e is ApiException ? ErrorReaction.localAndGlobalHandler : null,
  (e, s) => ErrorReaction.globalHandler,
])
```

#### Layer 3: Error Listeners

**Purpose**: Command-specific error handling with context

```dart
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  _deletePaymentMethod,
  errorFilter: HttpStatusCodeErrorFilter([404, 403], ErrorReaction.localHandler),
)..errors.listen((error, _) {
  final context = navigationService.currentContext;

  if (error!.error is ApiException) {
    final apiError = error.error as ApiException;

    String message;
    if (apiError.statusCode == 404) {
      message = context.l10n.paymentMethodNotFound;
    } else if (apiError.statusCode == 403) {
      message = context.l10n.cannotDeletePaymentMethod;
    } else {
      message = context.l10n.genericError;
    }

    toastService.show(message);
  }
});
```

### Error Routing Decision Tree

```
Error occurs in command
  ↓
Error filter evaluates error
  ↓
  ├─ ErrorReaction.none → Error swallowed (e.g., user cancellation)
  │
  ├─ ErrorReaction.localHandler → Call .errors listeners only
  │
  ├─ ErrorReaction.globalHandler → Call globalExceptionHandler only
  │
  ├─ ErrorReaction.localAndGlobalHandler → Call both
  │
  ├─ ErrorReaction.firstLocalThenGlobalHandler (DEFAULT)
  │   ↓
  │   Has .errors listeners? ─ Yes → Call local only
  │   │
  │   └─ No → Call global handler
  │
  └─ ErrorReaction.throwException → Rethrow immediately
```

---

## Common Error Filter Patterns

### Pattern 1: Function-Based Filter

**Use case**: Ad-hoc filtering with inline logic

```dart
class ErrorFilterFunction extends ErrorFilter {
  final ErrorReaction Function(Object error) filterFunction;

  ErrorFilterFunction(this.filterFunction);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return filterFunction(error);
  }
}

// Usage
errorFilter: ErrorFilterFunction((error) {
  if (error is NetworkException) return ErrorReaction.localHandler;
  if (error is CacheException) return ErrorReaction.none;
  return ErrorReaction.globalHandler;
})
```

### Pattern 2: HTTP Status Code Filter

**Use case**: Route API errors by status code

```dart
class HttpStatusCodeErrorFilter implements ErrorFilter {
  final List<int> statusCodes;
  final ErrorReaction reaction;

  HttpStatusCodeErrorFilter(this.statusCodes, this.reaction);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      if (statusCodes.isEmpty || statusCodes.contains(error.statusCode)) {
        return reaction;
      }
    }
    return ErrorReaction.globalHandler;
  }
}

// Usage examples
errorFilter: HttpStatusCodeErrorFilter([404], ErrorReaction.localHandler)
errorFilter: HttpStatusCodeErrorFilter([403, 422], ErrorReaction.localHandler)
errorFilter: HttpStatusCodeErrorFilter([], ErrorReaction.localHandler) // All codes
```

### Pattern 3: API Error Filter with Predicate

**Use case**: Conditional routing based on error properties

```dart
class ApiErrorFilter extends ErrorFilter {
  final bool Function(ApiException error) test;
  final ErrorReaction reaction;

  ApiErrorFilter(this.test, this.reaction);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ApiException && test(error)) {
      return reaction;
    }
    return ErrorReaction.globalHandler;
  }
}

// Usage
errorFilter: ApiErrorFilter(
  (e) => e.statusCode == 403 && e.message.contains('rate limit'),
  ErrorReaction.localHandler,
)
```

### Pattern 4: Local Only Filter

**Use case**: UI components that show errors in-place

```dart
class LocalOnlyErrorFilter implements ErrorFilter {
  const LocalOnlyErrorFilter();

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return ErrorReaction.localHandler;
  }
}

// Usage: Feed/list data sources
class FeedDataSource {
  late final updateDataCommand = Command.createAsyncNoParamNoResult(
    _updateData,
    errorFilter: const LocalOnlyErrorFilter(), // Show error in feed UI
  );
}
```

**Rationale**: Feed errors should appear in the feed container, not as global toasts

### Pattern 5: Global Only Filter

**Use case**: Background operations where user shouldn't see errors

```dart
class GlobalOnlyErrorFilter implements ErrorFilter {
  const GlobalOnlyErrorFilter();

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return ErrorReaction.globalHandler;
  }
}

// Usage: Background polling, prefetching
late final prefetchDataCommand = Command.createAsyncNoParamNoResult(
  _prefetchData,
  errorFilter: const GlobalOnlyErrorFilter(), // Log to crash reporter only
);
```

### Pattern 6: Composite Status Code Filter

**Use case**: Different reactions for different status codes

```dart
class CompositeStatusCodeFilter implements ErrorFilter {
  final Map<int, ErrorReaction> reactions;
  final ErrorReaction defaultReaction;

  CompositeStatusCodeFilter(this.reactions, this.defaultReaction);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    if (error is ApiException) {
      return reactions[error.statusCode] ?? defaultReaction;
    }
    return defaultReaction;
  }
}

// Usage
errorFilter: CompositeStatusCodeFilter({
  404: ErrorReaction.localAndGlobalHandler, // Data inconsistency bug
  403: ErrorReaction.localHandler,           // Business logic denial
  422: ErrorReaction.localHandler,           // Validation error
}, ErrorReaction.globalHandler)
```

### Pattern 7: Predicate Chain Filter

**Use case**: Complex multi-library error scenarios

```dart
class PredicatesErrorFilter implements ErrorFilter {
  final List<ErrorReaction? Function(Object, StackTrace)> predicates;

  PredicatesErrorFilter(this.predicates);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    for (final predicate in predicates) {
      final reaction = predicate(error, stackTrace);
      if (reaction != null) return reaction;
    }
    return ErrorReaction.globalHandler;
  }
}

// Usage: Payment flow with Stripe + API
errorFilter: PredicatesErrorFilter([
  // User cancelled payment sheet
  (e, s) => e is StripeException && e.code == 'canceled'
      ? ErrorReaction.none
      : null,

  // Stripe declined card
  (e, s) => e is StripeException && e.code == 'card_declined'
      ? ErrorReaction.localHandler
      : null,

  // Other Stripe errors
  (e, s) => e is StripeException
      ? ErrorReaction.localHandler
      : null,

  // API errors (backend validation)
  (e, s) => e is ApiException
      ? ErrorReaction.localAndGlobalHandler
      : null,

  // Everything else
  (e, s) => ErrorReaction.globalHandler,
])
```

### Pattern 8: Type-Based Error Filter

**Use case**: Route by error type, not properties

```dart
class ErrorTypeFilter extends ErrorFilter {
  final Map<Type, ErrorReaction> reactions;
  final ErrorReaction defaultReaction;

  ErrorTypeFilter(this.reactions, this.defaultReaction);

  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    return reactions[error.runtimeType] ?? defaultReaction;
  }
}

// Usage
errorFilter: ErrorTypeFilter({
  NetworkException: ErrorReaction.localHandler,
  CacheException: ErrorReaction.none,
  ValidationException: ErrorReaction.localHandler,
}, ErrorReaction.globalHandler)
```

---

## Error Type Handling Strategies

### HTTP Status Code Semantics

#### 401 Unauthorized

**Meaning**: User not authenticated

**Strategy**:
- Global handler only
- Show login/auth modal
- Don't show error toast

```dart
// Global handler
if (error.statusCode == 401) {
  navigationService.showAuthModal();
  return; // Don't show toast
}
```

**Filter**: Not needed (global handler catches all)

#### 403 Forbidden

**Two Categories**:

1. **Business Logic Denial**: Expected, user-friendly message needed
   - Example: "Cannot favorite this item during checkout"
   - Example: "Action not allowed in this time window"
   - **Strategy**: Local handler with custom toast

2. **Unexpected Denial**: Potential bug, needs investigation
   - Example: "User should have permission but doesn't"
   - **Strategy**: Local + global (custom toast + Sentry)

```dart
// Category 1: Expected business logic
errorFilter: HttpStatusCodeErrorFilter([403], ErrorReaction.localHandler),
)..errors.listen((error, _) {
  // Show user-friendly message
  toastService.show(context.l10n.actionNotAllowedMessage);
});

// Category 2: Unexpected (data inconsistency)
errorFilter: CompositeStatusCodeFilter({
  403: ErrorReaction.localAndGlobalHandler,
}, ErrorReaction.globalHandler),
)..errors.listen((error, _) {
  // Show custom message
  toastService.show(context.l10n.somethingWentWrong);
  // Global handler will log to Sentry
});
```

**Global Handler Strategy**:
```dart
if (error.statusCode == 403) {
  crashReporter.captureException(error);
  return; // Don't show generic toast, local handler should provide context
}
```

#### 404 Not Found

**Two Categories**:

1. **Expected 404**: Optimistic fetching, race conditions
   - Example: "Load item that might be deleted"
   - **Strategy**: Log as message (not exception), local handler shows UI

2. **Unexpected 404**: Data inconsistency bug
   - Example: "Backend said item exists, now 404"
   - **Strategy**: Local + global (custom toast + Sentry exception)

```dart
// Category 1: Expected 404
errorFilter: HttpStatusCodeErrorFilter([404], ErrorReaction.localHandler),
)..errors.listen((error, _) {
  // Update UI to show "item not found" state
  notifyItemDeleted();
});

// Global handler logs as message
if (error.statusCode == 404) {
  crashReporter.captureMessage('404 from ${commandName}');
  return; // Don't treat as exception
}

// Category 2: Unexpected 404 (data inconsistency)
errorFilter: CompositeStatusCodeFilter({
  404: ErrorReaction.localAndGlobalHandler,
}, ErrorReaction.globalHandler),
)..errors.listen((error, _) {
  toastService.show(context.l10n.dataInconsistencyError);
  // Global handler will log as exception to Sentry
});
```

#### 422 Unprocessable Entity

**Meaning**: Validation error, user input issue

**Strategy**:
- Local handler only
- Show specific validation message
- Don't log to crash reporter (expected error)

```dart
errorFilter: HttpStatusCodeErrorFilter([422], ErrorReaction.localHandler),
)..errors.listen((error, _) {
  final apiError = error!.error as ApiException;

  // Parse validation errors from response
  final validationErrors = parseValidationErrors(apiError.response);

  // Show field-specific errors
  formState.setErrors(validationErrors);
});
```

### Non-HTTP Error Types

#### Network Exceptions

**Examples**: Timeout, connection refused, DNS failure

**Strategy**:
- Local handler with retry option
- Or global handler with generic "network error" toast

```dart
errorFilter: ErrorTypeFilter({
  TimeoutException: ErrorReaction.localHandler,
  SocketException: ErrorReaction.localHandler,
}, ErrorReaction.globalHandler),
)..errors.listen((error, _) {
  toastService.showWithAction(
    context.l10n.networkError,
    action: ToastAction(
      label: context.l10n.retry,
      onPressed: () => command.run(lastParam),
    ),
  );
});
```

#### User Cancellation

**Examples**: Payment cancelled, dialog dismissed

**Strategy**: Silent (ErrorReaction.none)

```dart
errorFilter: PredicatesErrorFilter([
  (e, s) => e is UserCancelledException ? ErrorReaction.none : null,
  (e, s) => e is PaymentCancelledException ? ErrorReaction.none : null,
  (e, s) => ErrorReaction.globalHandler,
])
```

#### Deserialization Errors

**Meaning**: API response doesn't match expected schema

**Strategy**:
- Always log to crash reporter (indicates API change or bug)
- Global handler shows generic error
- Consider alerting backend team

```dart
// Cross-cutting concern (all filters should report)
void reportDeserializationError(Object error) {
  if (error is DeserializationException) {
    crashReporter.captureException(
      error,
      level: SentryLevel.error,
      extras: {
        'endpoint': error.endpoint,
        'expectedType': error.expectedType,
      },
    );

    // Optional: Alert backend team
    if (kReleaseMode) {
      backendAlertService.notifySchemaIssue(error);
    }
  }
}
```

---

## Undoable Command Patterns

### Pattern 1: Simple State Snapshot

**Use case**: Single value optimistic update

```dart
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<bool>(
  () async {
    final snapshot = isFavorite;

    // Optimistic update
    _isFavorite = !_isFavorite;
    notifyListeners();

    // API call
    await api.toggleFavorite(itemId);

    return snapshot;
  },
  undo: (stack, error) {
    _isFavorite = stack.pop();
    notifyListeners();
  },
);
```

### Pattern 2: Multiple Value Snapshot (Tuple)

**Use case**: Multiple related values change together

```dart
late final markAsReadCommand = Command.createUndoableNoParamNoResult<(int, bool?)>(
  () async {
    final snapshot = (unreadCount, isReadOverride);

    // Optimistic update
    isReadOverride = true;
    unreadCount = 0;
    notifyListeners();

    // API call
    await api.markAsRead(itemId);

    return snapshot;
  },
  undo: (stack, error) {
    final (oldCount, oldIsRead) = stack.pop();
    unreadCount = oldCount;
    isReadOverride = oldIsRead;
    notifyListeners();
  },
);
```

### Pattern 3: Complex Object Snapshot

**Use case**: Entire object needs restoration

```dart
late final votePollCommand = Command.createUndoableNoResult<int, PollDto>(
  (optionIndex) async {
    final snapshot = poll.copyWith();  // Deep copy

    // Optimistic update
    poll.userVote = optionIndex;
    poll.options[optionIndex].voteCount++;
    notifyListeners();

    // API call
    await api.votePoll(pollId, optionIndex);

    return snapshot;
  },
  undo: (stack, error) {
    poll = stack.pop();
    notifyListeners();
  },
);
```

### Pattern 4: Counter with Overflow Protection

**Use case**: Optimistic increment/decrement with bounds

```dart
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<int>(
  () async {
    final favoriteCountSnapshot = favoriteCount;

    // Optimistic update with bounds checking
    if (isFavorite) {
      _favoriteCount = max(0, _favoriteCount - 1);
    } else {
      _favoriteCount = _favoriteCount + 1;
    }
    _isFavoriteOverride = !isFavorite;
    notifyListeners();

    // API call
    await api.toggleFavorite(itemId);

    return favoriteCountSnapshot;
  },
  undo: (stack, error) {
    final originalCount = stack.pop();
    _favoriteCount = originalCount;
    _isFavoriteOverride = null;
    notifyListeners();
  },
);
```

### Pattern 5: List Modification

**Use case**: Add/remove items optimistically

```dart
late final deleteItemCommand = Command.createUndoableNoResult<String, ItemDto>(
  (itemId) async {
    final item = _items.firstWhere((i) => i.id == itemId);
    final snapshot = item;

    // Optimistic removal
    _items.removeWhere((i) => i.id == itemId);
    notifyListeners();

    // API call
    await api.deleteItem(itemId);

    return snapshot;
  },
  undo: (stack, error) {
    final deletedItem = stack.pop();
    _items.add(deletedItem);
    _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  },
);
```

### Pattern 6: Cascading State Updates

**Use case**: One change affects multiple related states

```dart
late final acceptOrderCommand = Command.createUndoableNoResult<String, OrderSnapshot>(
  (orderId) async {
    final snapshot = OrderSnapshot(
      order: order,
      sellerActiveOrders: seller.activeOrderCount,
      buyerPendingOrders: buyer.pendingOrderCount,
    );

    // Optimistic updates across multiple objects
    order.status = OrderStatus.accepted;
    seller.activeOrderCount++;
    buyer.pendingOrderCount--;
    notifyListeners();

    // API call
    await api.acceptOrder(orderId);

    return snapshot;
  },
  undo: (stack, error) {
    final snapshot = stack.pop();
    order.status = snapshot.order.status;
    seller.activeOrderCount = snapshot.sellerActiveOrders;
    buyer.pendingOrderCount = snapshot.buyerPendingOrders;
    notifyListeners();
  },
);
```

### Undo on Specific Errors Only

**Pattern**: Don't undo on validation errors (422), only on real failures

```dart
late final updateProfileCommand = Command.createUndoable<ProfileData, void, ProfileData>(
  (newData) async {
    final snapshot = currentProfile;

    // Optimistic update
    currentProfile = newData;
    notifyListeners();

    // API call (may throw 422 validation error)
    await api.updateProfile(newData);

    return snapshot;
  },
  undo: (stack, error) {
    // Only undo on non-validation errors
    if (error is ApiException && error.statusCode == 422) {
      return; // Keep optimistic state, let validation errors show
    }

    currentProfile = stack.pop();
    notifyListeners();
  },
);
```

---

## Command Lifecycle Management

### Listening to Execution State

**Pattern**: Update loading indicators

```dart
late final loadDataCommand = Command.createAsyncNoParam<Data>(_loadData, null);

void initState() {
  super.initState();

  loadDataCommand.isRunning.listen((isLoading, _) {
    setState(() {
      _isLoading = isLoading;
    });
  });
}
```

### Listening to Results

**Pattern**: Success actions without error handling

```dart
late final deleteAccountCommand = Command.createAsyncNoParamNoResult(_deleteAccount);

void initState() {
  super.initState();

  deleteAccountCommand.listen((_, __) {
    // Called only on success
    authService.logout();
    navigationService.navigateToLogin();
  });
}
```

### Listening to Errors

**Pattern**: Error-specific UI updates

```dart
late final loginCommand = Command.createAsync<Credentials, User>(_login, null);

void initState() {
  super.initState();

  loginCommand.errors.listen((error, _) {
    if (error!.error is InvalidCredentialsException) {
      setState(() {
        _showInvalidCredentialsMessage = true;
      });
    } else if (error.error is AccountLockedException) {
      setState(() {
        _showAccountLockedMessage = true;
      });
    }
  });
}
```

### Merging Multiple Command Errors

**Pattern**: Single error handler for related commands

```dart
class ItemProxy extends ChangeNotifier {
  late final toggleFavoriteCommand = Command.createUndoable<...>(...);
  late final togglePinnedCommand = Command.createUndoable<...>(...);
  late final shareCommand = Command.createAsync<...>(...);

  late final ValueListenable<CommandError?> _allErrors;
  late final StreamSubscription _errorSubscription;

  ItemProxy() {
    // Merge all command errors into single stream
    _allErrors = toggleFavoriteCommand.errors.mergeWith([
      togglePinnedCommand.errors,
      shareCommand.errors,
    ]);

    _errorSubscription = _allErrors.listen((error, _) {
      if (error!.error is ApiException) {
        final apiError = error.error as ApiException;
        if (apiError.statusCode == 403 || apiError.statusCode == 404) {
          handleItemAccessError(apiError);
        }
      }
    });
  }

  @override
  void dispose() {
    _errorSubscription.cancel();
    toggleFavoriteCommand.dispose();
    togglePinnedCommand.dispose();
    shareCommand.dispose();
    super.dispose();
  }
}
```

### Command Result Value Access Patterns

**Pattern 1: Direct value access**
```dart
final currentData = loadDataCommand.value; // Latest result or initialValue
```

**Pattern 2: Result with metadata**
```dart
final result = loadDataCommand.results.value;
if (result.hasData) {
  final data = result.data;
  final param = result.paramData;
}
```

**Pattern 3: Error checking**
```dart
final result = loadDataCommand.results.value;
if (result.hasError) {
  final error = result.error;
  final stackTrace = result.stackTrace;
}
```

---

## Command Chaining Patterns

### Pattern 1: Sequential Execution

**Use case**: After one command succeeds, trigger another

```dart
late final createOrderCommand = Command.createAsync<OrderParams, Order>(
  (params) async {
    final order = await api.createOrder(params);

    // Refresh related data
    getOrdersCommand.run();
    getBalanceCommand.run();

    // Show success feedback
    toastService.showSuccess(context.l10n.orderCreated);

    return order;
  },
);
```

### Pattern 2: Conditional Chaining

**Use case**: Next command depends on first command's result

```dart
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  (paymentMethodId) async {
    final currentMethods = getPaymentMethodsCommand.value ?? [];
    final methodToDelete = currentMethods.firstWhereOrNull((m) => m.id == paymentMethodId);

    // If deleting default method, set new default first
    if (methodToDelete?.isDefault == true && currentMethods.length > 1) {
      final nextMethod = currentMethods.firstWhereOrNull(
        (m) => m.id != paymentMethodId
      );

      if (nextMethod != null) {
        await setDefaultPaymentMethodCommand.runAsync(nextMethod.id);
      }
    }

    // Now safe to delete
    await api.deletePaymentMethod(paymentMethodId);

    // Refresh list
    getPaymentMethodsCommand.run();
  },
);
```

### Pattern 3: Parallel Execution

**Use case**: Multiple independent operations

```dart
late final refreshDashboardCommand = Command.createAsyncNoParamNoResult(
  () async {
    await Future.wait([
      getOrdersCommand.runAsync(),
      getNotificationsCommand.runAsync(),
      getBalanceCommand.runAsync(),
    ]);
  },
);
```

### Pattern 4: Command as Restriction

**Use case**: Disable one command while another executes

```dart
late final loadDataCommand = Command.createAsyncNoParam<Data>(_loadData, null);

late final saveDataCommand = Command.createAsync<Data, void>(
  _saveData,
  null,
  restriction: loadDataCommand.isRunningSync, // Can't save while loading
);
```

### Pattern 5: Cascading Updates

**Use case**: Command updates multiple related proxy objects

```dart
late final purchaseListingCommand = Command.createAsync<PurchaseParams, Order>(
  (params) async {
    final orderDto = await api.storeOrder(params);

    // Refresh listing (will show "sold" state)
    params.listing.loadFullTargetCommand.run();

    // Refresh user's balance
    userManager.getBalanceCommand.run();

    // Return new order proxy
    return createOrderProxy(orderDto);
  },
);
```

---

## Cross-Cutting Concerns

### Deserialization Error Detection

**Problem**: API schema changes cause parsing failures

**Solution**: All error filters check for deserialization errors and report

```dart
void reportDeserializationError(Object error) {
  // Unwrap ApiException if needed
  if (error is ApiException && error.innerException is DeserializationException) {
    error = error.innerException!;
  }

  if (error is DeserializationException) {
    crashReporter.captureException(
      error,
      stackTrace: error.stackTrace,
      level: SentryLevel.error,
      extras: {
        'endpoint': error.endpoint,
        'rawResponse': error.rawResponse?.substring(0, 500),
      },
    );
  }
}

// Every custom error filter should call this
class MyCustomErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    reportDeserializationError(error); // Check for schema issues

    // ... rest of filter logic
  }
}
```

### Account State Detection

**Problem**: Detect when user account is locked/suspended

**Solution**: Check error messages for account state keywords

```dart
void checkForAccountStateChange(Object error) {
  if (error is ApiException && error.statusCode == 403) {
    final message = error.message?.toLowerCase() ?? '';

    if (message.contains('temporarily locked') || message.contains('suspended')) {
      authService.setUserState(UserState.accountLocked);
    }

    if (message.contains('deactivated') || message.contains('banned')) {
      authService.setUserState(UserState.accountDeactivated);
    }
  }
}

// Error filters should call this
class MyCustomErrorFilter implements ErrorFilter {
  @override
  ErrorReaction filter(Object error, StackTrace stackTrace) {
    reportDeserializationError(error);
    checkForAccountStateChange(error); // Detect account state changes

    // ... rest of filter logic
  }
}
```

### Reusable Error Handler Functions

**Pattern**: Extract common error handling logic

```dart
// Marketplace errors have consistent patterns
void handleMarketplaceApiError(
  CommandError? error, {
  required String custom404Message,
  required String custom403GenericMessage,
  String? custom422Message,
}) {
  if (error == null) return;

  final context = navigationService.currentContext;

  if (error.error is ApiException) {
    final apiError = error.error as ApiException;

    String message;
    if (apiError.statusCode == 404) {
      message = custom404Message;
    } else if (apiError.statusCode == 403) {
      // Try to parse backend message
      final backendMessage = parseApiErrorMessage(apiError.message);
      if (backendMessage != null && !isGeneric403Message(backendMessage)) {
        message = backendMessage;
      } else {
        message = custom403GenericMessage;
      }
    } else if (apiError.statusCode == 422 && custom422Message != null) {
      message = custom422Message;
    } else {
      message = parseApiErrorMessage(apiError.message) ??
                getErrorTitle(context, apiError);
    }

    toastService.show(message);
  }
}

// Usage across many commands
late final deletePaymentMethodCommand = Command.createAsyncNoResult<String>(
  _deletePaymentMethod,
  errorFilter: CompositeStatusCodeFilter({
    404: ErrorReaction.localHandler,
    403: ErrorReaction.localHandler,
  }, ErrorReaction.globalHandler),
)..errors.listen((error, _) {
  handleMarketplaceApiError(
    error,
    custom404Message: context.l10n.paymentMethodNotFound,
    custom403GenericMessage: context.l10n.cannotDeletePaymentMethod,
  );
});
```

---

## Best Practices

### 1. Always Provide Debug Names

**Why**: Error logs are much more useful with command names

```dart
// ✅ GOOD
late final loadUserCommand = Command.createAsync(
  _loadUser,
  null,
  debugName: 'loadUser',
);

// ❌ BAD
late final loadUserCommand = Command.createAsync(_loadUser, null);
```

**Pro tip**: Use string constants for consistency

```dart
// command_names.dart
const String cmdLoadUser = 'loadUser';
const String cmdSaveUser = 'saveUser';

// usage
debugName: cmdLoadUser
```

### 2. Use Appropriate Error Filters

**Guideline**:
- **Feed/list data sources**: `LocalOnlyErrorFilter` (show errors in UI)
- **Background operations**: `GlobalOnlyErrorFilter` (log only)
- **User-initiated actions**: `ErrorHandlerGlobalIfNoLocal` (try local, fallback global)
- **Payment/critical flows**: Custom filters with multiple error types

### 3. Dispose Commands Properly

**Pattern**: Always dispose commands in StatefulWidget or ChangeNotifier

```dart
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final loadDataCommand = Command.createAsync<...>(...);

  @override
  void dispose() {
    loadDataCommand.dispose();
    super.dispose();
  }
}
```

### 4. Use includeLastResultInCommandResults for Data Persistence

**Pattern**: Keep showing old data while loading new data

```dart
late final loadItemsCommand = Command.createAsyncNoParam<List<Item>>(
  _loadItems,
  [],
  includeLastResultInCommandResults: true, // Keep old data visible
);

// UI shows old items + loading spinner, not just loading spinner
```

### 5. Provide Initial Values

**Why**: Prevents null-related errors, gives better UX

```dart
// ✅ GOOD: Empty list as initial value
late final loadItemsCommand = Command.createAsyncNoParam<List<Item>>(
  _loadItems,
  [], // Empty list initially
);

// ❌ BAD: Null initial value requires null checks everywhere
late final loadItemsCommand = Command.createAsyncNoParam<List<Item>?>(
  _loadItems,
  null,
);
```

### 6. Use Undoable Commands for Optimistic Updates

**When to use**:
- User actions that should feel instant (favorites, votes, follows)
- Operations that rarely fail
- Actions where rollback is straightforward

```dart
// ✅ GOOD: Undoable for instant feedback
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<bool>(
  () async {
    final snapshot = isFavorite;
    _isFavorite = !_isFavorite;
    notifyListeners();

    await api.toggleFavorite(itemId);
    return snapshot;
  },
  undo: (stack, error) {
    _isFavorite = stack.pop();
    notifyListeners();
  },
);
```

### 7. Prefer Local Error Handlers for User-Facing Errors

**Guideline**: If error message needs context, use local handler

```dart
// ✅ GOOD: Context-aware error message
errorFilter: const LocalOnlyErrorFilter(),
)..errors.listen((error, _) {
  if (error!.error is ApiException) {
    final apiError = error.error as ApiException;
    if (apiError.statusCode == 403) {
      // Show specific reason why action was forbidden
      toastService.show(context.l10n.cannotDeleteDefaultPaymentMethod);
    }
  }
});

// ❌ BAD: Generic global error message
errorFilter: const GlobalOnlyErrorFilter(),
// User sees generic "Something went wrong" toast
```

### 8. Use runAsync for Async Coordination

**Pattern**: When you need to await command completion

```dart
// ✅ GOOD: Await command in async function
Future<void> onRefresh() async {
  await loadDataCommand.runAsync();
}

// ✅ GOOD: Use with RefreshIndicator
RefreshIndicator(
  onRefresh: () => loadDataCommand.runAsync(),
  child: ListView(...),
)
```

---

## Anti-Patterns

### 1. ❌ Not Handling Errors

**Problem**: Errors disappear silently or show generic message

```dart
// ❌ BAD: No error filter, no error listener
late final loadDataCommand = Command.createAsync(_loadData, null);
```

**Solution**: Always provide error handling strategy

```dart
// ✅ GOOD: Explicit error handling
late final loadDataCommand = Command.createAsync(
  _loadData,
  null,
  errorFilter: const ErrorHandlerGlobalIfNoLocal(),
);
```

### 2. ❌ Using Sync Commands When You Need isRunning

**Problem**: Sync commands don't support execution state tracking

```dart
// ❌ BAD: Can't track execution state
late final processDataCommand = Command.createSync(_processData, null);

// This will throw assertion error:
processDataCommand.isRunning.listen(...); // ❌ ASSERTION FAILS
```

**Solution**: Use async commands for long-running operations

```dart
// ✅ GOOD: Async command supports isRunning
late final processDataCommand = Command.createAsync(_processData, null);

processDataCommand.isRunning.listen((isLoading, _) {
  setState(() => _isLoading = isLoading);
});
```

### 3. ❌ Forgetting to Dispose Commands

**Problem**: Memory leaks, subscription leaks

```dart
// ❌ BAD: Command never disposed
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final command = Command.createAsync(...);

  // Missing dispose()!
}
```

**Solution**: Always dispose in dispose() method

```dart
// ✅ GOOD: Command disposed
@override
void dispose() {
  command.dispose();
  super.dispose();
}
```

### 4. ❌ Storing Context in Commands

**Problem**: Stale BuildContext, memory leaks

```dart
// ❌ BAD: Storing context
class MyManager {
  BuildContext? _context;

  late final command = Command.createAsync(
    _execute,
    null,
  )..errors.listen((error, _) {
    // Using stored context - might be stale!
    showToast(_context!, error.toString());
  });
}
```

**Solution**: Access context when needed, don't store

```dart
// ✅ GOOD: Access context from navigation service or pass as parameter
class MyManager {
  late final command = Command.createAsync(
    _execute,
    null,
  )..errors.listen((error, _) {
    final context = navigationService.currentContext;
    showToast(context, error.toString());
  });
}
```

### 5. ❌ Using ErrorReaction.none for Real Errors

**Problem**: Errors disappear, making debugging impossible

```dart
// ❌ BAD: Swallowing all errors
errorFilter: ErrorFilterFunction((e) => ErrorReaction.none)
```

**Solution**: Only use .none for expected non-errors

```dart
// ✅ GOOD: Only swallow user cancellations
errorFilter: PredicatesErrorFilter([
  (e, s) => e is UserCancelledException ? ErrorReaction.none : null,
  (e, s) => ErrorReaction.globalHandler, // Everything else gets handled
])
```

### 6. ❌ Not Using Undoable Commands for Optimistic Updates

**Problem**: Manual rollback logic is error-prone and repetitive

```dart
// ❌ BAD: Manual rollback
late final toggleFavoriteCommand = Command.createAsync<void, void>(
  () async {
    final oldState = isFavorite;
    _isFavorite = !_isFavorite;
    notifyListeners();

    try {
      await api.toggleFavorite(itemId);
    } catch (e) {
      _isFavorite = oldState; // Manual rollback
      notifyListeners();
      rethrow;
    }
  },
  null,
);
```

**Solution**: Use undoable commands for automatic rollback

```dart
// ✅ GOOD: Automatic rollback on error
late final toggleFavoriteCommand = Command.createUndoableNoParamNoResult<bool>(
  () async {
    final snapshot = isFavorite;
    _isFavorite = !_isFavorite;
    notifyListeners();
    await api.toggleFavorite(itemId);
    return snapshot;
  },
  undo: (stack, error) {
    _isFavorite = stack.pop();
    notifyListeners();
  },
);
```

### 7. ❌ Catching Errors Inside Command Functions

**Problem**: Bypasses command_it's error handling system

```dart
// ❌ BAD: Catching errors inside command function
late final loadDataCommand = Command.createAsync(
  () async {
    try {
      return await api.loadData();
    } catch (e) {
      // Error never reaches error filter or listeners!
      print('Error: $e');
      return [];
    }
  },
  [],
);
```

**Solution**: Let errors propagate, handle via filter/listeners

```dart
// ✅ GOOD: Errors propagate to error handling system
late final loadDataCommand = Command.createAsync(
  () async {
    return await api.loadData(); // Let errors throw
  },
  [],
  errorFilter: const ErrorHandlerGlobalIfNoLocal(),
)..errors.listen((error, _) {
  // Handle error here
  print('Error: ${error!.error}');
});
```

### 8. ❌ Creating Commands in Widget build() Method

**Problem**: New command instance on every rebuild, subscriptions leak

```dart
// ❌ BAD: Command created on every build
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final command = Command.createAsync(_loadData, null); // ❌ NEW INSTANCE!

    return CommandBuilder(command: command, ...);
  }
}
```

**Solution**: Create commands in initState() or as class fields

```dart
// ✅ GOOD: Command created once
class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late final command = Command.createAsync(_loadData, null);

  @override
  Widget build(BuildContext context) {
    return CommandBuilder(command: command, ...);
  }

  @override
  void dispose() {
    command.dispose();
    super.dispose();
  }
}
```

---

## Summary

This knowledge base captures patterns from a production app with 164 command instances. Key takeaways:

1. **Three-layer error handling** (global → filter → listener) provides flexibility
2. **Eight common error filter patterns** cover most use cases
3. **HTTP status codes have semantic meaning** (401, 403, 404, 422 handled differently)
4. **Undoable commands** are essential for optimistic UI updates
5. **Cross-cutting concerns** (deserialization, account state) belong in error filters
6. **Command chaining** enables complex workflows
7. **Always dispose** commands to prevent leaks
8. **Debug names** are crucial for production debugging

The patterns documented here represent battle-tested approaches from real-world usage.
