# Changelog

All notable changes to fgltest-shell are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): until 1.0.0 the
command set, the `--json` reply shape and the session protocol may still change
between minor versions.

## [0.1.0] - 2026-10-09

First release.

### Added

- `fgltest_shell`: start a Genero application under GGC (a program run by
  `fglrun`, a `--command-line`, a GAS `--url`, or a suite of an fgltest config)
  and drive it from commands.
  - Look at the application: `fields`, `actions [all]`, `window`, `tables`,
    `value [field]`. The application's MESSAGE and ERROR lines are shown when
    they change.
  - Test steps: every fgltest action-file command (`fill`, `action`,
    `assertField`, `selectRow`, `assertCellAtRow`, …), typed as words, checked
    against fgltest's own command table and carried out by fgltest's own
    dispatcher.
  - Recording: each step that succeeds is recorded; `test <name>`, `steps`,
    `undo`, and `save <file>` writes an fgltest action file, validated with
    fgltest's loader before the shell reports it saved. `quit` asks again when
    steps are unsaved.
  - `run <file>`: replay an action file's tests in the current session.
- Batch use: `--script <file>` (or `-` for standard input) runs commands and
  ends, `--save <file>` saves the recording at the end, and the exit status
  says whether every command succeeded.
- `--json`: one JSON object per line for every command, for programs that drive
  the shell (any language that can start a process and read lines).
- One command per call, for AI agents and build steps: `--detach` starts the
  application and leaves its session running, `--send "<command>"` (repeatable)
  carries out commands in it, `--stop` ends it. The recording carries on across
  calls, and a call returns as soon as it has answered, even when its output is
  read through a pipe.
- `fgltest_session`: the GGC scenario behind the shell, reached over a local
  socket (a GGC scenario cannot read the terminal).
- Requires fgltest 1.1.2 or later. With it, `fill` reaches the program in any
  field (it moves the focus first, and fails the step if the program keeps it
  elsewhere), and the scenario server a detached session starts does not hold
  the caller's output open.

### Known limitations

- `--detach` is not yet tested on Windows.
