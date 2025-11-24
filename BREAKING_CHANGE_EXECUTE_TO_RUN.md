# Breaking Change Proposal: Rename "execute" to "run" Terminology

**Status**: ✅ Implemented
**Target Version**: v9.0.0 (deprecation), v10.0.0 (removal)
**Date Proposed**: November 12, 2025
**Date Implemented**: November 14, 2025
**Author**: command_it maintainers

---

## Executive Summary

We propose renaming Command's primary API from "execute" terminology to "run" terminology across methods, properties, and parameters. This change addresses the practical reality that the callable class syntax (`command()`) triggers linter warnings, making `.execute()` the de facto primary API surface.

**Key changes:**
- `execute()` → `run()`
- `executeWithFuture()` → `runAsync()`
- `isExecuting` → `isRunning`
- `isExecutingSync` → `isRunningSync`
- `canExecute` → `canRun`
- `thrownExceptions` → `errors`
- `ifRestrictedExecuteInstead:` → `ifRestrictedRunInstead:` (12 factory parameters)
- `whileExecuting:` → `whileRunning:` (CommandBuilder parameter)

**Timeline:** 2-phase deprecation (v9 adds new API with deprecation warnings, v10 removes old API)

---

## Motivation

### The Implicit Call Tear-Off Problem

Command implements a callable class via the `call()` method, originally designed to allow this syntax:

```dart
FloatingActionButton(
  onPressed: command,  // Callable class direct assignment
)
```

However, this triggers the `implicit_call_tearoffs` linter warning in strict configurations (DartPad, recommended linter rules), because Dart implicitly tears off the `.call()` method, which is considered unclear.

**The practical reality:** Users must use `.execute()` method tear-off instead:

```dart
FloatingActionButton(
  onPressed: command.execute,  // Explicit method tear-off ✅
)
```

See `test/callable_assignment_test.dart` and https://gist.github.com/escamoteur/e92fc4b2a0aaf4d180f46110543c6706

### Why "execute" is No Longer Appropriate

With `.execute()` now being the primary API surface (not the callable syntax), the name "execute" carries problems:

1. **Overly formal** - "Execute" has military/authoritative connotations that feel heavy
2. **Not Flutter-idiomatic** - Flutter uses "run" terminology ("run the app", "running state")
3. **Inconsistent with ecosystem** - Riverpod uses `.run()`, async tasks "run", not "execute"
4. **Longer and harder to type** - `isExecuting` vs `isRunning`, `canExecute` vs `canRun`

**The opportunity:** Since we must make a breaking change to fix other issues in v9/v10 anyway, this is the ideal time to improve the API surface.

---

## Proposed Changes

### API Surface Changes

#### Methods

| Current | Proposed | Usage Count | Notes |
|---------|----------|-------------|-------|
| `execute([TParam? param])` | `run([TParam? param])` | 61 call sites | Primary execution method |
| `executeWithFuture([TParam? param])` | `runAsync([TParam? param])` | 5 call sites | Returns awaitable Future |

#### Properties

| Current | Proposed | Usage Count | Notes |
|---------|----------|-------------|-------|
| `ValueListenable<bool> isExecuting` | `ValueListenable<bool> isRunning` | 74 occurrences | Async execution state (async notifications) |
| `ValueListenable<bool> isExecutingSync` | `ValueListenable<bool> isRunningSync` | ~20 occurrences | Execution state (sync notifications) |
| `ValueListenable<bool> canExecute` | `ValueListenable<bool> canRun` | 47 occurrences | Computed from restriction + isRunning |
| `ValueListenable<CommandError?> thrownExceptions` | `ValueListenable<CommandError?> errors` | ~15 occurrences | Error notifications |

#### Parameters

| Current | Proposed | Usage Count | Notes |
|---------|----------|-------------|-------|
| `ifRestrictedExecuteInstead` | `ifRestrictedRunInstead` | 54 occurrences | Callback when command is restricted (12 factory methods) |
| `whileExecuting` | `whileRunning` | ~10 occurrences | CommandBuilder parameter for loading state |

