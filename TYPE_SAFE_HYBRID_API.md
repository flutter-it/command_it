# Type-Safe Hybrid API - Compile-Time Function Validation

**Date**: November 9, 2025
**User Concern**: "We should be able to check if the function fulfills a needed function type"

---

## The Problem with `Object?`

### Current Proposal Has Type Safety Issue

```dart
// With Object? parameter
Command.createAsync(
  fetchData,
  [],
  errorFilter: (String e) => ErrorReaction.local,  // WRONG signature!
);
// Compiles fine! Error only at runtime when is-check fails
```

**Issue**: Dart allows ANY function to be passed to `Object?` parameter, losing compile-time validation.

---

## Runtime Check Analysis

Let's verify what the `is` check actually validates:

```dart
typedef ErrorFilterFn = ErrorReaction? Function(
  Object error,
  StackTrace stackTrace,
);

void test() {
  // Correct signatures
  var f1 = (Object e, StackTrace s) => null;
  print(f1 is ErrorFilterFn);  // true ✓

  var f2 = (dynamic e, dynamic s) => null;
  print(f2 is ErrorFilterFn);  // true ✓ (dynamic is supertype)

  var f3 = (e, s) => null;  // Type inference
  print(f3 is ErrorFilterFn);  // depends on inference

  // Wrong signatures
  var f4 = (String e, StackTrace s) => null;  // More specific param type
  print(f4 is ErrorFilterFn);  // false ✓ - Dart is contravariant on parameters

  var f5 = (Object e) => null;  // Wrong arity
  print(f5 is ErrorFilterFn);  // false ✓

  var f6 = (Object e, StackTrace s) => 'string';  // Wrong return type
  print(f6 is ErrorFilterFn);  // false ✓ - not assignable to ErrorReaction?

  var f7 = (Object e, StackTrace s, int x) => null;  // Too many params
  print(f7 is ErrorFilterFn);  // false ✓
}
```

**Good news**: Runtime check DOES validate:
- ✅ Parameter count (arity)
- ✅ Parameter types (contravariance)
- ✅ Return type (covariance)

**Bad news**: This is RUNTIME checking, not compile-time!

---

## Solution 1: Keep `Object?` But Document Behavior

### Validation Strategy

```dart
static ErrorFilterFn _resolveErrorFilter(Object? errorFilter) {
  if (errorFilter == null) {
    return _defaultFilter;
  }

  if (errorFilter is ErrorFilter) {
    return _convertObjectFilter(errorFilter);
  }

  if (errorFilter is ErrorFilterFn) {
    // Type check PASSED - signature is correct
    return errorFilter;
  }

  // If we get here, errorFilter is neither ErrorFilter nor correct function
  // Provide detailed error message
  throw ArgumentError.value(
    errorFilter,
    'errorFilter',
    'Invalid error filter.\n'
    'Expected:\n'
    '  - ErrorFilter object (e.g., RetryErrorFilter)\n'
    '  - OR function matching signature: '
    'ErrorReaction? Function(Object error, StackTrace stackTrace)\n'
    'Got: ${errorFilter.runtimeType}\n'
    '${_diagnoseFunction(errorFilter)}',
  );
}

static String _diagnoseFunction(Object obj) {
  // Try to provide helpful diagnostic for common mistakes
  if (obj is Function) {
    // It's a function, but wrong signature
    return 'Hint: You passed a function, but it doesn\'t match the required signature.\n'
           'Make sure your function has exactly 2 parameters:\n'
           '  - First parameter: Object (or dynamic)\n'
           '  - Second parameter: StackTrace\n'
           'And returns: ErrorReaction?';
  }
  return '';
}
```

### Pros ✅
- Runtime validation is comprehensive
- Clear error messages guide user
- Works with existing API

### Cons ❌
- NO compile-time checking for functions
- Error only appears when creating command
- IDE doesn't help

---

## Solution 2: Union Type with Static Factory

### Implementation

```dart
// Sealed union type
sealed class ErrorFilterInput {
  const ErrorFilterInput._();

  // Factory for objects
  factory ErrorFilterInput.object(ErrorFilter filter) = _ObjectFilter;

  // Factory for functions - TYPE CHECKED at compile time!
  factory ErrorFilterInput.function(
    ErrorReaction? Function(Object error, StackTrace stackTrace) fn,
  ) = _FunctionFilter;

  ErrorFilterFn toFunction();
}

class _ObjectFilter extends ErrorFilterInput {
  final ErrorFilter filter;
  const _ObjectFilter(this.filter) : super._();

  @override
  ErrorFilterFn toFunction() {
    return (e, s) {
      final reaction = filter.filter(e, s);
      return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
    };
  }
}

class _FunctionFilter extends ErrorFilterInput {
  final ErrorFilterFn fn;
  const _FunctionFilter(this.fn) : super._();

  @override
  ErrorFilterFn toFunction() => fn;
}

// Command constructor
class Command<TParam, TResult> {
  Command({
    ErrorFilterInput? errorFilter,  // ← Type-safe parameter
    // ... other params
  }) : _errorFilterFn = errorFilter?.toFunction() ?? _defaultFilter,
       super(...);
}
```

