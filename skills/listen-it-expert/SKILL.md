---
name: listen-it-expert
description: Expert guidance on listen_it ValueListenable operators and reactive collections for Flutter/Dart. Covers listen(), transformation operators (map, select, where, debounce, async), combining operators (combineLatest, mergeWith), operator chaining, reactive collections (ListNotifier, MapNotifier, SetNotifier), transactions, and CustomValueNotifier. Use when working with ValueListenable transformations, reactive data pipelines, or listen_it collections.
metadata:
  author: flutter-it
  version: "1.0"
---

# listen_it Expert - ValueListenable Operators & Reactive Collections

**What**: Extension methods on ValueListenable/Listenable for transformations, filtering, debouncing. Plus reactive collections. Pure Dart.

## CRITICAL RULES

- Operators return NEW ValueListenable objects - MUST capture the result
- `listen()` signature differs: on `Listenable` gets `(subscription)`, on `ValueListenable` gets `(value, subscription)`
- `mergeWith()` is an INSTANCE method on ValueListenable, NOT a static method
- There is NO `throttle()` operator
- NEVER create operator chains inline in `build()` - memory leak! Use class fields or watch_it
- All operators support `{bool lazy = false}` for deferred initialization

## listen() - Subscribing to Changes

```dart
// On ValueListenable<T> - receives value AND subscription
final sub = counter.listen((int value, ListenableSubscription subscription) {
  print('New value: $value');
  if (value > 100) subscription.cancel();  // Self-cancel
});
sub.cancel();  // Or cancel externally

// On plain Listenable - receives ONLY subscription (no value)
final sub = myChangeNotifier.listen((ListenableSubscription subscription) {
  print('Something changed');
});
```

## Transformation Operators

All return new `ValueListenable` and support `{bool lazy = false}`:

```dart
final counter = ValueNotifier<int>(0);

// map - Transform values
final doubled = counter.map((x) => x * 2);

// select - Like map but only notifies when result CHANGES (equality check)
final user = ValueNotifier<User>(User('Alice', 30));
final name = user.select((u) => u.name);  // Only fires when name actually changes

// where - Filter values (only propagate when test passes)
final positives = counter.where((x) => x > 0);
final positives = counter.where((x) => x > 0, fallbackValue: 0);  // Default when filtered

// debounce - Delay notifications
final debouncedSearch = searchField.debounce(Duration(milliseconds: 300));

// async - Defer to next frame (prevents setState-during-build)
final deferred = counter.async();
```

## Combining Operators

```dart
// combineLatest - Merge 2 ValueListenables
final firstName = ValueNotifier<String>('Alice');
final lastName = ValueNotifier<String>('Smith');
final fullName = firstName.combineLatest(
  lastName,
  (first, last) => '$first $last',
);

// combineLatest3/4/5/6 - Merge up to 6 sources
final combined = source1.combineLatest3(
  source2, source3,
  (v1, v2, v3) => '$v1-$v2-$v3',
);

// mergeWith - Merge multiple sources of SAME type (instance method)
final merged = source1.mergeWith([source2, source3]);
// Emits whenever any source changes, value is from the source that changed
```

## Chaining Operators

```dart
final processed = searchInput
    .where((text) => text.isNotEmpty)
    .map((text) => text.trim().toLowerCase())
    .debounce(Duration(milliseconds: 300));

processed.listen((query, subscription) {
  performSearch(query);
});
```

## Reactive Collections

Auto-notify listeners on mutations:

```dart
// ListNotifier
final items = ListNotifier<String>(data: ['a', 'b', 'c']);
items.add('d');           // Notifies
items.remove('a');        // Notifies
items[0] = 'z';          // Notifies
items.value;              // UnmodifiableListView (read-only access)

// MapNotifier
final settings = MapNotifier<String, dynamic>(data: {'theme': 'dark'});
settings['theme'] = 'light';   // Notifies
settings.remove('theme');      // Notifies

// SetNotifier
final tags = SetNotifier<String>(data: {'flutter', 'dart'});
tags.add('mobile');       // Notifies
tags.remove('dart');      // Notifies
```

**Notification modes**:
```dart
// CustomNotifierMode.always - notify on every operation (default for collections)
// CustomNotifierMode.normal - notify only when value changes (== check)
// CustomNotifierMode.manual - no auto-notification, call notifyListeners() yourself

final items = ListNotifier<String>(
  notificationMode: CustomNotifierMode.always,
);
```

**Transactions** (batch operations, single notification):
```dart
items.startTransAction();
items.add('a');
items.add('b');
items.add('c');
items.endTransAction();  // Single notification for all 3 adds
```

## Anti-Patterns

```dart
// ❌ Not capturing operator result
counter.map((x) => x * 2);  // Lost! Nobody holds a reference
// ✅ Capture it
final doubled = counter.map((x) => x * 2);

// ❌ Creating chains inline in build() - MEMORY LEAK
Widget build(context) {
  final doubled = counter.map((x) => x * 2);  // New chain every build!
  ...
}
// ✅ Use class field or watch_it (caches selector automatically)
late final doubled = counter.map((x) => x * 2);  // Created once

// ❌ Using addListener instead of listen
notifier.addListener(() { print(notifier.value); });
// ✅ Use listen() from listen_it
notifier.listen((value, sub) { print(value); });

// ❌ ValueNotifier.merge (doesn't exist!)
ValueNotifier.merge([a, b], combiner);  // NOT A REAL METHOD
// ✅ Use mergeWith (instance method) or combineLatest
final merged = a.mergeWith([b]);
final combined = a.combineLatest(b, (va, vb) => va + vb);
```

## Production Patterns

**Debounced auto-save**:
```dart
_dataSubscription = _data
    .debounce(const Duration(seconds: 1))
    .listen((_, __) {
  _data.saveDraft();
});
```

**Filtered draft list**:
```dart
final ListNotifier<CommonComposerData> _drafts = ListNotifier(
  notificationMode: CustomNotifierMode.manual,
);

late ValueListenable<List<CommonComposerData>> savedDrafts =
    (_drafts as ValueListenable<List<CommonComposerData>>)
        .map((list) => list.where((e) => e.intentionallySaved).toList());
```

**Error listening on commands**:
```dart
updatePostCommand.errors.listen((error, _) {
  final composerData = error!.paramData;
  composerData?.saveDraft(withIntention: true);
});
```

## CustomValueNotifier

For advanced notification control:

```dart
final notifier = CustomValueNotifier<int>(
  0,
  mode: CustomNotifierMode.normal,      // Only notify on actual changes
  asyncNotification: false,             // true = defer to next frame
);
```
