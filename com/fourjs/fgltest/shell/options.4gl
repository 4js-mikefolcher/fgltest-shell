# fgltest.shell.options — fgltest_shell's command line.
#
#   fgltest_shell [options] <program> [argument ...]
#   fgltest_shell [options] --command-line "<command>"
#   fgltest_shell [options] --url <GAS application URL>
#   fgltest_shell [options] --config fgltest.json [--suite <name>]
#
# and, for a session that outlives each call (an AI agent, a build script):
#
#   fgltest_shell --detach [options] <program> [argument ...]
#   fgltest_shell --send "<command>" [--send "<command>" ...]
#   fgltest_shell --stop
#
# Kept out of the program so fgltest-shell's own tests reach it.

PACKAGE com.fourjs.fgltest.shell

IMPORT os
IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.server

#+ How long to wait for the application to start, when not given.
PUBLIC CONSTANT DEFAULT_TIMEOUT = 60
#+ The first port tried for the shell's socket to its session.
PUBLIC CONSTANT DEFAULT_SESSION_PORT = 6510
#+ How long a detached session waits for the next --send, when not given.
PUBLIC CONSTANT DEFAULT_IDLE = 3600

PUBLIC TYPE Options RECORD
    program STRING,          -- the program to run, by fglrun
    arguments inspect.StringList,
    commandLine STRING,      -- or the command that starts the application
    url STRING,              -- or its GAS URL (GGC ua mode)
    config STRING,           -- or a suite of this fgltest config
    suite STRING,
    workdir STRING,          -- the application's working directory
    app STRING,              -- the application name to record
    port INTEGER,            -- the GGC scenario server's port
    sessionPort INTEGER,     -- the first port to try for the session socket
    script STRING,           -- read commands from this file ("-": standard input)
    json BOOLEAN,            -- answer in JSON, one object per line
    save STRING,             -- save the recording here when the shell ends
    outdir STRING,           -- where the logs go
    timeout INTEGER,         -- seconds to wait for the application to start
    detach BOOLEAN,          -- start a session that outlives this call
    send inspect.StringList, -- commands for the detached session
    stop BOOLEAN,            -- end the detached session
    session STRING,          -- the detached session's file
    idle INTEGER,            -- seconds it waits for the next --send
    help BOOLEAN,
    version BOOLEAN
END RECORD

#+ Parse the shell's arguments.
#+
#+ @return the options, and NULL or what is wrong with the arguments
PUBLIC FUNCTION parse(args inspect.StringList) RETURNS (Options, STRING)
    DEFINE o Options
    DEFINE i, n INTEGER
    DEFINE a, v, err STRING

    INITIALIZE o.* TO NULL
    LET o.json = FALSE
    LET o.detach = FALSE
    LET o.stop = FALSE
    LET o.help = FALSE
    LET o.version = FALSE
    LET n = args.getLength()
    LET i = 1
    WHILE i <= n
        LET a = args[i]
        IF a.getIndexOf("-", 1) != 1 THEN
            # The program, and every word after it is its own.
            LET o.program = a
            FOR i = i + 1 TO n
                LET o.arguments[o.arguments.getLength() + 1] = args[i]
            END FOR
            EXIT WHILE
        END IF
        CASE a
            WHEN "-h" LET o.help = TRUE
            WHEN "--help" LET o.help = TRUE
            WHEN "-V" LET o.version = TRUE
            WHEN "--version" LET o.version = TRUE
            WHEN "--json" LET o.json = TRUE
            WHEN "--detach" LET o.detach = TRUE
            WHEN "--stop" LET o.stop = TRUE
            WHEN "--" -- the program follows, even if it starts with "-"
                IF i == n THEN
                    RETURN o, "a program must follow --"
                END IF
                LET o.program = args[i + 1]
                FOR i = i + 2 TO n
                    LET o.arguments[o.arguments.getLength() + 1] = args[i]
                END FOR
                EXIT WHILE
            OTHERWISE
                IF NOT takesValue(a) THEN
                    RETURN o, SFMT("unknown option '%1'", a)
                END IF
                IF i == n THEN
                    RETURN o, SFMT("%1 needs a value", a)
                END IF
                LET i = i + 1
                LET v = args[i]
                LET err = setValue(o, a, v)
                IF err IS NOT NULL THEN
                    RETURN o, err
                END IF
        END CASE
        LET i = i + 1
    END WHILE
    IF o.help OR o.version THEN
        RETURN o, NULL
    END IF
    RETURN o, check(o)
