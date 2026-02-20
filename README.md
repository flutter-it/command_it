<img align="left" src="https://github.com/flutter-it/command_it/blob/main/command_it.png?raw=true" alt="command_it logo" width="150" style="margin-left: -10px;"/>

<div align="right">
  <a href="https://www.buymeacoffee.com/escamoteur"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="28" width="120"/></a>
  <br/>
  <a href="https://github.com/sponsors/escamoteur"><img src="https://img.shields.io/badge/Sponsor-❤-ff69b4?style=for-the-badge" alt="Sponsor" height="28" width="120"/></a>
</div>

<br clear="both"/>

# command_it <a href="https://codecov.io/gh/flutter-it/command_it"><img align="right" src="https://codecov.io/gh/flutter-it/command_it/branch/main/graph/badge.svg?style=for-the-badge" alt="codecov" width="200"/></a>

> 📚 **[Complete documentation available at flutter-it.dev](https://flutter-it.dev/documentation/command_it/getting_started)**
> Check out the comprehensive docs with detailed guides, examples, and best practices!

---

## 🔄 Migration Notice (v9.0.0)

> **Important:** Version 9.0.0 introduces new, clearer API naming. The old API is deprecated and will be removed in v10.0.0.
>
> **Quick Migration:** `execute()` → `run()` | `isExecuting` → `isRunning` | `canExecute` → `canRun`
>
> Run `dart fix --apply` to automatically update most usages.
>
> [Complete migration guide →](BREAKING_CHANGE_EXECUTE_TO_RUN.md)

---

**Command pattern for Flutter - wrap functions as observable objects with automatic state management**

Commands replace async methods with reactive alternatives. Wrap your functions, get automatic loading states, error handling, and UI integration. No manual state tracking, no try/catch everywhere.

Call them like functions. React to their state. Simple as that.

> **Part of [flutter_it](https://flutter-it.dev)** — A construction set of independent packages. command_it works standalone or combines with watch_it for reactive UI updates.

## Why Commands?

- **🎯 Declarative** — Wrap functions, get observable execution state automatically
- **⚡ Automatic State** — isRunning, value, errors tracked without manual code
- **🛡️ Smart Error Handling** — Route errors globally/locally with filters
- **🔒 Built-in Protection** — Prevents parallel execution automatically
- **🎛️ Restrictions** — Disable commands conditionally (auth, network, etc.)
- **🧪 Testable** — Easier to test than traditional async methods

[Learn more about the benefits →](https://flutter-it.dev/documentation/command_it/getting_started)

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  command_it: ^9.0.2
  listen_it: ^5.3.3  # Required - commands build on ValueListenable
```

### Basic Example

```dart
import 'package:command_it/command_it.dart';

// 1. Create a command that wraps your async function
class CounterManager {
  int _counter = 0;

  late final incrementCommand = Command.createAsyncNoParam<String>(
    () async {
      await Future.delayed(Duration(milliseconds: 500));
      _counter++;
      return _counter.toString();
    },
    initialValue: '0',
  );
}

// 2. Use it in your UI - command is a ValueListenable
class CounterWidget extends StatelessWidget {
  final manager = CounterManager();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Shows loading indicator automatically while command runs
        ValueListenableBuilder<bool>(
          valueListenable: manager.incrementCommand.isRunning,
          builder: (context, isRunning, _) {
            if (isRunning) return CircularProgressIndicator();

            return ValueListenableBuilder<String>(
              valueListenable: manager.incrementCommand,
              builder: (context, value, _) => Text('Count: $value'),
            );
          },
        ),
        ElevatedButton(
          onPressed: manager.incrementCommand.run,
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

**That's it!** The command automatically:
- Prevents parallel execution
- Tracks isRunning state
- Publishes results
- Handles errors

[Full tutorial](https://flutter-it.dev/documentation/command_it/getting_started)

### Using CommandBuilder

Simplify your UI code with the built-in builder widget:

```dart
CommandBuilder<void, String>(
  command: manager.incrementCommand,
  whileRunning: (context, _, __) => CircularProgressIndicator(),
  onData: (context, value, _) => Text('Count: $value'),
  onError: (context, error, _, __) => Text('Error: $error'),
)
```

## Key Features

### Command Types

Create commands for any function signature:

- **[createAsync](https://flutter-it.dev/documentation/command_it/command_types#createasync)** — Async with parameter and result
- **[createAsyncNoParam](https://flutter-it.dev/documentation/command_it/command_types#createasyncnoparam)** — Async without parameter
- **[createAsyncNoResult](https://flutter-it.dev/documentation/command_it/command_types#createasyncnoresult)** — Async that returns nothing
- **[createSync](https://flutter-it.dev/documentation/command_it/command_types#createsync)** — Sync with parameter and result
- Plus NoParam and NoResult variants for sync commands

### Command Properties

Observe different aspects of execution:

- **[value](https://flutter-it.dev/documentation/command_it/command_properties#value)** — Last successful result
- **[isRunning](https://flutter-it.dev/documentation/command_it/command_properties#isrunning)** — Async execution state
- **[isRunningSync](https://flutter-it.dev/documentation/command_it/command_properties#isrunningsync)** — Synchronous version for restrictions
- **[canRun](https://flutter-it.dev/documentation/command_it/command_properties#canrun)** — Combined restriction and running state
- **[errors](https://flutter-it.dev/documentation/command_it/command_properties#errors)** — Stream of errors
- **[results](https://flutter-it.dev/documentation/command_it/command_results)** — CommandResult with all data at once

### Error Handling

Declarative error routing with filters:

- **[Basic Error Handling](https://flutter-it.dev/documentation/command_it/error_handling)** — Listen to errors locally
- **[Global Handler](https://flutter-it.dev/documentation/command_it/error_handling#global-handler)** — App-wide error handling
- **[Global Errors Stream](https://flutter-it.dev/documentation/command_it/global_configuration#globalerrors)** — Reactive monitoring of all globally-routed errors
- **[Error Filters](https://flutter-it.dev/documentation/command_it/error_filters)** — Route errors by type or predicate
- **[Built-in Filters](https://flutter-it.dev/documentation/command_it/error_filters#built-in-filters)** — GlobalIfNoLocalErrorFilter, PredicatesErrorFilter, etc.

### Advanced Features

- **[Command Restrictions](https://flutter-it.dev/documentation/command_it/restrictions)** — Disable commands conditionally
- **[CommandBuilder](https://flutter-it.dev/documentation/command_it/command_builders)** — Widget for simpler UI code
- **[Undoable Commands](https://flutter-it.dev/documentation/command_it/undoable_commands)** — Built-in undo/redo support
- **[Command Piping](#piping-commands)** — Chain commands together automatically
- **[Testing](https://flutter-it.dev/documentation/command_it/testing)** — Patterns for testing commands

### Piping Commands

Chain commands together with the `pipeToCommand()` extension. When the source completes successfully, it automatically triggers the target command:

```dart
// Trigger refresh after save completes
saveCommand.pipeToCommand(refreshCommand);

// Transform result before passing to target
userIdCommand.pipeToCommand(fetchUserCommand, transform: (id) => UserRequest(id));

// Pipe from any ValueListenable - track execution state changes
longRunningCommand.isRunning.pipeToCommand(spinnerStateCommand);
```

The `pipeToCommand()` extension works on any `ValueListenable`, including commands, `isRunning`, `results`, or plain `ValueNotifier`. Returns a `ListenableSubscription` for manual cancellation if needed.

> ⚠️ **Warning:** Circular pipes (A→B→A) cause infinite loops. Ensure your pipe graph is acyclic.

## Ecosystem Integration

**Built on listen_it** — Commands are `ValueListenable` objects, so they work with all listen_it operators (map, debounce, where, etc.).

```dart
// Register with get_it
di.registerLazySingleton(() => TodoManager());

// Use commands in your managers
class TodoManager {
  final loadTodosCommand = Command.createAsyncNoParam<List<Todo>>(
    () => api.fetchTodos(),
    [],
  );

  // Debounce search with listen_it operators
  final searchCommand = Command.createSync<String, String>((s) => s, '');

  TodoManager() {
    searchCommand.debounce(Duration(milliseconds: 500)).listen((term, _) {
      loadTodosCommand.run();
    });
  }
}
```

**Want more?** Combine with other flutter_it packages:

- **[listen_it](https://pub.dev/packages/listen_it)** — **Required dependency.** ValueListenable operators and reactive collections.

- **Optional: [watch_it](https://pub.dev/packages/watch_it)** — State management. Watch commands reactively without builders: `watchValue((m) => m.loadCommand)`.

- **Optional: [get_it](https://pub.dev/packages/get_it)** — Service locator for dependency injection. Access managers with commands from anywhere: `di<TodoManager>()`.

> 💡 **flutter_it is a construction set** — command_it works standalone. Add watch_it and get_it when you need reactive UI and dependency injection.

[Explore the ecosystem →](https://flutter-it.dev)

## AI-Assisted Development

This package includes **AI skill files** in the `skills/` directory that help AI coding assistants
(Claude Code, Cursor, GitHub Copilot, and others) generate correct code using command_it.

The skill files teach AI tools critical rules, common patterns, and anti-patterns specific to command_it.
Included skills: `command-it-expert`, `listen-it-expert`, `flutter-architecture-expert`, `feed-datasource-expert`.

They follow the [Agent Skills](https://github.com/agentskills) open standard.

[Learn more about AI skills →](https://flutter-it.dev/misc/ai_skills)

## Learn More

### 📖 Documentation

- **[Getting Started Guide](https://flutter-it.dev/documentation/command_it/getting_started)** — Installation, concepts, first command
- **[Command Basics](https://flutter-it.dev/documentation/command_it/command_basics)** — Creating and running commands
- **[Command Properties](https://flutter-it.dev/documentation/command_it/command_properties)** — value, isRunning, canRun, errors, results
- **[Command Types](https://flutter-it.dev/documentation/command_it/command_types)** — Choosing the right factory function
- **[Error Handling](https://flutter-it.dev/documentation/command_it/error_handling)** — Basic error patterns
- **[Error Filters](https://flutter-it.dev/documentation/command_it/error_filters)** — Advanced error routing
- **[Command Restrictions](https://flutter-it.dev/documentation/command_it/restrictions)** — Conditional execution control
- **[Command Builders](https://flutter-it.dev/documentation/command_it/command_builders)** — Simplifying UI code
- **[Testing Commands](https://flutter-it.dev/documentation/command_it/testing)** — Test patterns and examples
- **[Integration with watch_it](https://flutter-it.dev/documentation/command_it/watch_it_integration)** — Reactive UI updates
- **[Best Practices](https://flutter-it.dev/documentation/command_it/best_practices)** — Patterns, anti-patterns, tips

### 💬 Community & Support

- **[Discord](https://discord.gg/ZHYHYCM38h)** — Get help, share ideas, connect with other developers
- **[GitHub Issues](https://github.com/escamoteur/command_it/issues)** — Report bugs, request features
- **[GitHub Discussions](https://github.com/escamoteur/command_it/discussions)** — Ask questions, share patterns

## Contributing

Contributions are welcome! Please read the [contributing guidelines](CONTRIBUTING.md) before submitting PRs.

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Part of the [flutter_it ecosystem](https://flutter-it.dev)** — Build reactive Flutter apps the easy way. No codegen, no boilerplate, just code.