#### CommandResult Structure

```dart
// Before
class CommandResult<TParam, TResult> {
  final bool isExecuting;

  const CommandResult(
    this.paramData,
    this.data,
    this.error,
    this.isExecuting,
    // ...
  );
}

// After
class CommandResult<TParam, TResult> {
  final bool isRunning;

  const CommandResult(
    this.paramData,
    this.data,
    this.error,
    this.isRunning,
    // ...
  );
}
```

#### Internal Implementation (Not Breaking)

These are internal and don't affect public API:
- `_execute()` → `_run()`
- `_isExecuting` → `_isRunning`
- Internal field names updated for consistency

---

## MockCommand API Update (v9.3.0)

**Status**: ✅ Implemented in v9.3.0 (January 2025)

MockCommand was updated to match the Command API terminology migration. All "execute" terminology in MockCommand has been renamed to "run" with the same deprecation pattern.

### MockCommand Methods

| Old API (Deprecated) | New API | Purpose |
|---------------------|---------|---------|
| `startExecution([TParam? param])` | `startRun([TParam? param])` | Start simulated command execution |
| `endExecutionWithData(TResult data)` | `endRunWithData(TResult data)` | End execution with success data |
| `endExecutionWithError(String message)` | `endRunWithError(String message)` | End execution with error |
| `endExecutionNoData()` | `endRunNoData()` | End execution without data |
| `queueResultsForNextExecuteCall(values)` | `queueResultsForNextRunCall(values)` | Queue results for next run |

### MockCommand Properties

| Old API (Deprecated) | New API | Purpose |
|---------------------|---------|---------|
| `executionCount` | `runCount` | Number of times command was called |
| `lastPassedValueToExecute` | `lastPassedValueToRun` | Last parameter passed to command |
| `returnValuesForNextExecute` | `returnValuesForNextRun` | Queued results for next call |

### Migration Example

**Before (deprecated):**
```dart
final mockCommand = MockCommand<String, String>(initialValue: '');

mockCommand.startExecution('test');
mockCommand.endExecutionWithData('result');
expect(mockCommand.executionCount, 1);
expect(mockCommand.lastPassedValueToExecute, 'test');
```

**After (v9.3.0+):**
```dart
final mockCommand = MockCommand<String, String>(initialValue: '');

mockCommand.startRun('test');
mockCommand.endRunWithData('result');
expect(mockCommand.runCount, 1);
expect(mockCommand.lastPassedValueToRun, 'test');
```

### Deprecation Notes

- All old "execute" terminology methods and properties still work with deprecation warnings
- Will be removed in v10.0.0 (same timeline as Command API)
- Automated search/replace patterns from the main migration guide work for MockCommand too
- Both old and new APIs are fully tested for backward compatibility

---

## Impact Analysis

### Affected Code Locations

**Core Library (`lib/`):** ~140 occurrences (v9.0.0) + 30 occurrences (v9.3.0 MockCommand)
- `lib/command_it.dart` - Command base class (~30 occurrences)
- `lib/async_command.dart` - Async implementation (~25 occurrences)
- `lib/sync_command.dart` - Sync implementation (~20 occurrences)
- `lib/undoable_command.dart` - Undoable implementation (~35 occurrences)
- `lib/mock_command.dart` - Mock implementation (~15 occurrences in v9.0.0, +30 in v9.3.0 for MockCommand-specific API)
- `lib/command_builder.dart` - Widget builder (~10 occurrences)
- `lib/code_for_docs.dart` - Documentation examples (~5 occurrences)

**Tests (`test/`):** ~56 occurrences (v9.0.0) + 8 new tests (v9.3.0 MockCommand)
- `test/flutter_command_test.dart` - Main test suite (~33 occurrences in v9.0.0, +8 new tests in v9.3.0 for MockCommand API)
- `test/error_test.dart` - Error handling tests (~21 occurrences)
- `test/callable_assignment_test.dart` - Callable class tests (~2 occurrences)