### Usage

```dart
// Object - explicit factory
errorFilter: ErrorFilterInput.object(
  const RetryErrorFilter(maxRetries: 3),
)

// Function - COMPILE-TIME type checked!
errorFilter: ErrorFilterInput.function(
  (e, s) => e is NetworkException ? ErrorReaction.global : null,
)

// Wrong signature - COMPILE ERROR!
errorFilter: ErrorFilterInput.function(
  (String e) => ErrorReaction.local,  // ← Compile error: String not assignable to Object
)
```

### Pros ✅
- ✅ Compile-time type checking for functions!
- ✅ IDE autocomplete and validation
- ✅ Clear intent (object vs function)
- ✅ Type-safe

### Cons ⚠️
- Requires wrapping at call site
- More verbose
- Not backward compatible (but could be phased in)

---

## Solution 3: Implicit Conversion with Generic

### Implementation

```dart
// Base class that accepts typed input
abstract class ErrorFilterProvider<T> {
  ErrorFilterFn toFunction();
}

// For objects
class ObjectFilterProvider extends ErrorFilterProvider<ErrorFilter> {
  final ErrorFilter filter;
  const ObjectFilterProvider(this.filter);

  @override
  ErrorFilterFn toFunction() => (e, s) {
    final reaction = filter.filter(e, s);
    return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
  };
}

// For functions
class FunctionFilterProvider extends ErrorFilterProvider<ErrorFilterFn> {
  final ErrorFilterFn fn;
  const FunctionFilterProvider(this.fn);

  @override
  ErrorFilterFn toFunction() => fn;
}

// Implicit conversion operators (if Dart supported them - IT DOESN'T)
// This is what we WISH we could do:
extension ErrorFilterConversion on ErrorFilter {
  ErrorFilterProvider<ErrorFilter> get asProvider => ObjectFilterProvider(this);
}

extension FunctionConversion on ErrorFilterFn {
  ErrorFilterProvider<ErrorFilterFn> get asProvider => FunctionFilterProvider(this);
}
```

### Usage (Theoretical)

```dart
// If Dart had implicit conversions:
errorFilter: const RetryErrorFilter(maxRetries: 3)  // Implicit conversion
errorFilter: (e, s) => ErrorReaction.local          // Implicit conversion
```

### Reality

**Dart doesn't support implicit conversions!** Must be explicit.

---

## Solution 4: Named Constructors (Best Practical Solution)

### Implementation

```dart
class Command<TParam, TResult> extends CustomValueNotifier<TResult> {
  final ErrorFilterFn _errorFilterFn;

  // Private constructor
  Command._internal({
    required ErrorFilterFn errorFilterFn,
    required TResult initialValue,
    // ... other params
  }) : _errorFilterFn = errorFilterFn,
       super(...);

  // Factory methods with specific types

  // Accept ErrorFilter object
  static Command<TParam, TResult> create<TParam, TResult>({
    required Future<TResult> Function(TParam) func,
    required TResult initialValue,
    ErrorFilter? errorFilter,  // ← Type-safe: only ErrorFilter
    // ... other params
  }) {
    return Command._internal(
      errorFilterFn: _convertObjectFilter(errorFilter ?? errorFilterDefault),
      initialValue: initialValue,
      // ... other params
    );
  }

  // Accept function - COMPILE-TIME CHECKED!
  static Command<TParam, TResult> createWithFn<TParam, TResult>({
    required Future<TResult> Function(TParam) func,
    required TResult initialValue,
    ErrorReaction? Function(Object error, StackTrace stackTrace)? errorFilterFn,  // ← Explicit signature
    // ... other params
  }) {
    return Command._internal(
      errorFilterFn: errorFilterFn ?? _defaultFilter,
      initialValue: initialValue,
      // ... other params
    );
  }
}
```

### Usage

```dart
// Object - type-safe
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilter: const RetryErrorFilter(maxRetries: 3),  // ✓ Type checked
);

// Function - type-safe!
Command.createAsyncWithFn<String, List>(
  fetchData,
  [],
  errorFilterFn: (e, s) => e is NetworkException ? ErrorReaction.global : null,  // ✓ Type checked
);

// Wrong signature - COMPILE ERROR!
Command.createAsyncWithFn<String, List>(
  fetchData,
  [],
  errorFilterFn: (String e) => ErrorReaction.local,  // ✗ Compile error
);
```

