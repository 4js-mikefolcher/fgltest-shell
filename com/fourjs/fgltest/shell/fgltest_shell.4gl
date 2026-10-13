# fgltest_shell — drive a Genero application from the command line.
#
#   fgltest_shell [options] <program> [argument ...]
#
# Starts the application under GGC and reads commands: look at its fields and
# actions, fill fields, trigger actions, check what it shows. Every step that
# succeeds is recorded, and `save` writes the recording as an fgltest action
# file, which fgltest then replays. See options.usage() for the arguments.
#
# With --detach the session outlives this program: each later call carries out
# its --send commands in it and leaves, so a caller that runs one command at a
# time (an AI agent, a build script) drives the application a command per
# call. What a shell keeps between commands — the session's port, the
# recording — is then kept in a session file between calls.
#
# The work is split three ways:
#   this program        arguments, the scenario server, starting the session,
#                       reading lines and printing answers
#   fgltest_session     the GGC scenario: carries out each request against the
#                       application (started by this program, like a suite)
#   repl                what each line means and the answer to show
#
# A GGC scenario cannot read this terminal, so the two programs talk over a
# local TCP socket that the session listens on (see protocol).

IMPORT os
IMPORT util
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.server
IMPORT FGL com.fourjs.fgltest.cli
IMPORT FGL com.fourjs.fgltest.shell.protocol
IMPORT FGL com.fourjs.fgltest.shell.options
IMPORT FGL com.fourjs.fgltest.shell.recording
IMPORT FGL com.fourjs.fgltest.shell.repl
IMPORT FGL com.fourjs.fgltest.shell.words

# Exit statuses (see options.usage()).
CONSTANT EXIT_FAILED = 1
CONSTANT EXIT_USAGE = 2
CONSTANT EXIT_START = 3

# Seconds to wait for the scenario server to start listening.
CONSTANT SERVER_WAIT = 30
# Ports tried, from the first, for the session's socket.
CONSTANT PORTS_TRIED = 100
# Log lines shown when the application could not be started.
CONSTANT LOG_TAIL = 15
# A detached session's file, in --outdir, when --session does not name one.
CONSTANT SESSION_FILE = "fgltest_shell.session.json"
# Seconds to try reaching a detached session.
CONSTANT REACH_WAIT = 2

# A detached session, as its file records it between calls.
TYPE SessionFile RECORD
    version STRING,
    application STRING,
    sessionPort INTEGER,
    serverPort INTEGER,
    ownServer BOOLEAN,
    log STRING,
    shell STRING,          -- repl.state()
    recording STRING       -- recording.state()
END RECORD

DEFINE m_sock base.Channel     -- to the session
DEFINE m_connected BOOLEAN     -- m_sock is open
DEFINE m_sessionPort INTEGER   -- the session's
DEFINE m_out base.Channel      -- standard output
DEFINE m_port INTEGER          -- the scenario server's
DEFINE m_ownServer BOOLEAN     -- this shell started it, and so stops it