END FUNCTION

# Options that take a value.
PRIVATE FUNCTION takesValue(a STRING) RETURNS BOOLEAN
    CASE a
        WHEN "--command-line" RETURN TRUE
        WHEN "--url" RETURN TRUE
        WHEN "--config" RETURN TRUE
        WHEN "--suite" RETURN TRUE
        WHEN "--workdir" RETURN TRUE
        WHEN "--app" RETURN TRUE
        WHEN "--port" RETURN TRUE
        WHEN "--session-port" RETURN TRUE
        WHEN "--script" RETURN TRUE
        WHEN "--save" RETURN TRUE
        WHEN "--outdir" RETURN TRUE
        WHEN "--timeout" RETURN TRUE
        WHEN "--send" RETURN TRUE
        WHEN "--session" RETURN TRUE
        WHEN "--idle" RETURN TRUE
    END CASE
    RETURN FALSE
END FUNCTION

PRIVATE FUNCTION setValue(o Options INOUT, a STRING, v STRING) RETURNS STRING
    CASE a
        WHEN "--command-line" LET o.commandLine = v
        WHEN "--url" LET o.url = v
        WHEN "--config" LET o.config = v
        WHEN "--suite" LET o.suite = v
        WHEN "--workdir" LET o.workdir = v
        WHEN "--app" LET o.app = v
        WHEN "--script" LET o.script = v
        WHEN "--save" LET o.save = v
        WHEN "--outdir" LET o.outdir = v
        WHEN "--session" LET o.session = v
        WHEN "--send" LET o.send[o.send.getLength() + 1] = v
        WHEN "--idle"
            IF NOT isCount(v) OR v == "0" THEN
                RETURN SFMT("--idle must be a number of seconds, not '%1'", v)
            END IF
            LET o.idle = v
        WHEN "--port"
            LET o.port = toPort(v)
            IF o.port IS NULL THEN
                RETURN SFMT("--port must be a port number (1-%1), not '%2'", server.MAX_PORT, v)
            END IF
        WHEN "--session-port"
            LET o.sessionPort = toPort(v)
            IF o.sessionPort IS NULL THEN
                RETURN SFMT("--session-port must be a port number (1-%1), not '%2'", server.MAX_PORT, v)
            END IF
        WHEN "--timeout"
            IF NOT isCount(v) OR v == "0" THEN
                RETURN SFMT("--timeout must be a number of seconds, not '%1'", v)
            END IF
            LET o.timeout = v
    END CASE
    RETURN NULL
END FUNCTION

