# fgltest_session — the GGC scenario behind fgltest_shell.
#
# fgltest_shell starts this program the way the fgltest CLI starts a suite
# (`fglrun fgltest_session tcp --port ... --command-line ...`). GGC's scenario
# server then starts the application and runs serve() in a scenario process of
# its own, whose standard input is not the user's terminal. So serve() listens
# on a local TCP port instead, which the shell connects to, and answers its
# requests one JSON line at a time (see protocol and session).
#
# Inputs come from the environment, since ggc.parseOptions() owns the command
# line and rejects arguments it does not know:
#   FGLTEST_SHELL_PORT     the port to listen on (127.0.0.1 only)
#   FGLTEST_SHELL_APP      the application name, as GGC and the hello report it
#   FGLTEST_SHELL_WAIT     seconds to wait for the shell to connect (default 60)
#   FGLTEST_SHELL_KEEP     1: a detached session — when a shell disconnects,
#                          wait for the next one (each `--send` is a new shell)
#   FGLTEST_SHELL_IDLE     seconds a detached session waits for the next shell
#                          before it ends (default 3600)

IMPORT util
IMPORT FGL ggc
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.ggcdriver
IMPORT FGL com.fourjs.fgltest.shell.session

# How long to wait for the shell when FGLTEST_SHELL_WAIT is not set. A shell
# that never connects (it was interrupted while the application started) must
# not leave this process and the application running for ever.
CONSTANT DEFAULT_WAIT = 60
CONSTANT DEFAULT_IDLE = 3600

MAIN
    DEFINE app STRING

    LET app = fgl_getenv("FGLTEST_SHELL_APP")
    IF LENGTH(app) == 0 THEN
        LET app = "application"
    END IF
    CALL core.setDriver(ggcdriver.asDriver())
    CALL session.setApplication(app)
    CALL session.setMessageSource(FUNCTION messages)
    CALL ggc.setApplicationName(app)
    CALL ggc.parseOptions()
    CALL ggc.registerScenario(FUNCTION serve)
    CALL ggc.play()
END MAIN

# The scenario: accept the shell's connection, then answer each request until
# the shell says bye, disconnects, or the application can no longer be driven.
# A detached session outlives the shell: it waits for the next one instead.
FUNCTION serve()
    DEFINE listener, ch base.Channel
    DEFINE ready DYNAMIC ARRAY OF base.Channel
    DEFINE port, wait, idle INTEGER
    DEFINE request, reply STRING
    DEFINE over, keep, served BOOLEAN

    # A mistyped field or action name must fail one request, not end the
    # process: ggc would otherwise EXIT PROGRAM on it (see ggcdriver).
    CALL ggcdriver.beNonFatal()

    LET port = fgl_getenv("FGLTEST_SHELL_PORT")
    LET wait = fgl_getenv("FGLTEST_SHELL_WAIT")
    IF wait IS NULL OR wait <= 0 THEN
        LET wait = DEFAULT_WAIT
    END IF
    LET keep = FALSE   -- an unset variable compares as NULL, not FALSE
    IF fgl_getenv("FGLTEST_SHELL_KEEP") == "1" THEN
        LET keep = TRUE
    END IF
    LET idle = fgl_getenv("FGLTEST_SHELL_IDLE")
    IF idle IS NULL OR idle <= 0 THEN
        LET idle = DEFAULT_IDLE
    END IF
    IF port IS NULL OR port <= 0 THEN
        DISPLAY "fgltest_session: FGLTEST_SHELL_PORT is not set to a port number"
        CALL ggc.end()
        RETURN
    END IF
    LET listener = base.Channel.create()
    TRY
        CALL listener.openServerSocket("127.0.0.1", port, "u")
    CATCH
        DISPLAY SFMT("fgltest_session: cannot listen on port %1: %2", port, err_get(status))
        CALL ggc.end()
        RETURN
    END TRY
    LET ready[1] = listener

    LET over = FALSE
    WHILE NOT over
        IF util.Channels.selectWithTimeout(ready, wait) == 0 THEN
            DISPLAY SFMT("fgltest_session: no shell connected within %1 seconds", wait)
            EXIT WHILE
        END IF
        LET ch = util.Channels.accept(listener)
        LET served = FALSE
        WHILE NOT over
            LET request = ch.readLine()
            IF ch.isEof() THEN
                EXIT WHILE   -- this shell has gone
            END IF
            LET served = TRUE
            CALL session.handle(request) RETURNING reply, over
            CALL ch.writeLine(reply)
            CALL ch.flush()
        END WHILE
        CALL ch.close()
        # A connection that asked nothing was another shell looking for a
        # free port: keep waiting for this session's own.
        IF served THEN
            IF NOT keep THEN
                EXIT WHILE
            END IF
            LET wait = idle
        END IF
    END WHILE
    CALL listener.close()
    DISPLAY "fgltest_session: session over"
    CALL ggc.end()
END FUNCTION

# The application's MESSAGE and ERROR lines, NULL when there is none (or GGC
# could not read them: they are extras, never worth failing a request over).
FUNCTION messages() RETURNS (STRING, STRING)
    DEFINE m ggc.Message
    DEFINE msg, err STRING

    CALL ggc.getMessage() RETURNING m.*
    IF ggc.statusCode == ggc.SUCCESS AND core.isTrue(m.found) THEN
        LET msg = m.message
    END IF
    CALL ggc.getError() RETURNING m.*
    IF ggc.statusCode == ggc.SUCCESS AND core.isTrue(m.found) THEN
        LET err = m.message
    END IF
    RETURN msg, err
END FUNCTION