MAIN
    DEFINE args inspect.StringList
    DEFINE o options.Options
    DEFINE cfg cli.Config
    DEFINE s cli.SuiteCfg
    DEFINE err, outdir, logFile, text, appName, sessionFile STRING
    DEFINE i, timeout, code INTEGER
    DEFINE up, ok, interactive BOOLEAN

    DEFER INTERRUPT
    LET m_out = base.Channel.create()
    CALL m_out.openFile(NULL, "w")
    LET m_connected = FALSE
    LET m_ownServer = FALSE

    FOR i = 1 TO num_args()
        LET args[i] = arg_val(i)
    END FOR
    CALL options.parse(args) RETURNING o, err
    IF err IS NOT NULL THEN
        CALL say("fgltest_shell: " || err)
        CALL say("(fgltest_shell --help shows the usage)")
        EXIT PROGRAM EXIT_USAGE
    END IF
    IF core.isTrue(o.help) THEN
        CALL say(options.usage())
        EXIT PROGRAM 0
    END IF
    IF core.isTrue(o.version) THEN
        CALL say("fgltest_shell " || protocol.VERSION)
        EXIT PROGRAM 0
    END IF

    LET outdir = NVL(o.outdir, ".")
    LET sessionFile = NVL(o.session, os.Path.join(outdir, SESSION_FILE))
    IF core.isTrue(o.stop) THEN
        LET o.send[1] = "quit"   -- what --stop is
    END IF
    IF o.send.getLength() > 0 THEN
        CALL sendCommands(o, sessionFile)   -- does not return
    END IF
    IF core.isTrue(o.detach) THEN
        CALL checkNoSession(sessionFile)
    END IF

    CALL connection(o) RETURNING cfg, s, appName, err
    IF err IS NOT NULL THEN
        CALL say("fgltest_shell: " || err)
        EXIT PROGRAM EXIT_USAGE
    END IF
    LET timeout = NVL(o.timeout, options.DEFAULT_TIMEOUT)
    LET ok = os.Path.mkDir(outdir)   -- ignore the result: it may exist already
    CALL fgl_setenv("FGLTEST_OUTDIR", outdir)   -- the server's log goes there too
    LET logFile = os.Path.join(outdir, "fgltest_shell.log")
    LET interactive = (o.script IS NULL AND NOT core.isTrue(o.json) AND NOT core.isTrue(o.detach))

    LET m_port = cfg.port
    CALL server.ensure(m_port, -1, SERVER_WAIT) RETURNING up, m_ownServer
    IF NOT up THEN
        IF NOT server.haveGgcAdmin() THEN
            CALL say("fgltest_shell: cannot start the GGC scenario server: ggcadmin is not on PATH (source the GGC environment, envggc)")
        ELSE
            CALL say(SFMT("fgltest_shell: the GGC scenario server did not start on port %1 (see %2)",
                m_port, os.Path.join(outdir, "ggcserver.log")))
        END IF
        EXIT PROGRAM EXIT_START
    END IF

    LET m_sessionPort = freePort(NVL(o.sessionPort, options.DEFAULT_SESSION_PORT))
    IF m_sessionPort IS NULL THEN
        CALL say("fgltest_shell: no free port for the session: give one with --session-port")
        CALL finish(EXIT_START)
    END IF
    CALL fgl_setenv("FGLTEST_SHELL_PORT", m_sessionPort)
    CALL fgl_setenv("FGLTEST_SHELL_APP", appName)
    CALL fgl_setenv("FGLTEST_SHELL_WAIT", timeout)
    CALL fgl_setenv("FGLTEST_SHELL_KEEP", IIF(core.isTrue(o.detach), "1", "0"))
    CALL fgl_setenv("FGLTEST_SHELL_IDLE", NVL(o.idle, options.DEFAULT_IDLE))
    IF interactive THEN
        CALL say(SFMT("starting %1 ...", appName))
    END IF
    # A detached session outlives this program: core.background() keeps it
    # from holding this program's output open (a caller reading it through a
    # pipe would wait for the session to end).
    RUN core.background(cli.suiteCommand(cfg, s, logFile)) WITHOUT WAITING
    IF NOT connect(m_sessionPort, timeout) THEN
        CALL say(SFMT("fgltest_shell: %1 did not start within %2 seconds: check that `%3` runs in %4 (and see %5)",
            appName, timeout, NVL(s.commandLine, s.url), NVL(s.workdir, "."), logFile))
        CALL showTail(logFile)
        CALL finish(EXIT_START)
    END IF

    CALL repl.init(FUNCTION send, o.json, interactive)
    CALL repl.setLostNote("see " || logFile)
    CALL repl.hello() RETURNING text, ok
    CALL say(text)
    IF NOT ok THEN
        CALL finish(EXIT_START)
    END IF

    IF core.isTrue(o.detach) THEN
        CALL detach(o, sessionFile, appName, logFile)   -- does not return
    END IF

    CALL readCommands(o, interactive)

    LET code = 0
    IF LENGTH(o.save) > 0 THEN
        IF NOT saveAtEnd(o.save) THEN
            LET code = EXIT_FAILED
        END IF
    END IF
    IF NOT interactive AND repl.failures() > 0 THEN
        LET code = EXIT_FAILED
    END IF
    CALL repl.bye()
    CALL finish(code)
END MAIN