# Exactly one way to reach the application, and nothing that does not go with it.
PRIVATE FUNCTION check(o Options) RETURNS STRING
    DEFINE ways INTEGER
    LET ways = 0
    IF LENGTH(o.program) > 0 THEN
        LET ways = ways + 1
    END IF
    IF LENGTH(o.commandLine) > 0 THEN
        LET ways = ways + 1
    END IF
    IF LENGTH(o.url) > 0 THEN
        LET ways = ways + 1
    END IF
    IF LENGTH(o.config) > 0 THEN
        LET ways = ways + 1
    END IF
    # Talking to a detached session: it has its application already.
    IF o.send.getLength() > 0 OR o.stop THEN
        IF o.send.getLength() > 0 AND o.stop THEN
            RETURN "give --send or --stop, not both (--send quit also ends the session)"
        END IF
        IF ways > 0 OR o.detach THEN
            RETURN "--send and --stop talk to the session --detach started: give them no application"
        END IF
        IF LENGTH(o.script) > 0 OR LENGTH(o.save) > 0 THEN
            RETURN "--script and --save do not go with --send or --stop (send save <file> instead)"
        END IF
        RETURN NULL
    END IF
    IF o.detach AND (LENGTH(o.script) > 0 OR LENGTH(o.save) > 0) THEN
        RETURN "--script and --save do not go with --detach: send the commands with --send"
    END IF
    IF ways == 0 THEN
        RETURN "say which application to drive: a program, --command-line, --url or --config"
    END IF
    IF ways > 1 THEN
        RETURN "give only one of: a program, --command-line, --url, --config"
    END IF
    IF LENGTH(o.suite) > 0 AND LENGTH(o.config) == 0 THEN
        RETURN "--suite needs --config"
    END IF
    IF LENGTH(o.workdir) > 0 AND (LENGTH(o.url) > 0 OR LENGTH(o.config) > 0) THEN
        RETURN "--workdir goes with a program or --command-line (a config suite has its own)"
    END IF
    RETURN NULL
END FUNCTION

#+ The command that starts the application: --command-line as given, else
#+ `fglrun <program> <argument>...` (NULL for --url and --config). The words
#+ are joined with spaces, as GGC splits them: use --command-line for
#+ anything a plain word list cannot say.
PUBLIC FUNCTION applicationCommand(o Options) RETURNS STRING
    DEFINE b base.StringBuffer
    DEFINE i INTEGER
    IF LENGTH(o.commandLine) > 0 THEN
        RETURN o.commandLine
    END IF
    IF LENGTH(o.program) == 0 THEN
        RETURN NULL
    END IF
    LET b = base.StringBuffer.create()
    CALL b.append("fglrun ")
    CALL b.append(o.program)
    FOR i = 1 TO o.arguments.getLength()
        CALL b.append(" ")
        CALL b.append(o.arguments[i])
    END FOR
    RETURN b.toString()
END FUNCTION

#+ The application name to record: --app, else the program's name without its
#+ directory or extension, else the suite's name, else "application".
PUBLIC FUNCTION applicationName(o Options) RETURNS STRING
    DEFINE name STRING
    IF LENGTH(o.app) > 0 THEN
        RETURN o.app
    END IF
    IF LENGTH(o.program) > 0 THEN
        LET name = plainName(o.program)
    ELSE
        LET name = commandName(o.commandLine)
    END IF
    IF LENGTH(name) > 0 THEN
        RETURN name
    END IF
    IF LENGTH(o.suite) > 0 THEN
        RETURN o.suite
    END IF
    RETURN "application"
END FUNCTION

#+ The name of the program a command line runs (the word after fglrun and
#+ its options, else the first word), without its directory or extension;
#+ NULL for an empty command line.
PUBLIC FUNCTION commandName(cmd STRING) RETURNS STRING
    IF LENGTH(cmd) == 0 THEN
        RETURN NULL
    END IF
    RETURN plainName(programOf(cmd))
END FUNCTION

PRIVATE FUNCTION plainName(path STRING) RETURNS STRING
    DEFINE name STRING
    DEFINE i INTEGER
    IF LENGTH(path) == 0 THEN
        RETURN NULL
    END IF
    LET name = os.Path.baseName(path)
    LET i = name.getIndexOf(".", 1)
    IF i > 1 THEN
        LET name = name.subString(1, i - 1)
    END IF
    RETURN name
END FUNCTION