**Example App (`example/`):** ~5 occurrences
- `example/lib/weather_manager.dart` - 2 call sites
- `example/lib/homepage.dart` - 3 usages (1 call + 2 properties)

**Documentation:** ~120 occurrences
- `README.md` - 7 mentions
- `CLAUDE.md` - 10 mentions
- `docs/` - 6 files, 13 mentions
- Specification docs (9 files) - 100+ mentions

**Total Estimated Updates:** 300-400 locations

### Breaking Change Impact

**Severity: HIGH**

This is a **complete API surface rename** affecting:
- Every method call to execute commands
- Every property access for state tracking
- Every parameter using the callback
- All CommandResult instantiations
- All documentation and examples

**User Impact:**
- 100% of command_it users will need to update their code
- Automated search/replace can handle most cases
- Some manual review needed for complex scenarios

---

## Migration Guide

### For Package Users

#### Automated Migration (Recommended)

**Step 1: Global search and replace**

Use your IDE's "Replace in Path" feature with these patterns:

```
# Methods
.execute(        → .run(
.executeWithFuture(  → .runAsync(

# Properties
.isExecuting     → .isRunning
.isExecutingSync → .isRunningSync
.canExecute      → .canRun
.thrownExceptions → .errors

# Parameters
ifRestrictedExecuteInstead:  → ifRestrictedRunInstead:
whileExecuting:  → whileRunning:

# CommandResult constructor
isExecuting:     → isRunning:

# Accessing CommandResult field
.isExecuting     → .isRunning
```

**Step 2: MockCommand migration (if using MockCommand)**

MockCommand users should also apply these replacements:

```
# MockCommand methods
.startExecution(      → .startRun(
.endExecutionWithData(  → .endRunWithData(
.endExecutionWithError( → .endRunWithError(
.endExecutionNoData(  → .endRunNoData(
.queueResultsForNextExecuteCall( → .queueResultsForNextRunCall(

# MockCommand properties
.executionCount       → .runCount
.lastPassedValueToExecute → .lastPassedValueToRun
.returnValuesForNextExecute → .returnValuesForNextRun
```

**Step 3: Manual review**

Check these edge cases:
- String literals containing "execute" (e.g., log messages)
- Comments and documentation
- Variable names like `shouldExecute` → consider renaming

**Step 4: Test and verify**

```bash
flutter analyze
flutter test
```

#### Manual Migration Examples

**Before:**
```dart
final command = Command.createAsync(fetchData, []);

// Method calls
command.execute(param);
await command.executeWithFuture(param);

// Property access
if (command.isExecuting.value) { /* ... */ }
if (command.isExecutingSync.value) { /* ... */ }
if (command.canExecute.value) { /* ... */ }

// Error handling
command.thrownExceptions.listen((error, _) {
  print('Error: $error');
});

// Widget usage
ValueListenableBuilder(
  valueListenable: command.isExecuting,
  builder: (context, isExecuting, _) {
    return isExecuting
      ? CircularProgressIndicator()
      : ElevatedButton(onPressed: command.execute, child: Text('Go'));
  },
)

// CommandBuilder usage
CommandBuilder(
  command: command,
  whileExecuting: (context, lastValue, _) => CircularProgressIndicator(),
  onData: (context, data, _) => DataWidget(data),
);

// Parameter usage
Command.createAsync(
  fetchData,
  [],
  ifRestrictedExecuteInstead: (param) => showLoginDialog(),
);

// CommandResult usage
final result = CommandResult(null, data, null, false);
if (result.isExecuting) { /* ... */ }
```