# The application to drive, as an fgltest suite whose program is the session:
# from --config, else from the program, --command-line or --url.
#+ @return the config and suite, the application's name, and NULL or what is wrong
FUNCTION connection(o options.Options) RETURNS (cli.Config, cli.SuiteCfg, STRING, STRING)
    DEFINE cfg cli.Config
    DEFINE s cli.SuiteCfg
    DEFINE err, appName STRING

    LET appName = options.applicationName(o)
    IF LENGTH(o.config) > 0 THEN
        CALL fromConfig(o) RETURNING cfg, s, err
        IF err IS NOT NULL THEN
            RETURN cfg, s, appName, err
        END IF
        # Named after the program the suite runs, else after the suite.
        IF LENGTH(o.app) == 0 THEN
            LET appName = NVL(options.commandName(s.commandLine), NVL(s.name, appName))
        END IF
    ELSE
        LET err = defaultPort(cfg)
        IF err IS NOT NULL THEN
            RETURN cfg, s, appName, err
        END IF
        IF LENGTH(o.url) > 0 THEN
            LET s.mode = "ua"
            LET s.url = o.url
        ELSE
            LET s.mode = "tcp"
            LET s.workdir = NVL(o.workdir, ".")
            LET s.commandLine = options.applicationCommand(o)
        END IF
    END IF
    IF o.port IS NOT NULL THEN
        LET cfg.port = o.port
    END IF
    LET s.name = "shell"
    LET s.module = os.Path.join(base.Application.getProgramDir(), "fgltest_session")
    LET s.actions = NULL
    # GGC starts the application from the scenario server's directory, which
    # need not be this one.
    IF LENGTH(s.workdir) > 0 THEN
        LET s.workdir = absolute(s.workdir)
        IF NOT os.Path.isDirectory(s.workdir) THEN
            RETURN cfg, s, appName, SFMT("the working directory '%1' does not exist", s.workdir)
        END IF
    END IF
    RETURN cfg, s, appName, NULL
END FUNCTION

# A suite of an fgltest config: the one named by --suite, or its only one. A
# config that only discovers suites lends its connection template.
FUNCTION fromConfig(o options.Options) RETURNS (cli.Config, cli.SuiteCfg, STRING)
    DEFINE cfg cli.Config
    DEFINE s cli.SuiteCfg
    DEFINE text, err, names STRING
    DEFINE i INTEGER

    LET text = readFile(o.config)
    IF text IS NULL THEN
        RETURN cfg, s, SFMT("cannot read config '%1'", o.config)
    END IF
    TRY
        CALL util.JSON.parse(text, cfg)
    CATCH
        RETURN cfg, s, SFMT("invalid config JSON in '%1'", o.config)
    END TRY
    LET err = cli.normalize(cfg, o.config, base.Application.getProgramDir())
    LET err = cli.checkConfig(o.config, text, cfg, err)
    IF err IS NOT NULL THEN
        RETURN cfg, s, err
    END IF
    IF cfg.suites.getLength() == 0 THEN
        IF LENGTH(o.suite) > 0 THEN
            RETURN cfg, s, SFMT("config '%1' lists no suites (no '%2')", o.config, o.suite)
        END IF
        LET s.mode = cfg.discover.mode
        LET s.workdir = cfg.discover.workdir
        LET s.commandLine = cfg.discover.commandLine
        LET s.url = cfg.discover.url
        RETURN cfg, s, NULL
    END IF
    IF LENGTH(o.suite) == 0 THEN
        IF cfg.suites.getLength() == 1 THEN
            RETURN cfg, cfg.suites[1], NULL
        END IF
    ELSE
        FOR i = 1 TO cfg.suites.getLength()
            IF cfg.suites[i].name == o.suite THEN
                RETURN cfg, cfg.suites[i], NULL
            END IF
        END FOR
    END IF
    LET names = cfg.suites[1].name
    FOR i = 2 TO cfg.suites.getLength()
        LET names = names || ", " || cfg.suites[i].name
    END FOR
    IF LENGTH(o.suite) == 0 THEN
        RETURN cfg, s, SFMT("config '%1' has several suites: choose one with --suite (%2)", o.config, names)
    END IF
    RETURN cfg, s, SFMT("config '%1' has no suite '%2' (it has: %3)", o.config, o.suite, names)
