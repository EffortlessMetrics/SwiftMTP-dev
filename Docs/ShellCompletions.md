# Shell Completions

SwiftMTP ships tab-completion scripts for **bash**, **zsh**, and **fish**. These provide completion for all subcommands and global options.

## Installation

### Bash

Add to your `~/.bashrc` or `~/.bash_profile`:

```bash
source /path/to/SwiftMTP/completions/swiftmtp.bash
```

### Zsh

Copy the completion file to a directory in your `$fpath`:

```bash
cp completions/_swiftmtp ~/.zsh/completions/
# Then add to ~/.zshrc (if not already):
# fpath=(~/.zsh/completions $fpath)
# autoload -Uz compinit && compinit
```

Or source it directly in `~/.zshrc`:

```bash
fpath=(/path/to/SwiftMTP/completions $fpath)
autoload -Uz compinit && compinit
```

### Fish

Copy the completion file to your Fish completions directory:

```bash
cp completions/swiftmtp.fish ~/.config/fish/completions/
```

## Regenerating

The completion scripts are hand-maintained to match the CLI's custom argument parser. When adding new subcommands or global options, update all three files in `completions/`.

## What's Completed

- All subcommands: `probe`, `ls`, `pull`, `push`, `cp`, `edit`, `delete`, `move`, `thumb`, `info`, `snapshot`, `mirror`, `bench`, `events`, `quirks`, `health`, `storages`, `collect`, `submit`, `add-device`, `wizard`, `device-lab`, `profile`, `diag`, `usb-dump`, `learn-promote`, `bdd`, `storybook`, `version`
- Global options: `--real-only`, `--mock`, `--mock-profile`, `--json`, `--jsonl`, `--trace-usb`, `--trace-usb-details`, `--strict`, `--safe`, `--vid`, `--pid`, `--bus`, `--address`, `--help`
- Mirror-specific options: `--dry-run`, `--delete`, `--format`, `--conflict`
- File path completion for commands that accept paths
- Mock profile name completion (`pixel7`, `galaxy`, `iphone`, `canon`, `default`)