**After:**
```dart
final command = Command.createAsync(fetchData, []);

// Method calls
command.run(param);
await command.runAsync(param);

// Property access
if (command.isRunning.value) { /* ... */ }
if (command.isRunningSync.value) { /* ... */ }
if (command.canRun.value) { /* ... */ }

// Error handling
command.errors.listen((error, _) {
  print('Error: $error');
});

// Widget usage
ValueListenableBuilder(
  valueListenable: command.isRunning,
  builder: (context, isRunning, _) {
    return isRunning
      ? CircularProgressIndicator()
      : ElevatedButton(onPressed: command.run, child: Text('Go'));
  },
)

// CommandBuilder usage
CommandBuilder(
  command: command,
  whileRunning: (context, lastValue, _) => CircularProgressIndicator(),
  onData: (context, data, _) => DataWidget(data),
);

// Parameter usage
Command.createAsync(
  fetchData,
  [],
  ifRestrictedRunInstead: (param) => showLoginDialog(),
);

// CommandResult usage
final result = CommandResult(null, data, null, false);
if (result.isRunning) { /* ... */ }
```

---

## Deprecation Strategy

We propose a **2-phase deprecation** over two major versions to minimize ecosystem disruption.

### Phase 1: v9.0.0 - Add New API, Deprecate Old

**Timeline:** Release v9.0.0 in November 2025

**Changes:**
1. Add new `run()` method alongside deprecated `execute()`
2. Add new `runWithFuture()` alongside deprecated `executeWithFuture()`
3. Add new `isRunning` property alongside deprecated `isExecuting`
4. Add new `canRun` property alongside deprecated `canExecute`
5. Add new `ifRestrictedRunInstead` parameter alongside deprecated `ifRestrictedExecuteInstead`
6. Update all internal examples/docs to use new terminology
7. Add migration guide to CHANGELOG

**Implementation approach:**

```dart
class Command<TParam, TResult> {
  // New API
  void run([TParam? param]) {
    // Implementation (moved from execute)
  }

  Future<TResult> runAsync([TParam? param]) {
    // Implementation (moved from executeWithFuture)
  }

  ValueListenable<bool> get isRunning => _isRunningAsync;
  ValueListenable<bool> get isRunningSync => _isRunning;
  ValueListenable<bool> get canRun => _canRun;
  ValueListenable<CommandError?> get errors => _errors;

  // Deprecated API (forwards to new API)
  @Deprecated('Use run() instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  void execute([TParam? param]) => run(param);

  @Deprecated('Use runAsync() instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  Future<TResult> executeWithFuture([TParam? param]) => runAsync(param);

  @Deprecated('Use isRunning instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  ValueListenable<bool> get isExecuting => isRunning;

  @Deprecated('Use isRunningSync instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  ValueListenable<bool> get isExecutingSync => isRunningSync;

  @Deprecated('Use canRun instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  ValueListenable<bool> get canExecute => canRun;

  @Deprecated('Use errors instead. This will be removed in v10.0.0. '
              'See BREAKING_CHANGE_EXECUTE_TO_RUN.md for migration guide.')
  ValueListenable<CommandError?> get thrownExceptions => errors;
}
```

**For CommandResult:**

```dart
class CommandResult<TParam, TResult> {
  final bool isRunning;

  const CommandResult(
    this.paramData,
    this.data,
    this.error,
    this.isRunning, {
    // ...
  });

  @Deprecated('Use isRunning instead. This will be removed in v10.0.0.')
  bool get isExecuting => isRunning;
}
```

**Analyzer output for users:**

```
warning: 'execute' is deprecated and shouldn't be used. Use run() instead.
This will be removed in v10.0.0. See BREAKING_CHANGE_EXECUTE_TO_RUN.md
for migration guide. (deprecated_member_use)
```

### Phase 2: v10.0.0 - Remove Deprecated API

**Timeline:** Release v10.0.0 in May-June 2026 (6 months after v9.0.0)

**Changes:**
1. Remove all deprecated `execute*` methods
2. Remove all deprecated `isExecuting`/`canExecute` properties
3. Remove all deprecated parameter names
4. Remove deprecation shims from CommandResult
5. Update CHANGELOG with final breaking change notice

**Grace period:** 6 months of deprecation warnings before removal

---

## Timeline