END FUNCTION

# The scenario server's port without a config: FGLTEST_PORT, as for fgltest,
# else GGC's default.
FUNCTION defaultPort(cfg cli.Config INOUT) RETURNS STRING
    DEFINE env STRING
    DEFINE p INTEGER
    LET cfg.port = server.DEFAULT_PORT
    LET env = fgl_getenv("FGLTEST_PORT")
    IF LENGTH(env) > 0 THEN
        LET p = env   -- a non-number converts to NULL
        IF p IS NULL OR p <= 0 OR p > server.MAX_PORT THEN
            RETURN SFMT("FGLTEST_PORT must be a port number (1-%1), not '%2'", server.MAX_PORT, env)
        END IF
        LET cfg.port = p
    END IF
    RETURN NULL
END FUNCTION

# The first port from `first` that nothing listens on.
FUNCTION freePort(first INTEGER) RETURNS INTEGER
    DEFINE p INTEGER
    FOR p = first TO first + PORTS_TRIED - 1
        IF p > server.MAX_PORT THEN
            EXIT FOR
        END IF
        IF p != m_port AND NOT server.isUp(p) THEN
            RETURN p
        END IF
    END FOR
    RETURN NULL
END FUNCTION

# Connect to the session, which listens once GGC has started the application.
# Every attempt connects or fails at once, so try each second until `secs`.
FUNCTION connect(port INTEGER, secs INTEGER) RETURNS BOOLEAN
    DEFINE i INTEGER
    LET m_sock = base.Channel.create()
    FOR i = 0 TO secs
        TRY
            CALL m_sock.openClientSocket("127.0.0.1", port, "u", 1)
            LET m_connected = TRUE
            RETURN TRUE
        CATCH
            SLEEP 1
        END TRY
    END FOR
    RETURN FALSE
END FUNCTION

# repl's link to the session: one request line out, one reply line back.
FUNCTION send(request STRING) RETURNS STRING
    DEFINE reply STRING
    TRY
        CALL m_sock.writeLine(request)
        LET reply = m_sock.readLine()
    CATCH
        RETURN NULL
    END TRY
    IF m_sock.isEof() OR LENGTH(reply) == 0 THEN
        RETURN NULL
    END IF
    RETURN reply
END FUNCTION

# repl's link to a detached session: connect on the first request, so the
# commands that need no session (save, steps, undo, test) work without one —
# after the application has ended, say.
FUNCTION sendLazily(request STRING) RETURNS STRING
    IF NOT m_connected THEN
        IF NOT connect(m_sessionPort, REACH_WAIT) THEN
            RETURN NULL
        END IF
    END IF
    RETURN send(request)
END FUNCTION

# ------------------------------------------------------ detached session ----

# --detach: record where the session is, and leave it running.
FUNCTION detach(o options.Options, path STRING, appName STRING, logFile STRING)
    DEFINE st SessionFile
    DEFINE err, again STRING

    LET st.version = protocol.VERSION
    LET st.application = appName
    LET st.sessionPort = m_sessionPort
    LET st.serverPort = m_port
    LET st.ownServer = core.isTrue(m_ownServer)
    LET st.log = logFile
    LET st.shell = repl.state()
    LET st.recording = recording.state()
    LET err = writeFile(path, util.JSON.stringify(st))
    IF err IS NOT NULL THEN
        CALL say("fgltest_shell: " || err)
        CALL repl.bye()
        CALL finish(EXIT_START)
    END IF
    IF NOT core.isTrue(o.json) THEN
        # The options a later call needs to find this session again.
        IF LENGTH(o.session) > 0 THEN
            LET again = " --session " || words.quote(o.session)
        ELSE
            IF LENGTH(o.outdir) > 0 THEN
                LET again = " --outdir " || words.quote(o.outdir)
            END IF
        END IF
        CALL say(SFMT("the session is running: fgltest_shell%1 --send \"<command>\" carries out a command, fgltest_shell%1 --stop ends it",
            NVL(again, "")))
    END IF
    CALL m_sock.close()   -- the session waits for the next shell
    EXIT PROGRAM 0
