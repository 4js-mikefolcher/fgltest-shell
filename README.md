# fgltest-shell

An interactive command-line shell for testing Genero BDL applications, built on
[fgltest](https://github.com/4js-mikefolcher/fgl-test-harness) and the
supported **GGC** (Genero Ghost Client) engine.

Start a Genero program, then drive it by name from the command line: list its
fields and actions, fill fields, trigger actions, check what it shows. Every
step that succeeds is recorded, and `save` writes the recording as an fgltest
action file that `fgltest` replays in batch.

```
$ fgltest_shell --workdir examples/demo demo
starting demo ...
fgltest-shell 0.1.0, driving demo. Type help for the commands.
fgltest> actions
sr_contacts.accept  accept  sr_contacts.cancel  cancel  (…)  sr_contacts.append  append  (…)
fgltest> test "adds a contact"
recording test 'adds a contact'
fgltest> action append
ok
fgltest> fields
formonly.c_name   editable  Edit
formonly.c_city   editable  Edit
formonly.c_phone  editable  Edit
fgltest> fill formonly.c_name "Katherine Johnson"
ok
fgltest> action accept
ok
application message: Added Katherine Johnson.
fgltest> assertRowCount contacts 4
ok: number equals 4.0
fgltest> save contacts.actions.json
saved 1 test, 4 steps to contacts.actions.json
```

Three ways to use it:

- **Interactively**: explore an application and record tests as you go.
- **From a script** (`--script file`): run the same commands in batch, record
  them (`--save`), and check the exit status.
- **One command per call** (`--detach`, then `--send`, then `--stop`): the
  session stays alive between calls, so an AI agent or a build step drives the
  application one action at a time. Add `--json` to get one JSON object per
  answer, which any language can read.

The commands are fgltest's own action-file commands, checked against
fgltest's command table and carried out by fgltest's dispatcher. A step that
works in the shell therefore works the same way when its saved file is
replayed.

See [USERGUIDE.md](USERGUIDE.md) for the full guide and
[CHANGELOG.md](CHANGELOG.md) for the release history.

## Requirements

- Genero BDL **6.x**, or **5.01** or later (`fglcomp`, `fglform`, `fglrun` on
  `PATH`).
- The **GGC toolkit** shipped with Genero (`$FGLDIR/testing_utilities/ggc`):
  source its `envggc`. The shell starts and stops GGC's scenario server itself.
- A Java runtime for the GGC engine.
- [fgltest](https://github.com/4js-mikefolcher/fgl-test-harness) 1.1.2 or
  later, which fglpkg installs with this package.

## Install

```
fglpkg install --save-dev 4js-fgltest-shell
eval "$(fglpkg env)"                         # puts both packages on FGLLDPATH
. "$FGLDIR/testing_utilities/ggc/envggc"     # the GGC engine and ggcadmin
alias fgltest_shell='fglrun "$PWD/.fglpkg/packages/4js-fgltest-shell/com/fourjs/fgltest/shell/fgltest_shell"'
```

Run the shell from your project root. Paths you give it (`--workdir`,
`--script`, `save <file>`) are relative to where you start it.

## Build from source

```
fglpkg install   # fgltest, at the version fglpkg-lock.json pins (make runs it if needed)
make             # the library and both programs into com/fourjs/fgltest/shell/,
                 # the demo application and the self-tests
make check       # fgltest-shell's own tests: no GGC, no server, no application
make test        # drives the demo end to end and replays the recording (needs GGC)
make lint        # validates fglpkg.json as pack/publish would
make clean
```

The committed `fglpkg-lock.json` was resolved on Genero 6. On Genero 5, run
`fglpkg update` once first, so fgltest's Genero 5 build is installed.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