| Date | Version | Milestone |
|------|---------|-----------|
| November 2025 | v8.0.3 | Document implicit call tear-off issue |
| November 2025 | v8.1.0 | Hybrid error filtering + other features |
| November 2025 | **v9.0.0** | **Add "run" API, deprecate "execute" API** |
| November 2025 | v9.2.0 | CommandBuilder auto-run + Command.toWidget deprecation |
| January 2025 | **v9.3.0** | **MockCommand "run" API migration** |
| Nov 2025 - May 2026 | v9.x | Bug fixes, ecosystem migration period |
| May-June 2026 | **v10.0.0** | **Remove deprecated "execute" API** |

**Minimum deprecation period:** 6 months

---

## Resolved Questions

### 1. Awaitable Method Name

**Which name should we use for the awaitable version?**

| Option | Pros | Cons | Vote |
|--------|------|------|------|
| `runWithFuture()` | Direct parallel to current API, clear that it returns Future | Slightly verbose | |
| `runAwaited()` | Shorter, emphasizes await-ability | Less clear it returns Future | |
| `runAsync()` | Short and common | Ambiguous (async commands are already async) | ✅ **CHOSEN** |
| `runFuture()` | Very short | Grammatically awkward ("run future"?) | |

**Decision:** `runAsync()`
- Shorter and more natural than `runWithFuture()`
- Common pattern in async APIs
- While commands themselves are async, the method name emphasizes the awaitable Future return
- User preference confirmed this choice

### 2. Should We Also Rename Internal Methods?

**Question:** Should `_execute()` internal method become `_run()`?

**Decision:** ✅ YES - Implemented
- Internal consistency matters
- Reduces confusion during debugging
- No breaking change (private API)
- All internal methods and fields renamed: `_execute()` → `_run()`, `_isExecuting` → `_isRunning`, etc.

### 3. Deprecation Period Length

**Question:** How long should v9.x exist before v10.0.0 removes the old API?

**Options:**
- **6 months** - Faster iteration
- **12 months** - Standard deprecation period
- **18 months** - Extra time for large codebases
- **24 months** - Maximum grace period

**Decision:** **6 months**
- command_it is a relatively young package with smaller user base
- Breaking change is straightforward (automated search/replace)
- Allows faster iteration and cleaner codebase
- Users will have clear migration guide and deprecation warnings

### 4. Should CommandResult Use Named Parameters?

**Question:** Should we use this opportunity to also make CommandResult use named parameters?

**Current:**
```dart
const CommandResult(
  this.paramData,
  this.data,
  this.error,
  this.isRunning,  // Positional
);
```

**Alternative:**
```dart
const CommandResult({
  required this.paramData,
  required this.data,
  required this.error,
  required this.isRunning,  // Named
});
```

**Recommendation:** **No, separate concern**
- This proposal is focused on terminology only
- Mixing multiple breaking changes complicates migration
- Consider for v11.0.0 if desired

---

## Alternatives Considered

### Alternative 1: Keep "execute" Terminology

**Pros:**
- No breaking change
- Users already familiar with current API
- "Execute" is standard in Command pattern literature (WPF, .NET)

**Cons:**
- Doesn't address that `.execute()` is now primary API (due to linter issue)
- "Execute" feels overly formal for Flutter
- Missed opportunity to improve DX

**Verdict:** Rejected - The linter issue makes this the right time to improve terminology

### Alternative 2: Use "invoke" Instead

**Pros:**
- Common in callback/function contexts
- Clear action meaning

**Cons:**
- Longer than "run" (6 vs 3 characters)
- Less natural for async operations ("invoking" sounds synchronous)
- Not as idiomatic in Flutter ecosystem

**Verdict:** Rejected - "run" is shorter and more natural

### Alternative 3: Use "call" Explicitly

**Pros:**
- Makes the callable class pattern explicit

**Cons:**
- Redundant with the `call()` method
- Doesn't solve anything
- `command.call.call()` would be confusing

**Verdict:** Rejected - Doesn't improve clarity

### Alternative 4: Add "run" as Alias, Keep Both

**Pros:**
- No breaking change
- Users can choose preferred style

**Cons:**
- API surface bloat (double the methods/properties)
- Confusing to have two ways to do same thing
- Documentation would be inconsistent