END FUNCTION

# --send (and --stop, which sends quit): carry out the commands in the
# detached session, then keep what changed for the next call — or, after
# quit, end the session.
FUNCTION sendCommands(o options.Options, path STRING)
    DEFINE st SessionFile
    DEFINE err, text STRING
    DEFINE i, code INTEGER
    DEFINE done BOOLEAN

    CALL readSession(path) RETURNING st, err
    IF err IS NOT NULL THEN
        IF core.isTrue(o.stop) THEN
            CALL say("fgltest_shell: no session is running")
            EXIT PROGRAM 0
        END IF
        CALL say("fgltest_shell: " || err)
        EXIT PROGRAM EXIT_START
    END IF
    LET m_sessionPort = st.sessionPort
    LET m_port = st.serverPort
    LET m_ownServer = core.isTrue(st.ownServer)
    CALL repl.init(FUNCTION sendLazily, o.json, FALSE)
    CALL repl.setLostNote("see " || st.log)
    CALL repl.restore(st.shell)
    LET err = recording.restore(st.recording)
    IF err IS NOT NULL THEN
        CALL say(SFMT("fgltest_shell: %1 (%2)", err, path))
        EXIT PROGRAM EXIT_START
    END IF

    LET done = FALSE
    FOR i = 1 TO o.send.getLength()
        # Several commands in one call: show each with its answer.
        IF o.send.getLength() > 1 AND NOT core.isTrue(o.json) THEN
            CALL say("fgltest> " || o.send[i])
        END IF
        CALL repl.execute(o.send[i]) RETURNING text, done
        IF text IS NOT NULL THEN
            CALL say(text)
        END IF
        IF done THEN
            EXIT FOR
        END IF
    END FOR
    LET code = IIF(repl.failures() > 0, EXIT_FAILED, 0)
    IF done THEN
        CALL repl.bye()
        CALL os.Path.delete(path) RETURNING i
        CALL finish(code)
    END IF
    LET st.shell = repl.state()
    LET st.recording = recording.state()
    LET err = writeFile(path, util.JSON.stringify(st))
    IF err IS NOT NULL THEN
        CALL say("fgltest_shell: " || err)
        LET code = EXIT_FAILED
    END IF
    IF m_connected THEN
        CALL m_sock.close()   -- not bye: the session waits for the next shell
    END IF
    EXIT PROGRAM code
END FUNCTION

# --detach: one detached session per session file. A file whose session no
# longer answers is left over from one that ended, and is replaced.
FUNCTION checkNoSession(path STRING)
    DEFINE st SessionFile
    DEFINE err STRING
    CALL readSession(path) RETURNING st, err
    IF err IS NOT NULL THEN
        RETURN
    END IF
    IF connect(st.sessionPort, 0) THEN
        CALL m_sock.close()
        LET m_connected = FALSE
        CALL say(SFMT("fgltest_shell: a session is already running (%1): end it with --stop, or name another with --session <file>",
            path))
        EXIT PROGRAM EXIT_USAGE
    END IF
END FUNCTION

FUNCTION readSession(path STRING) RETURNS (SessionFile, STRING)
    DEFINE st SessionFile
    DEFINE text STRING
    LET text = readFile(path)
    IF text IS NULL THEN
        RETURN st, SFMT("no session is running: start one with --detach (there is no %1)", path)
    END IF
    TRY
        CALL util.JSON.parse(text, st)
    CATCH
        RETURN st, SFMT("'%1' is not an fgltest-shell session file", path)
    END TRY
    IF st.version IS NULL OR st.version != protocol.VERSION THEN
        RETURN st, SFMT("'%1' was written by fgltest-shell %2, this is %3: stop that session with it",
            path, NVL(st.version, "(unknown)"), protocol.VERSION)
    END IF
    RETURN st, NULL
END FUNCTION

FUNCTION writeFile(path STRING, text STRING) RETURNS STRING
    DEFINE ch base.Channel
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "w")
        CALL ch.writeLine(text)
        CALL ch.close()
    CATCH
        RETURN SFMT("cannot write '%1'", path)
    END TRY
    RETURN NULL
END FUNCTION

# ------------------------------------------------------------ input ----

