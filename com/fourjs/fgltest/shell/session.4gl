# fgltest.shell.session — carry out the shell's requests against the
# application.
#
# The fgltest_session program runs this inside a GGC scenario, reading one
# request per line from the shell's socket. handle() itself knows nothing of
# sockets or GGC: it works through the active fgltest Driver, so fgltest-shell's
# own tests drive it with an in-memory one.
#
# A step goes through fgltest's own action-file dispatcher (script.exec), so a
# step typed in the shell does exactly what the same step does when its saved
# action file is replayed by fgltest.

PACKAGE com.fourjs.fgltest.shell

IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.driver
IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.script
IMPORT FGL com.fourjs.fgltest.shell.protocol

#+ Reads the application's MESSAGE and ERROR lines (NULL when empty). The
#+ Driver interface does not offer them, so the program running the session
#+ supplies one (fgltest_session reads them from GGC).
PUBLIC TYPE MessageFn FUNCTION() RETURNS (STRING, STRING)

PRIVATE DEFINE m_messages MessageFn
PRIVATE DEFINE m_hasMessages BOOLEAN
PRIVATE DEFINE m_application STRING

#+ The application name the session reports in its hello.
PUBLIC FUNCTION setApplication(name STRING)
    LET m_application = name
END FUNCTION

#+ Where to read the application's MESSAGE / ERROR lines from.
PUBLIC FUNCTION setMessageSource(fn MessageFn)
    LET m_messages = fn
    LET m_hasMessages = TRUE
END FUNCTION

#+ Carry out one request (a JSON line) and answer it.
#+
#+ @return the reply (a JSON line), and TRUE when the session is over — the
#+         shell said bye, or the application can no longer be driven
PUBLIC FUNCTION handle(text STRING) RETURNS (STRING, BOOLEAN)
    DEFINE req protocol.Request
    DEFINE r protocol.Reply
    DEFINE err STRING
    DEFINE over BOOLEAN

    LET r = protocol.reply()
    CALL protocol.decodeRequest(text) RETURNING req, err
    IF err IS NOT NULL THEN
        LET r.ok = FALSE
        LET r.error = err
        RETURN protocol.encodeReply(r), FALSE
    END IF

    CALL core.resetResults()
    CALL core.clearDriverError()
    LET over = FALSE
    CASE req.op
        WHEN "hello"
            LET r.version = protocol.VERSION
            LET r.application = m_application
            RETURN protocol.encodeReply(r), FALSE
        WHEN "bye"
            RETURN protocol.encodeReply(r), TRUE
        WHEN "step"
            CALL runStep(req.step, r)
        WHEN "fields"
            LET r.fields = inspect.fields()
        WHEN "actions"
            LET r.actions = inspect.actions()
        WHEN "window"
            CALL readWindow(r)
        WHEN "tables"
            CALL readTables(r)
        WHEN "value"
            CALL readValue(req.target, r)
        OTHERWISE
            LET r.ok = FALSE
            LET r.error = SFMT("unknown request '%1'", req.op)
            RETURN protocol.encodeReply(r), FALSE
    END CASE

    IF core.isTrue(core.hasDriverError()) THEN
        LET r.ok = FALSE
        IF r.error IS NULL THEN
            LET r.error = core.driverError()
        END IF
    END IF
    CALL checkApplication(r)
    IF core.isTrue(r.appEnded) THEN
        LET over = TRUE
    ELSE
        CALL readMessages(r)
    END IF
    RETURN protocol.encodeReply(r), over
END FUNCTION

# Run one action-file step and record what its assertions found.
PRIVATE FUNCTION runStep(step script.Step, r protocol.Reply INOUT)
    DEFINE steps script.StepList
    DEFINE i INTEGER

    IF script.requirements(step.command) IS NULL THEN
        LET r.ok = FALSE
        LET r.error = SFMT("unknown command '%1'", step.command)
        RETURN
    END IF
    LET steps[1].* = step.*
    CALL script.exec(steps)
    LET r.checks = core.getResults()
    FOR i = 1 TO r.checks.getLength()
        IF NOT core.isTrue(r.checks[i].passed) THEN
            LET r.ok = FALSE
        END IF
    END FOR
END FUNCTION

PRIVATE FUNCTION readWindow(r protocol.Reply INOUT)
    DEFINE d driver.Driver
    LET d = core.getDriver()
    LET r.window.windowName = d.windowName()
    LET r.window.windowTitle = d.windowTitle()
    LET r.window.formName = d.formName()
    LET r.window.formTitle = d.formTitle()
END FUNCTION

PRIVATE FUNCTION readTables(r protocol.Reply INOUT)
    DEFINE names inspect.StringList
    DEFINE i INTEGER
    LET names = inspect.tables()
    FOR i = 1 TO names.getLength()
        LET r.tables[i].name = names[i]
        LET r.tables[i].rows = inspect.rowCount(names[i])
        LET r.tables[i].currentRow = inspect.currentRow(names[i])
    END FOR
END FUNCTION

PRIVATE FUNCTION readValue(field STRING, r protocol.Reply INOUT)
    DEFINE d driver.Driver
    LET d = core.getDriver()
    IF LENGTH(field) == 0 THEN
        LET r.value = d.currentValue()
    ELSE
        LET r.value = d.fieldValue(field)
    END IF
END FUNCTION

# Whether the application can still be driven. The runner's crash check:
# GGC keeps answering from the last screen after a crash, so look for the
# runtime's error box; a lost or ended session shows as fatal.
#
# An application that ended is not by itself a failure: `action exit` that
# ends it has done what it should, and is recorded. A request it could not
# carry out has a driver error already; a crash is a failure.
PRIVATE FUNCTION checkApplication(r protocol.Reply INOUT)
    DEFINE msg STRING
    IF core.isTrue(core.isFatal()) THEN
        LET r.appEnded = TRUE
        RETURN
    END IF
    CALL core.clearDriverError()   -- the probe must run even after a driver error
    LET msg = inspect.applicationError()
    CALL core.clearDriverError()
    IF msg IS NOT NULL THEN
        LET r.ok = FALSE
        LET r.appEnded = TRUE
        LET r.appError = msg
    END IF
END FUNCTION

PRIVATE FUNCTION readMessages(r protocol.Reply INOUT)
    DEFINE msg, err STRING
    IF NOT core.isTrue(m_hasMessages) THEN
        RETURN
    END IF
    CALL m_messages() RETURNING msg, err
    LET r.message = msg
    LET r.errorLine = err
END FUNCTION