**Verdict:** Rejected - Clean break is better than maintaining dual API forever

---

## Implementation Checklist

### Phase 1: v9.0.0 Preparation

- [ ] Create this proposal document
- [ ] Get community feedback (GitHub discussion)
- [ ] Decide on awaitable method name (runWithFuture vs alternatives)
- [ ] Update IMPLEMENTATION_PLAN.md with v9.0.0 section

### Phase 1: v9.0.0 Implementation

**Core Library:**
- [ ] Add `run()` method to Command base class
- [ ] Add `runWithFuture()` method
- [ ] Add `isRunning` property
- [ ] Add `canRun` property
- [ ] Add `ifRestrictedRunInstead` parameter
- [ ] Add `@Deprecated` annotations to all old APIs
- [ ] Update CommandResult with `isRunning` field + deprecated getter
- [ ] Rename internal `_execute()` to `_run()`
- [ ] Rename internal `_isExecuting` to `_isRunning`

**Tests:**
- [ ] Update all tests to use new API
- [ ] Add tests verifying deprecated APIs still work
- [ ] Add tests for deprecation warnings

**Documentation:**
- [ ] Update README.md to use "run" terminology
- [ ] Update CLAUDE.md
- [ ] Update all docs/ markdown files
- [ ] Update example app
- [ ] Add migration guide to CHANGELOG
- [ ] Update API_PROPOSAL docs
- [ ] Update all specification docs

**Quality:**
- [ ] Run full test suite
- [ ] Check analyzer output for deprecation warnings
- [ ] Verify backward compatibility (old code still works)
- [ ] Update pub.dev package description

### Phase 1.5: v9.3.0 MockCommand Implementation

**MockCommand Library:**
- [x] Add `startRun()` method alongside deprecated `startExecution()`
- [x] Add `endRunWithData()` method alongside deprecated `endExecutionWithData()`
- [x] Add `endRunWithError()` method alongside deprecated `endExecutionWithError()`
- [x] Add `endRunNoData()` method alongside deprecated `endExecutionNoData()`
- [x] Add `queueResultsForNextRunCall()` method alongside deprecated `queueResultsForNextExecuteCall()`
- [x] Add `runCount` property alongside deprecated `executionCount`
- [x] Add `lastPassedValueToRun` property alongside deprecated `lastPassedValueToExecute`
- [x] Add `returnValuesForNextRun` property alongside deprecated `returnValuesForNextExecute`
- [x] Add `@Deprecated` annotations to all old MockCommand APIs
- [x] Update internal references to use new field names

**Tests:**
- [x] Add 8 new tests for MockCommand "run" API
- [x] Verify all existing MockCommand tests still pass with old API
- [x] Test backward compatibility (both APIs work)

**Documentation:**
- [x] Update BREAKING_CHANGE_EXECUTE_TO_RUN.md with MockCommand section
- [x] Update CHANGELOG.md with v9.3.0 entry
- [x] Update pubspec.yaml to v9.3.0
- [ ] Update docs/testing.md with new MockCommand API examples
- [ ] Update code samples to use new MockCommand API

**Quality:**
- [x] Run MockCommand tests
- [x] Verify compilation (no errors)
- [x] Format code with dart format

### Phase 2: v10.0.0 Implementation

**Command API Removal:**
- [ ] Remove all `@Deprecated` execute* methods
- [ ] Remove all `@Deprecated` isExecuting/canExecute properties
- [ ] Remove deprecated CommandResult.isExecuting getter
- [ ] Remove deprecated parameter names

**MockCommand API Removal:**
- [ ] Remove all `@Deprecated` MockCommand execute* methods (startExecution, endExecutionWithData, etc.)
- [ ] Remove all `@Deprecated` MockCommand properties (executionCount, lastPassedValueToExecute, returnValuesForNextExecute)

**Final Steps:**
- [ ] Update CHANGELOG with final breaking change notice
- [ ] Verify no references to old API remain (including MockCommand)
- [ ] Run full test suite
- [ ] Update semantic version to 10.0.0