# Read lines from the terminal (prompting) or the --script file, and carry
# them out until quit, the end of the input, or a session that has gone.
FUNCTION readCommands(o options.Options, interactive BOOLEAN)
    DEFINE input base.Channel
    DEFINE line, text, path STRING
    DEFINE done, echo BOOLEAN

    LET path = o.script
    IF path == "-" THEN
        LET path = NULL
    END IF
    LET input = base.Channel.create()
    TRY
        CALL input.openFile(path, "r")   -- NULL: standard input
    CATCH
        CALL say(SFMT("fgltest_shell: cannot read '%1'", o.script))
        CALL repl.bye()
        CALL finish(EXIT_USAGE)
    END TRY
    # A script's lines are shown with their answers, so its output reads as a
    # transcript; a person sees what they typed already.
    LET echo = (NOT interactive AND NOT core.isTrue(o.json))
    LET done = FALSE
    WHILE NOT done
        IF interactive THEN
            CALL m_out.writeNoNL("fgltest> ")
        END IF
        LET line = input.readLine()
        IF input.isEof() THEN
            IF interactive THEN
                CALL say("")
                IF recording.unsaved() THEN
                    CALL say("(the recorded steps were not saved)")
                END IF
            END IF
            EXIT WHILE
        END IF
        IF int_flag THEN
            LET int_flag = FALSE
        END IF
        IF echo AND LENGTH(line) > 0 THEN
            CALL say("fgltest> " || line)
        END IF
        CALL repl.execute(line) RETURNING text, done
        IF text IS NOT NULL THEN
            CALL say(text)
        END IF
    END WHILE
    CALL input.close()
END FUNCTION

# --save: write the recording when the shell ends, answered like the save
# command (so --json still prints only JSON). FALSE if it was not written.
FUNCTION saveAtEnd(path STRING) RETURNS BOOLEAN
    DEFINE text STRING
    DEFINE before INTEGER
    DEFINE done BOOLEAN
    LET before = repl.failures()
    CALL repl.execute("save " || words.quote(path)) RETURNING text, done
    CALL say(text)
    RETURN (repl.failures() == before)
END FUNCTION

# Close the session, stop the scenario server if this shell started it, and exit.
FUNCTION finish(code INTEGER)
    IF m_connected THEN
        CALL m_sock.close()
        LET m_connected = FALSE
    END IF
    IF m_ownServer THEN
        CALL server.stop(m_port)
    END IF
    EXIT PROGRAM code
END FUNCTION

# The last lines of the session's log: why the application did not start.
FUNCTION showTail(path STRING)
    DEFINE ch base.Channel
    DEFINE lines DYNAMIC ARRAY OF STRING
    DEFINE line STRING
    DEFINE i INTEGER
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "r")
    CATCH
        RETURN
    END TRY
    WHILE TRUE
        LET line = ch.readLine()
        IF ch.isEof() THEN
            EXIT WHILE
        END IF
        LET lines[lines.getLength() + 1] = line
    END WHILE
    CALL ch.close()
    FOR i = IIF(lines.getLength() > LOG_TAIL, lines.getLength() - LOG_TAIL + 1, 1) TO lines.getLength()
        CALL say("  | " || lines[i])
    END FOR
END FUNCTION

FUNCTION absolute(p STRING) RETURNS STRING
    IF os.Path.pathType(p) == "absolute" THEN
        RETURN os.Path.fullPath(p)
    END IF
    RETURN os.Path.fullPath(os.Path.join(os.Path.pwd(), p))
END FUNCTION

FUNCTION readFile(path STRING) RETURNS STRING
    DEFINE ch base.Channel
    DEFINE b base.StringBuffer
    DEFINE line STRING
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "r")
    CATCH
        RETURN NULL
    END TRY
    LET b = base.StringBuffer.create()
    WHILE TRUE
        LET line = ch.readLine()
        IF ch.isEof() THEN
            EXIT WHILE
        END IF
        CALL b.append(line)
        CALL b.append("\n")
    END WHILE
    CALL ch.close()
    RETURN b.toString()
END FUNCTION

FUNCTION say(s STRING)
    CALL m_out.writeLine(s)
END FUNCTION