### Pros ✅
- ✅ Full compile-time type checking
- ✅ No runtime overhead
- ✅ Clear API (separate factories)
- ✅ Backward compatible (keep old factories)

### Cons ⚠️
- Doubles the number of factory methods (12 → 24)
- Some API bloat
- User must choose correct factory

---

## Solution 5: Combined Parameter with Explicit Types

### Implementation

```dart
class Command<TParam, TResult> {
  Command({
    ErrorFilter? errorFilter,
    ErrorReaction? Function(Object, StackTrace)? errorFilterFn,  // ← Explicit signature
    // ... other params
  }) : _errorFilterFn = _resolve(errorFilter, errorFilterFn),
       super(...) {
    assert(
      errorFilter == null || errorFilterFn == null,
      'Cannot provide both errorFilter and errorFilterFn',
    );
  }

  static ErrorFilterFn _resolve(
    ErrorFilter? objFilter,
    ErrorFilterFn? fnFilter,
  ) {
    if (objFilter != null) {
      return (e, s) {
        final reaction = objFilter.filter(e, s);
        return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
      };
    }
    return fnFilter ?? _defaultFilter;
  }
}
```

### Usage

```dart
// Object
errorFilter: const RetryErrorFilter(maxRetries: 3),

// Function - COMPILE-TIME CHECKED!
errorFilterFn: (e, s) => e is NetworkException ? ErrorReaction.global : null,

// Wrong signature - COMPILE ERROR!
errorFilterFn: (String e) => ErrorReaction.local,  // ✗ Parameter type mismatch
```

### Pros ✅
- ✅ Full compile-time checking
- ✅ Clear separation
- ✅ Type-safe

### Cons ⚠️
- Two parameters (API complexity)
- Must assert mutual exclusivity
- User might be confused which to use

---

## Comparison Matrix

| Solution | Compile-Time Check | Runtime Check | Verbosity | Backward Compat | API Bloat |
|----------|-------------------|---------------|-----------|----------------|-----------|
| `Object?` | ❌ | ✅ | Low | ✅ | None |
| Union Type | ✅ | ✅ | Medium | ❌ | None |
| Named Constructors | ✅ | ✅ | Medium | ✅ | High (2x methods) |
| Two Parameters | ✅ | ✅ | Low | ✅ | Low |
| Implicit Conversion | ✅ | ✅ | Low | ✅ | None (impossible) |

---

## Recommended Solution: Two Parameters (Solution 5)

### Why This is Best

1. **Full compile-time type checking** ✅
   ```dart
   errorFilterFn: (e, s) => ...  // Function signature validated by compiler
   ```

2. **Backward compatible** ✅
   ```dart
   errorFilter: const ErrorHandlerLocal()  // Existing code works
   ```

3. **Minimal API bloat** ✅
   - Only adds one parameter per factory method
   - No duplicate methods

4. **Clear separation** ✅
   - `errorFilter` for objects
   - `errorFilterFn` for functions
   - Names indicate the difference

### Full Implementation

```dart
typedef ErrorFilterFn = ErrorReaction? Function(
  Object error,
  StackTrace stackTrace,
);

class Command<TParam, TResult> extends CustomValueNotifier<TResult> {
  final ErrorFilterFn _errorFilterFn;

  Command({
    required TResult initialValue,
    required ValueListenable<bool>? restriction,
    required ExecuteInsteadHandler<TParam>? ifRestrictedExecuteInstead,
    required bool includeLastResultInCommandResults,
    required bool noReturnValue,
    required bool notifyOnlyWhenValueChanges,
    ErrorFilter? errorFilter,      // ← Object type
    ErrorFilterFn? errorFilterFn,  // ← Function type with explicit signature
    required String? name,
    required bool noParamValue,
  })  : _errorFilterFn = _resolveErrorFilter(errorFilter, errorFilterFn),
        _restriction = restriction,
        // ... rest of initialization
        super(...) {
    assert(
      errorFilter == null || errorFilterFn == null,
      'Cannot provide both errorFilter and errorFilterFn. Choose one.',
    );
  }

  static ErrorFilterFn _resolveErrorFilter(
    ErrorFilter? objectFilter,
    ErrorFilterFn? functionFilter,
  ) {
    if (objectFilter != null) {
      return (error, stackTrace) {
        final reaction = objectFilter.filter(error, stackTrace);
        return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
      };
    }

    if (functionFilter != null) {
      return functionFilter;
    }

    // Use global default
    return (error, stackTrace) {
      final reaction = errorFilterDefault.filter(error, stackTrace);
      return reaction == ErrorReaction.defaulErrorFilter ? null : reaction;
    };
  }
}
```

### Usage Examples