---

## Risk Assessment

### High Risk

**Ecosystem disruption**
- 100% of command_it users affected
- Third-party packages using command_it will break
- **Mitigation:** 6-month deprecation period with clear migration guide

**User confusion during transition**
- Two ways to do same thing during v9.x
- **Mitigation:** Clear documentation, consistent examples

### Medium Risk

**Incomplete migration**
- Users forget to migrate before v10.0.0
- **Mitigation:** Loud deprecation warnings, migration guide

**Documentation debt**
- Need to update all docs, examples, tutorials
- **Mitigation:** Checklist above, thorough review

### Low Risk

**Naming bikeshed**
- Community might prefer different name
- **Mitigation:** Get feedback early via GitHub discussion

**Performance impact**
- Deprecated methods are forwards, slight overhead
- **Mitigation:** Negligible (single method call), removed in v10

---

## Success Criteria

### v9.0.0 Release

- [ ] All new "run" APIs functional and tested
- [ ] All deprecated "execute" APIs work with warnings
- [ ] Zero test failures
- [ ] Migration guide published
- [ ] Community feedback addressed

### v9.x Adoption Period

- [ ] 80%+ of example code uses new API
- [ ] Major users have migrated (if any)
- [ ] No critical bugs in new API

### v10.0.0 Release

- [ ] Old API completely removed
- [ ] Zero references to "execute" in public API
- [ ] All docs updated
- [ ] Clean analyzer output

---

## Community Feedback

**How to provide feedback:**

1. **GitHub Discussion** - [Create discussion thread]
2. **Discord** - https://discord.gg/ZHYHYCM38h
3. **GitHub Issues** - Label as "breaking-change-proposal"

**Feedback requested on:**

1. Is "run" the right terminology? Any better alternatives?
2. Which awaitable method name: `runWithFuture()` vs `runAwaited()` vs other?
3. Is 6 months enough deprecation time?
4. Any migration concerns we haven't considered?

---

## References

- **Implicit call tear-off gist:** https://gist.github.com/escamoteur/e92fc4b2a0aaf4d180f46110543c6706
- **Callable assignment test:** `test/callable_assignment_test.dart`
- **Dart linter rule:** `implicit_call_tearoffs`
- **Similar packages:**
  - Riverpod: Uses `.run()` for providers
  - Bloc: Uses `.add()` for events (different pattern)
  - Flutter: "Run the app", "running state"

---

## Appendix: Complete API Mapping

### Methods

| Old API | New API | Signature |
|---------|---------|-----------|
| `execute([TParam? param])` | `run([TParam? param])` | `void` |
| `executeWithFuture([TParam? param])` | `runAsync([TParam? param])` | `Future<TResult>` |

### Properties

| Old API | New API | Type |
|---------|---------|------|
| `isExecuting` | `isRunning` | `ValueListenable<bool>` |
| `isExecutingSync` | `isRunningSync` | `ValueListenable<bool>` |
| `canExecute` | `canRun` | `ValueListenable<bool>` |
| `thrownExceptions` | `errors` | `ValueListenable<CommandError?>` |

### Parameters

| Old API | New API | Type | Context |
|---------|---------|------|---------|
| `ifRestrictedExecuteInstead` | `ifRestrictedRunInstead` | `void Function(TParam? param)?` | 12 Command factory methods |
| `whileExecuting` | `whileRunning` | `Widget Function(BuildContext, TResult?, TParam?)?` | CommandBuilder + toWidget extension |

### CommandResult Fields

| Old API | New API | Type |
|---------|---------|------|
| `isExecuting` | `isRunning` | `bool` |

### Internal (Not Breaking)

| Old API | New API | Visibility |
|---------|---------|------------|
| `_execute([TParam? param])` | `_run([TParam? param])` | Private |
| `_isExecuting` | `_isRunning` | Private |
| `_isExecutingAsync` | `_isRunningAsync` | Private |
| `_ifRestrictedExecuteInstead` | `_ifRestrictedRunInstead` | Private |

---

**End of Proposal**
