# fgltest-shell user guide

fgltest-shell drives a running Genero application from the command line. You
name what to do (fill this field, trigger that action, check this value), the
shell does it through GGC, and you see the result at once. What works is
recorded, and becomes an fgltest test.

- [How it works](#how-it-works)
- [Starting the shell](#starting-the-shell)
- [Looking at the application](#looking-at-the-application)
- [Test steps](#test-steps)
- [Recording tests](#recording-tests)
- [Scripts](#scripts)
- [JSON answers](#json-answers)
- [One command per call: AI agents and build steps](#one-command-per-call-ai-agents-and-build-steps)
- [Exit status](#exit-status)
- [Things to know](#things-to-know)
- [Troubleshooting](#troubleshooting)

## How it works

```
 you / a script / an agent
          │  commands
          ▼
   fgltest_shell ──── local socket (JSON lines) ────▶ fgltest_session ──GGC──▶ your application
   reads commands,                                     a GGC scenario: carries
   shows answers, records                              out each request with fgltest
```

`fgltest_shell` starts GGC's scenario server (unless one is running already),
then starts `fgltest_session`, a GGC scenario that runs your application. A
GGC scenario runs in a process of its own and cannot read your terminal, so
the two programs talk over a socket on `127.0.0.1`.

Each test step goes through fgltest's own action-file dispatcher
(`script.exec`), with its checks and its error handling. A step that works in
the shell therefore works the same when the file you saved is replayed by
`fgltest`.

## Starting the shell

Give the shell the application to drive, in one of four ways:

| Start it with | The application is |
|---|---|
| `fgltest_shell [options] <program> [argument ...]` | a program, run with `fglrun <program> <argument ...>` |
| `fgltest_shell [options] --command-line "<command>"` | started by this command |
| `fgltest_shell [options] --url <url>` | a GAS application (GGC's `ua` mode) |
| `fgltest_shell [options] --config fgltest.json [--suite <name>]` | the one a suite of your fgltest config runs |

The program and its arguments come last: every word after the program is
passed to it. Use `--` before a program whose name starts with `-`.

| Option | Meaning |
|---|---|
| `--workdir <dir>` | The application's working directory (default: the current one). |
| `--app <name>` | The application name recorded in saved files (default: the program's name). |
| `--script <file>` | Run the commands in `<file>` (`-` for standard input), then end. See [Scripts](#scripts). |
| `--save <file>` | Save the recording to `<file>` when the shell ends. |
| `--json` | Answer each command with one JSON object per line. See [JSON answers](#json-answers). |
| `--port <n>` | The GGC scenario server's port (default 6500, or `FGLTEST_PORT`). |
| `--session-port <n>` | The first port tried for the shell's socket to its session (default 6510). |
| `--timeout <seconds>` | How long the application may take to start (default 60). |
| `--outdir <dir>` | Where the logs go: `fgltest_shell.log` (the session) and `ggcserver.log` (default: here). |
| `--detach`, `--send`, `--stop`, `--session`, `--idle` | See [One command per call](#one-command-per-call-ai-agents-and-build-steps). |
| `-h`, `--help`; `-V`, `--version` | |

The GGC environment must be active (`. "$FGLDIR/testing_utilities/ggc/envggc"`),
with your application's own environment (`FGLLDPATH`, database settings, and
so on), which the session and the application inherit.

A scenario server the shell starts is stopped when the shell ends. A server
that was running already is left alone.

## Looking at the application

```
fgltest> window
window screen  "Contacts"
form   contacts  "Contacts"
fgltest> fields
formonly.name  editable  Edit
formonly.city  editable  Edit
fgltest> actions
sr_contacts.accept  accept  sr_contacts.cancel  cancel  sr_contacts.close  close  (…)
fgltest> tables
contacts: 3 rows, current row 1
fgltest> value formonly.name
[Ada Lovelace]
```

| Command | Shows |
|---|---|
| `fields` | The current window's fields: name, state (editable, read-only, disabled, hidden) and widget. |
| `actions [all]` | The active actions; with `all`, every action, marking the inactive ones. |
| `window` | The current window and form, with their titles. |
| `tables` | The current window's tables, with their row counts and current rows. |
| `value [field]` | A field's value, in brackets; without a field, the current field's. |
| `help [command]` | The commands, or how to call one and what it does. |

These are not recorded. When the application's MESSAGE or ERROR line
changes, the shell shows it after the answer:

```
fgltest> action accept
ok
application error line: A contact needs a name.
```

## Test steps

Every fgltest action-file command can be typed, as words: the command, then
what it needs, in the order target, column, row, value. Quote a word that
has spaces with `"..."` (where `\"` and `\\` are escapes) or `'...'` (taken
as it is). Command names ignore case.

```
fill formonly.customer "Big Co"
action accept
selectRow contacts 3
assertCellAtRow contacts name 3 "Alan Turing"
assertField formonly.note 'say "hi"'
```

`help` lists them all. In short:

| Kind | Commands |
|---|---|
| Interact | `action`, `field`, `fill`, `enter`, `clear`, `key`, `pause`, `selectRow`, `focusCell` |
| Check fields | `assertField`, `assertFieldNot`, `assertFieldContains`, `assertFieldMatches`, `assertCurrent`, `assertFieldEnabled`, `assertFieldDisabled`, `assertFieldEditable`, `assertFieldReadOnly`, `assertFieldExists`, `assertFieldMissing`, `assertFieldCount` |
| Check actions | `assertActionActive`, `assertActionInactive`, `assertActionExists`, `assertActionMissing` |
| Check the window | `assertFormName`, `assertFormTitle`, `assertWindowName`, `assertWindowTitle` |
| Check tables | `assertTableExists`, `assertCell`, `assertCellContains`, `assertCellMatches`, `assertCellAtRow`, `assertRowCount`, `assertRowCountAtLeast`, `assertRowCountAtMost`, `assertCurrentRow` |

The answer says how the step went:

| Answer | Meaning |
|---|---|
| `ok` | The step was carried out. |
| `ok: value equals [x]` | A check held. |
| `FAIL: expected [x] to equal [y]` | A check did not hold. |
| `ERROR: (GGC-7) FormField or Table named 'x' not found.` | The step could not be carried out: a name the application does not have, an action that is not active. The application is unchanged and the session carries on. |

A step that fails or errors is not recorded, and the answer says so.

## Recording tests

Each step that succeeds is added to the current test. If you have not named
one, the first step starts a test called `test 1`.

| Command | Does |
|---|---|
| `test <name>` | Start recording a new test. If the current test has no steps yet, it is renamed instead. |
| `steps` | Show the current test's steps. |
| `undo` | Drop the current test's last step. The step is not undone in the application. |
| `save <file.actions.json>` | Write every test with steps as an fgltest action file. The file is read back with fgltest's own loader before the shell says it is saved. |
| `run <file.actions.json>` | Run an action file's tests in this session, as fgltest would: hooks, `skip` and `only` included. Its steps are not recorded. |
| `quit` (or `exit`) | End the session. With unsaved steps, you are asked to quit a second time. |

Replay a saved file with fgltest, from a config that names it:

```json
{
  "suites": [
    {
      "name": "contacts",
      "actions": "contacts.actions.json",
      "mode": "tcp",
      "workdir": "examples/demo",
      "commandLine": "fglrun demo"
    }
  ]
}
```

Every test in a file runs in one application session, one after the other,
just as you recorded them. A test therefore starts where the previous one
ended.

## Scripts

`--script <file>` runs the commands in a file, one per line, then ends. Blank
lines and lines starting with `#` are skipped. Each command is shown with its
answer, so the output reads as a transcript. `--save` writes what was recorded:

```
fgltest_shell --script examples/demo/demo.shell --save results/demo.actions.json \
    --outdir results --workdir examples/demo demo
```

The exit status is 1 if any command failed (see [Exit status](#exit-status)).
`--script -` reads the commands from standard input.

## JSON answers

With `--json`, each command is answered with one JSON object on one line.
Programs in any language can read these. Every answer has the same members:

| Member | Holds |
|---|---|
| `command` | The command, as fgltest spells it (`fill`, `assertField`, `fields`, …). |
| `ok` | `false` when the command failed: a check did not hold, a step could not be carried out, or the command was not understood. |
| `error` | Why it failed, when it did. |
| `output` | The text the shell would have shown. |
| `checks` | For a step: the checks it made, each `{passed, message, detail}`. |
| `fields` | For `fields`: `{name, colName, widget, varType, active, hidden, readOnly}` each. |
| `actions` | For `actions`: `{name, active, text}` each. |
| `window` | For `window`: `{windowName, windowTitle, formName, formTitle}`. |
| `tables` | For `tables`: `{name, rows, currentRow}` each. |
| `value` | For `value`. |
| `message`, `errorLine` | The application's MESSAGE and ERROR lines, when it has them. |
| `appEnded` | `true` once the application can no longer be driven. |
| `appError` | The runtime error it stopped with, if it crashed. |
| `version`, `application` | In the first answer (`hello`), sent when the shell starts. |

```
$ printf 'action append\nfields\n' | fgltest_shell --json --workdir examples/demo demo
{"command":"hello","ok":true,…,"version":"0.1.0","application":"demo","output":"fgltest-shell 0.1.0, driving demo. …"}
{"command":"action","ok":true,"checks":[],"appEnded":false,…,"output":"ok"}
{"command":"fields","ok":true,…,"fields":[{"name":"formonly.c_name","colName":"c_name","widget":"Edit",…}],…}
```

Until 1.0.0 the reply's members may still change between minor versions (see
the CHANGELOG).

## One command per call: AI agents and build steps

An interactive shell needs someone to keep typing into it. An AI agent or a
build step runs one command and reads its answer, then runs the next. For
those callers the session can outlive the shell:

```
fgltest_shell --detach --workdir examples/demo demo     # start; returns once the application is up
fgltest_shell --send fields                             # one command per call…
fgltest_shell --send "action append" --send "fill formonly.c_name Mary" --send "action accept"
fgltest_shell --json --send "assertRowCount contacts 4"
fgltest_shell --send "save results/agent.actions.json"
fgltest_shell --stop                                    # end it (as --send quit does)
```

- `--detach` takes the same options as an interactive start. It leaves the
  application and its session running, and returns.
- `--send "<command>"` carries out any shell command in that session. Repeat
  it to carry out several in one call; each is then shown with its answer.
  `--json` works as above.
- The recording carries on across calls. `steps`, `undo`, `test` and `save`
  work as they do interactively, and still work after the application has
  ended.
- `--stop` ends the session and the application. It stops the scenario server
  if `--detach` started it, and says if recorded steps were not saved.
- What a call needs to find the session is kept in a session file,
  `fgltest_shell.session.json` in `--outdir`. Give `--outdir` (or
  `--session <file>`) the same way to every call, and use different session
  files to drive several applications at once. `--detach` refuses to start a
  second session on a session file whose session is still running.
- A detached session that receives nothing for `--idle` seconds (default 3600)
  ends on its own, and so does its application.

Each call returns as soon as its answers are written, even when its output is
read through a pipe (`subprocess.run(..., capture_output=True)` and the
like). The background processes do not hold it open:

```python
import json, subprocess

SHELL = ".fglpkg/packages/4js-fgltest-shell/com/fourjs/fgltest/shell/fgltest_shell"

def shell(*commands):
    args = ["fglrun", SHELL, "--json"]
    for c in commands:
        args += ["--send", c]
    out = subprocess.run(args, capture_output=True, text=True).stdout
    return [json.loads(line) for line in out.splitlines()]

subprocess.run(["fglrun", SHELL, "--detach", "--workdir", "examples/demo", "demo"], check=True)
actions = [a["name"] for a in shell("actions")[0]["actions"] if a["active"]]
print(shell("action append", "fill formonly.c_name Mary", "action accept")[-1]["message"])
subprocess.run(["fglrun", SHELL, "--stop"])
```

## Exit status

| Status | When |
|---|---|
| 0 | Every command succeeded (always 0 for an interactive session that started). |
| 1 | With `--script`, `--json` or `--send`: a command failed, or `--save` could not save. |
| 2 | Bad arguments or config, or `--detach` while a session is already running. |
| 3 | The application could not be started, or `--send` found no session. |

## Things to know

- **`fill` moves the focus**, as a user would: the program's `AFTER FIELD`
  for the field it leaves and `BEFORE FIELD` for the one it enters run on the
  way. Then it puts the value in, so fields can be filled in any order. When
  the program keeps the focus where it is, the step fails with an error naming
  both fields: `cannot fill 'formonly.c_city': the program kept the focus on
  'formonly.c_name'`. That happens when an `AFTER FIELD` rejects the current
  field's value, or when the field cannot be entered (`NOENTRY`).
- **When the application ends**, for instance `action cancel` on its last
  dialog, the step answers `ok`, and the next command reports that the
  application has ended. GGC only notices on the following request. The step
  that ended it is recorded, so a replay ends the application at the same
  point. After that, only the recording commands work: `save`, `steps`,
  `undo`, `test`, then `quit`.
- **Table cells.** `assertCell` reads the current row. `assertCellAtRow` moves
  to the row first, so it can read a row that is not on screen. `table` is
  the table's name as `tables` lists it, and `column` is the column name
  without `formonly.`.
- **A crash.** When the application stops with a runtime error, the shell says
  so, with the error, and the session ends.
- **Windows.** The shell is built and tested on macOS (Genero 6.00.03 and
  5.01.02). The program has no shell scripts, but `--detach` has not been
  tried on Windows yet.
- **Load testing** is not what this is for. GGC drives each session over the
  front-end protocol, which does not reach the thousands of virtual users a
  load-testing tool such as k6 does.

## Troubleshooting

| Symptom | Look at |
|---|---|
| `the application did not start within N seconds` | Check that the command runs with `fglrun` in the working directory, then read `fgltest_shell.log` (the session) and `ggcserver.log` in `--outdir`. |
| `cannot start the GGC scenario server: ggcadmin is not on PATH` | Source `$FGLDIR/testing_utilities/ggc/envggc`. |
| `the session closed unexpectedly` | The session process ended: see `fgltest_shell.log`. |
| `no session is running` (with `--send`) | Start one with `--detach`, and give `--outdir` / `--session` the same way to every call. |
| `cannot fill 'x': the program kept the focus on 'y'` | The program would not leave `y`. Its `AFTER FIELD` rejected `y`'s value (the application's ERROR line usually says why), or `x` cannot be entered. |