```dart
// 1. Object - compile-time checked
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilter: const RetryErrorFilter(maxRetries: 3),  // ✓ ErrorFilter type
);

// 2. Function - compile-time checked!
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilterFn: (error, stackTrace) =>  // ✓ Signature enforced
    error is NetworkException ? ErrorReaction.global : null,
);

// 3. Wrong function signature - COMPILE ERROR!
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilterFn: (String error) => ErrorReaction.local,
  // ✗ Compile error:
  // The argument type 'ErrorReaction? Function(String)' can't be assigned
  // to the parameter type 'ErrorReaction? Function(Object, StackTrace)?'
);

// 4. Wrong return type - COMPILE ERROR!
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilterFn: (error, stackTrace) => 'invalid',
  // ✗ Compile error:
  // The return type 'String' isn't a 'ErrorReaction?'
);

// 5. Both provided - RUNTIME ASSERTION!
Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilter: const ErrorHandlerLocal(),
  errorFilterFn: (e, s) => ErrorReaction.global,
  // ✗ Assertion error:
  // Cannot provide both errorFilter and errorFilterFn. Choose one.
);

// 6. Named function - works!
ErrorReaction? myFilter(Object error, StackTrace stackTrace) {
  return error is TimeoutException ? ErrorReaction.local : null;
}

Command.createAsync<String, List>(
  fetchData,
  [],
  errorFilterFn: myFilter,  // ✓ Type checked
);
```

### IDE Support

```dart
// When user types:
errorFilterFn:

// IDE autocompletes with signature:
errorFilterFn: (Object error, StackTrace stackTrace) {

},

// And shows parameter types on hover
```

### Error Messages

```dart
// Wrong signature
errorFilterFn: (String e, StackTrace s) => null

// Compiler error:
// The argument type 'Null Function(String, StackTrace)'
// can't be assigned to the parameter type
// 'ErrorReaction? Function(Object, StackTrace)?'.
// Try changing the type of the function literal, or
// casting the argument.
```

Clear, actionable error message!

---

## Migration Path

### Phase 1: Add `errorFilterFn` parameter (v8.1.0) - Non-breaking

```dart
// Old code continues to work
errorFilter: const ErrorHandlerLocal()

// New code can use function
errorFilterFn: (e, s) => ErrorReaction.localHandler
```

### Phase 2: Update documentation (v8.1.0)

```dart
/// Error handling configuration.
///
/// Provide EITHER [errorFilter] (object) OR [errorFilterFn] (function), not both.
///
/// Use [errorFilter] when:
/// - Filter has configuration (e.g., `RetryErrorFilter(maxRetries: 3)`)
/// - Filter is reused across multiple commands
/// - You want const optimization
///
/// Use [errorFilterFn] when:
/// - One-off custom logic specific to this command
/// - Simple type-based filtering
/// - Inline lambda is sufficient
///
/// Example:
/// ```dart
/// // Object
/// errorFilter: const RetryErrorFilter(maxRetries: 3)
///
/// // Function
/// errorFilterFn: (error, stackTrace) =>
///   error is NetworkException ? ErrorReaction.global : null
/// ```
Command.createAsync(...);
```

### Phase 3: Deprecate `defaulErrorFilter` (v8.2.0)

```dart
enum ErrorReaction {
  // ...
  @Deprecated('Return null from errorFilterFn instead')
  defaulErrorFilter,
}
```

### Phase 4: Remove deprecated enum (v9.0.0)

---

## Alternative: If API Simplicity is Critical

If you absolutely must have single parameter, use **Solution 2 (Union Type)** with convenience:

```dart
// Add shorthand extension
extension ErrorFilterInputExt on ErrorFilter {
  ErrorFilterInput get asInput => ErrorFilterInput.object(this);
}

extension ErrorFilterFnExt on ErrorFilterFn {
  ErrorFilterInput get asInput => ErrorFilterInput.function(this);
}

// Usage - only slightly more verbose
errorFilter: const RetryErrorFilter(maxRetries: 3).asInput,
errorFilter: ((e, s) => ErrorReaction.local).asInput,
```

But this loses const optimization and is still more verbose than two parameters.

---

## Final Recommendation

**Use Solution 5: Two Parameters**

```dart
Command({
  ErrorFilter? errorFilter,
  ErrorFilterFn? errorFilterFn,
  // ...
})
```

**Rationale**:
- ✅ Full compile-time type safety
- ✅ Clear, explicit API
- ✅ Backward compatible
- ✅ Minimal API bloat
- ✅ Best IDE support
- ✅ Clear error messages

**Only downside**: Must choose between two parameters, but:
- Names make the choice obvious
- Documentation guides users
- Assertion catches mistakes
- Better than runtime-only validation

---

**Conclusion**: Two parameters (`errorFilter` and `errorFilterFn`) provide the best balance of type safety, usability, and backward compatibility. The compile-time checking is worth the small API complexity.