# The program a command line runs: the word after fglrun (and its options),
# else the first word.
PRIVATE FUNCTION programOf(cmd STRING) RETURNS STRING
    DEFINE t base.StringTokenizer
    DEFINE w, first STRING
    LET t = base.StringTokenizer.create(cmd, " ")
    IF NOT t.hasMoreTokens() THEN
        RETURN NULL
    END IF
    LET first = t.nextToken()
    IF os.Path.baseName(first) != "fglrun" THEN
        RETURN first
    END IF
    WHILE t.hasMoreTokens()
        LET w = t.nextToken()
        IF w.getIndexOf("-", 1) != 1 THEN
            RETURN w
        END IF
    END WHILE
    RETURN first
END FUNCTION

#+ The --help text.
PUBLIC FUNCTION usage() RETURNS STRING
    DEFINE b base.StringBuffer
    LET b = base.StringBuffer.create()
    CALL b.append("usage: fgltest_shell [options] <program> [argument ...]\n")
    CALL b.append("       fgltest_shell [options] --command-line \"<command>\"\n")
    CALL b.append("       fgltest_shell [options] --url <GAS application URL>\n")
    CALL b.append("       fgltest_shell [options] --config fgltest.json [--suite <name>]\n")
    CALL b.append("\n")
    CALL b.append("Starts a Genero application under GGC and drives it from commands: list its\n")
    CALL b.append("fields and actions, fill fields, trigger actions, check values. Each step that\n")
    CALL b.append("succeeds is recorded, and `save` writes the recording as an fgltest action file.\n")
    CALL b.append("\n")
    CALL b.append("options:\n")
    CALL b.append("  --workdir <dir>        the application's working directory (default: here)\n")
    CALL b.append("  --app <name>           the application name to record (default: the program's)\n")
    CALL b.append("  --script <file>        run the commands in <file> (- for standard input), then end\n")
    CALL b.append("  --save <file>          save the recording to <file> when the shell ends\n")
    CALL b.append("  --json                 answer each command with one JSON object per line\n")
    CALL b.append(SFMT("  --port <n>             the GGC scenario server's port (default %1)\n", server.DEFAULT_PORT))
    CALL b.append(SFMT("  --session-port <n>     the first port to try for the session (default %1)\n", DEFAULT_SESSION_PORT))
    CALL b.append(SFMT("  --timeout <seconds>    how long the application may take to start (default %1)\n", DEFAULT_TIMEOUT))
    CALL b.append("  --outdir <dir>         where the session and server logs go (default: here)\n")
    CALL b.append("\n")
    CALL b.append("A session that outlives each call, for AI agents and scripts:\n")
    CALL b.append("  --detach               start the application, leave its session running, return\n")
    CALL b.append("  --send \"<command>\"     carry out a command in that session (repeat for several)\n")
    CALL b.append("  --stop                 end that session (as --send quit does)\n")
    CALL b.append("  --session <file>       the session's file (default: fgltest_shell.session.json\n")
    CALL b.append("                         in --outdir), to run more than one at a time\n")
    CALL b.append(SFMT("  --idle <seconds>       a detached session ends after this long unused (default %1)\n", DEFAULT_IDLE))
    CALL b.append("  -h, --help             this text\n")
    CALL b.append("  -V, --version          the version\n")
    CALL b.append("\n")
    CALL b.append("Type help in the shell for its commands. Exit status: 0 when every command\n")
    CALL b.append("succeeded, 1 when one failed (with --script or --send), 2 for bad arguments,\n")
    CALL b.append("3 when the application could not be started or no session is running.")
    RETURN b.toString()
END FUNCTION

PRIVATE FUNCTION toPort(v STRING) RETURNS INTEGER
    DEFINE p INTEGER
    IF NOT isCount(v) THEN
        RETURN NULL
    END IF
    LET p = v
    IF p <= 0 OR p > server.MAX_PORT THEN
        RETURN NULL
    END IF
    RETURN p
END FUNCTION

PRIVATE FUNCTION isCount(v STRING) RETURNS BOOLEAN
    IF v IS NULL OR LENGTH(v) == 0 OR LENGTH(v) > 9 THEN
        RETURN FALSE
    END IF
    RETURN v.matches("^[0-9]+$")
END FUNCTION
