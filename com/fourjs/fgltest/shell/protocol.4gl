# fgltest.shell.protocol — the messages between the shell and its session.
#
# The shell (the program the user types into) and the session (a GGC scenario
# driving the application) talk over a local TCP socket, one JSON object per
# line: the shell sends a Request, the session answers with a Reply. The same
# JSON is what `fgltest_shell --json` prints, so a program in any language can
# drive the shell and read its answers.
#
# A GGC scenario cannot read the user's terminal: GGC's scenario server starts
# it as a separate process whose standard input is empty. Hence the socket.

PACKAGE com.fourjs.fgltest.shell

IMPORT util
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.driver
IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.script

#+ fgltest-shell's version. Keep in step with fglpkg.json and CHANGELOG.md.
PUBLIC CONSTANT VERSION = "0.1.0"

#+ What the shell asks the session to do.
#+
#+ op is one of: hello, step (run `step`, an action-file step), fields,
#+ actions, window, tables, value (of field `target`, or the current field
#+ when NULL), bye.
PUBLIC TYPE Request RECORD
    op STRING,
    step script.Step,
    target STRING
END RECORD

PUBLIC TYPE WindowInfo RECORD
    windowName STRING,
    windowTitle STRING,
    formName STRING,
    formTitle STRING
END RECORD

PUBLIC TYPE TableInfo RECORD
    name STRING,
    rows INTEGER,
    currentRow INTEGER
END RECORD
PUBLIC TYPE TableList DYNAMIC ARRAY OF TableInfo

#+ The session's answer. `ok` is FALSE when the request failed: a check did
#+ not hold, the driver could not perform it, or the application stopped.
#+
#+ `fgltest_shell --json` answers every command with one of these, `command`
#+ naming the command and `output` holding what the shell would have shown.
PUBLIC TYPE Reply RECORD
    command STRING,              -- set by the shell
    ok BOOLEAN,
    error STRING,                -- why the request could not be performed
    checks core.CheckResultList, -- the assertions a step recorded
    message STRING,              -- the application's MESSAGE line now
    errorLine STRING,            -- the application's ERROR line now
    appEnded BOOLEAN,            -- the application can no longer be driven
    appError STRING,             -- the runtime error it stopped with
    fields inspect.FieldList,
    actions driver.ActionList,
    window WindowInfo,
    tables TableList,
    value STRING,
    version STRING,
    application STRING,
    output STRING                -- set by the shell
END RECORD

#+ A request for `op` with no step or target.
PUBLIC FUNCTION request(op STRING) RETURNS Request
    DEFINE r Request
    INITIALIZE r.* TO NULL
    LET r.op = op
    RETURN r
END FUNCTION

PUBLIC FUNCTION encodeRequest(r Request) RETURNS STRING
    RETURN util.JSON.stringify(r)
END FUNCTION

#+ Parse a request line; NULL error on success.
PUBLIC FUNCTION decodeRequest(text STRING) RETURNS (Request, STRING)
    DEFINE r Request
    INITIALIZE r.* TO NULL
    TRY
        CALL util.JSON.parse(text, r)
    CATCH
        RETURN r, SFMT("not a request: %1", text)
    END TRY
    IF LENGTH(r.op) == 0 THEN
        RETURN r, SFMT("not a request: %1", text)
    END IF
    RETURN r, NULL
END FUNCTION

#+ A reply with every flag set to a definite value (an unset BOOLEAN is NULL,
#+ which reads as false through NOT and AND).
PUBLIC FUNCTION reply() RETURNS Reply
    DEFINE r Reply
    INITIALIZE r.* TO NULL
    LET r.ok = TRUE
    LET r.appEnded = FALSE
    RETURN r
END FUNCTION

PUBLIC FUNCTION encodeReply(r Reply) RETURNS STRING
    RETURN util.JSON.stringify(r)
END FUNCTION

#+ Parse a reply line. A line that is not one (the session crashed mid-reply,
#+ say) gives a failed reply saying so.
PUBLIC FUNCTION decodeReply(text STRING) RETURNS Reply
    DEFINE r Reply
    LET r = reply()
    TRY
        CALL util.JSON.parse(text, r)
    CATCH
        LET r = reply()
        LET r.ok = FALSE
        LET r.error = SFMT("unreadable reply from the session: %1", text)
    END TRY
    LET r.ok = core.isTrue(r.ok)
    LET r.appEnded = core.isTrue(r.appEnded)
    RETURN r
END FUNCTION
