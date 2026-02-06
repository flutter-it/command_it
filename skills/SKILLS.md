# Claude Code Skills for command_it

This directory contains **Claude Code skill files** that help AI assistants (like Claude Code, Cursor, GitHub Copilot) generate correct command_it code efficiently.

## What are Skills?

Skills are concise reference guides optimized for AI consumption. They contain:
- Critical rules and constraints
- Common usage patterns
- Anti-patterns with corrections
- Integration examples

**Note**: These are NOT replacements for comprehensive documentation. For detailed guides, see https://flutter-it.dev/documentation/command_it/

## Available Skills

This directory includes:

1. **`command_it-expert.md`** - Command patterns, error handling, restrictions, reactive states
2. **`listen_it-expert.md`** - ValueListenable operators (command_it depends on listen_it)
3. **`flutter-architecture-expert.md`** - High-level app architecture guidance

**Note**: For the ecosystem overview, see `/skills/flutter_it.md` in the monorepo root.

## Installation

To use these skills with Claude Code:

### Option 1: Copy to Global Skills Directory (Recommended)

```bash
# Copy all skills to your global Claude Code skills directory
cp skills/*.md ~/.claude/skills/
```

### Option 2: Symlink (Auto-updates when package updates)

```bash
# Create symlinks (Linux/Mac)
ln -s $(pwd)/skills/command_it-expert.md ~/.claude/skills/command_it-expert.md
ln -s $(pwd)/skills/listen_it-expert.md ~/.claude/skills/listen_it-expert.md
ln -s $(pwd)/skills/flutter-architecture-expert.md ~/.claude/skills/flutter-architecture-expert.md
```

### Option 3: Manual Copy (Windows)

```powershell
# Copy files manually
copy skills\*.md %USERPROFILE%\.claude\skills\
```

## Using the Skills

Once installed, Claude Code will automatically have access to these skills when working on Flutter projects.

**For other AI assistants**:
- **Cursor**: Copy to project root or reference in `.cursorrules`
- **GitHub Copilot**: Copy to `.github/copilot-instructions.md`

## Verification

After installation, you can verify by asking Claude Code:

```
Can you help me create an async command with loading states?
```

Claude should reference the skill and provide correct command patterns with error handling.

## Contents Overview

### command_it-expert.md (~1200 tokens)

Covers:
- Command types (sync vs async)
- **CRITICAL**: Sync commands don't support isRunning
- Restrictions (counterintuitive semantics: `true` = disabled)
- Error handling strategies and filters
- Results handling
- listen_it operators on commands
- Debounced commands pattern
- Integration with watch_it
- Common anti-patterns

### listen_it-expert.md (~1000 tokens)

Covers:
- ValueListenable operators (commands implement ValueListenable)
- Operator chaining (debounce, map, where, etc.)
- **CRITICAL**: Operators return NEW objects (must capture)
- Use listen() instead of addListener()
- Reactive collections
- Common patterns

### flutter-architecture-expert.md (~800 tokens)

Covers:
- Command integration in app architecture
- State management patterns
- Error handling at architecture level

## Why command_it Skills Are Important

command_it has **important constraints** that can cause runtime errors:

1. **Sync commands don't support isRunning** - Will throw assertion error
2. **Restriction semantics are counterintuitive** - `true` means disabled, not enabled
3. **Operator results must be captured** - Debounce returns new command object
4. **Error filters prevent double reporting** - Global vs local listeners

## Documentation Links

- **Comprehensive docs**: https://flutter-it.dev/documentation/command_it/
- **Package README**: https://pub.dev/packages/command_it
- **GitHub**: https://github.com/escamoteur/command_it
- **Discord**: https://discord.gg/ZHYHYCM38h

## Contributing

Found an issue or have suggestions for improving these skills?
- Open an issue on GitHub
- Join the Discord community
- Submit a PR with improvements

---

**Note**: These skills are designed for AI consumption. For human-readable documentation, please visit https://flutter-it.dev
