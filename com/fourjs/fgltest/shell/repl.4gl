# fgltest.shell.repl — the shell itself: a typed line in, its answer out.
#
# fgltest_shell reads the lines and prints the answers; this module carries
# them out. It reaches the session through a function that sends one request
# line and returns the reply line, so fgltest-shell's own tests run the whole
# shell against an in-process session and an in-memory driver.
#
# Answers are text for a person, or with `json` one protocol.Reply per line,
# its `output` holding the text (see protocol).

PACKAGE com.fourjs.fgltest.shell

IMPORT util
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.script
IMPORT FGL com.fourjs.fgltest.shell.protocol
IMPORT FGL com.fourjs.fgltest.shell.commands
IMPORT FGL com.fourjs.fgltest.shell.recording
IMPORT FGL com.fourjs.fgltest.shell.render

#+ Sends one request line to the session and returns its reply line, or NULL
#+ when the session has gone.
PUBLIC TYPE SendFn FUNCTION(request STRING) RETURNS STRING

PRIVATE DEFINE m_send SendFn
PRIVATE DEFINE m_json BOOLEAN
PRIVATE DEFINE m_confirmQuit BOOLEAN
PRIVATE DEFINE m_quitArmed BOOLEAN
PRIVATE DEFINE m_ended BOOLEAN       -- the application can no longer be driven
PRIVATE DEFINE m_lost BOOLEAN        -- the session went away
PRIVATE DEFINE m_lostNote STRING
PRIVATE DEFINE m_lastMessage STRING
PRIVATE DEFINE m_lastError STRING
PRIVATE DEFINE m_failures INTEGER

# What state() keeps between calls.
PRIVATE TYPE State RECORD
    ended BOOLEAN,
    lastMessage STRING,
    lastError STRING
END RECORD

#+ Start a shell talking to the session through `send`.
#+
#+ @param send        sends a request line, returns the reply line
#+ @param json        answer with JSON lines instead of text
#+ @param confirmQuit ask for a second quit when recorded steps are unsaved
#+                    (someone is typing: a script cannot answer)
PUBLIC FUNCTION init(send SendFn, json BOOLEAN, confirmQuit BOOLEAN)
    LET m_send = send
    LET m_json = core.isTrue(json)
    LET m_confirmQuit = core.isTrue(confirmQuit)
    LET m_quitArmed = FALSE
    LET m_ended = FALSE
    LET m_lost = FALSE
    LET m_lostNote = NULL
    LET m_lastMessage = NULL
    LET m_lastError = NULL
    LET m_failures = 0
END FUNCTION

#+ What to say when the session goes away unexpectedly, such as where its log is.
PUBLIC FUNCTION setLostNote(note STRING)
    LET m_lostNote = note
END FUNCTION

#+ Greet the session: check that it is this shell's version, and start the
#+ recording for its application.
#+
#+ @return the answer to show, and TRUE when the session is ready
PUBLIC FUNCTION hello() RETURNS (STRING, BOOLEAN)
    DEFINE r protocol.Reply
    DEFINE lost BOOLEAN

    CALL request(protocol.request("hello")) RETURNING r, lost
    IF lost THEN
        RETURN emit("hello", r, lostText()), FALSE
    END IF
    IF NOT core.isTrue(r.ok) THEN
        RETURN emit("hello", r, "ERROR: " || r.error), FALSE
    END IF
    IF r.version IS NULL OR r.version != protocol.VERSION THEN
        LET r.ok = FALSE
        LET r.error = SFMT("the session is fgltest-shell %1 and this shell %2: reinstall the package",
            NVL(r.version, "(unknown)"), protocol.VERSION)
        RETURN emit("hello", r, "ERROR: " || r.error), FALSE
    END IF
    CALL recording.start(r.application)
    RETURN emit("hello", r, SFMT("fgltest-shell %1, driving %2. Type help for the commands.",
        protocol.VERSION, r.application)), TRUE
END FUNCTION

#+ Carry out one line.
#+
#+ @return the answer to show (NULL for a blank line or a comment), and TRUE
#+         when the shell should end
PUBLIC FUNCTION execute(line STRING) RETURNS (STRING, BOOLEAN)
    DEFINE c commands.ShellCommand
    DEFINE req protocol.Request
    DEFINE err, dropped, text STRING
    DEFINE done BOOLEAN

    LET c = commands.parse(line)
    IF c.kind != "quit" THEN
        LET m_quitArmed = FALSE
    END IF
    CASE c.kind
        WHEN "none"
            RETURN NULL, FALSE
        WHEN "error"
            RETURN local(c.name, FALSE, c.error), FALSE
        WHEN "help"
            RETURN local("help", TRUE, commands.help(c.arg)), FALSE
        WHEN "query"
            LET req = protocol.request(c.name)
            IF c.name == "value" THEN
                LET req.target = c.arg
            END IF
            RETURN ask(c.name, req, (c.name == "actions" AND c.arg == "all")), FALSE
        WHEN "step"
            RETURN step(c), FALSE
        WHEN "test"
            LET err = recording.startTest(c.arg)
            IF err IS NOT NULL THEN
                RETURN local("test", FALSE, err), FALSE
            END IF
            RETURN local("test", TRUE, SFMT("recording test '%1'", c.arg)), FALSE
        WHEN "steps"
            RETURN local("steps", TRUE, listSteps()), FALSE
        WHEN "undo"
            LET dropped = recording.undo()
            IF dropped IS NULL THEN
                RETURN local("undo", FALSE, "no recorded step to drop in this test"), FALSE
            END IF
            RETURN local("undo", TRUE, SFMT("dropped: %1 (the application is not changed back)", dropped)), FALSE
        WHEN "save"
            LET err = recording.save(c.arg)
            IF err IS NOT NULL THEN
                RETURN local("save", FALSE, err), FALSE
            END IF
            RETURN local("save", TRUE, SFMT("saved %1 to %2", counted(), c.arg)), FALSE
        WHEN "run"
            RETURN runFile(c.arg), FALSE
        WHEN "quit"
            CALL quit() RETURNING text, done
            RETURN text, done
    END CASE
    RETURN local(c.name, FALSE, SFMT("cannot carry out '%1'", line)), FALSE
END FUNCTION

#+ Tell the session the shell is leaving (when it is still there).
PUBLIC FUNCTION bye()
    DEFINE r protocol.Reply
    DEFINE lost BOOLEAN
    IF NOT m_lost AND NOT m_ended THEN
        CALL request(protocol.request("bye")) RETURNING r, lost
    END IF
END FUNCTION

#+ What the shell knows about the application beyond the recording (whether it
#+ has ended, the MESSAGE and ERROR lines last shown), for restore().
PUBLIC FUNCTION state() RETURNS STRING
    DEFINE st State
    LET st.ended = core.isTrue(m_ended)
    LET st.lastMessage = m_lastMessage
    LET st.lastError = m_lastError
    RETURN util.JSON.stringify(st)
END FUNCTION

#+ Carry on from what state() wrote, in a shell that init() has just started
#+ (in place of hello(): the session greeted the shell that started it).
PUBLIC FUNCTION restore(text STRING)
    DEFINE st State
    TRY
        CALL util.JSON.parse(text, st)
    CATCH
        RETURN
    END TRY
    LET m_ended = core.isTrue(st.ended)
    LET m_lastMessage = st.lastMessage
    LET m_lastError = st.lastError
END FUNCTION

#+ Commands that failed so far: a step or a check that did not hold, a request
#+ the session could not carry out, a line that is not a command.
PUBLIC FUNCTION failures() RETURNS INTEGER
    RETURN m_failures
END FUNCTION

#+ TRUE once the application can no longer be driven.
PUBLIC FUNCTION ended() RETURNS BOOLEAN
    RETURN m_ended
END FUNCTION

# ------------------------------------------------------------ commands ----

# A request to the session, answered with what the session found.
PRIVATE FUNCTION ask(command STRING, req protocol.Request, actionsAll BOOLEAN) RETURNS STRING
    DEFINE r protocol.Reply
    DEFINE text STRING
    IF m_ended THEN
        RETURN local(command, FALSE, endedText())
    END IF
    CALL exchange(req, actionsAll) RETURNING r, text
    RETURN emit(command, r, text)
END FUNCTION

# A test step: carried out by the session, and recorded when it succeeds.
PRIVATE FUNCTION step(c commands.ShellCommand) RETURNS STRING
    DEFINE req protocol.Request
    DEFINE r protocol.Reply
    DEFINE text STRING
    IF m_ended THEN
        RETURN local(c.name, FALSE, endedText())
    END IF
    LET req = protocol.request("step")
    LET req.step.* = c.step.*
    CALL exchange(req, FALSE) RETURNING r, text
    IF core.isTrue(r.ok) THEN
        CALL recording.add(c.step)
    ELSE
        LET text = text.append("\n(not recorded)")
    END IF
    RETURN emit(c.name, r, text)
END FUNCTION

# Send a request; the reply and the text that shows it. A failed reply counts
# as a failure.
PRIVATE FUNCTION exchange(req protocol.Request, actionsAll BOOLEAN) RETURNS (protocol.Reply, STRING)
    DEFINE r protocol.Reply
    DEFINE lost BOOLEAN
    DEFINE text STRING

    CALL request(req) RETURNING r, lost
    IF NOT core.isTrue(r.ok) THEN
        LET m_failures = m_failures + 1
    END IF
    IF lost THEN
        RETURN r, lostText()
    END IF
    LET text = render.reply(req.op, actionsAll, r, m_lastMessage, m_lastError)
    # A MESSAGE stays on screen until the program replaces it, and GGC may not
    # report it while an ERROR shows: keep the last one seen, so it is not
    # shown again as new when it comes back.
    IF LENGTH(r.message) > 0 THEN
        LET m_lastMessage = r.message
    END IF
    IF LENGTH(r.errorLine) > 0 THEN
        LET m_lastError = r.errorLine
    END IF
    RETURN r, text
END FUNCTION

PRIVATE FUNCTION listSteps() RETURNS STRING
    DEFINE steps script.StepList
    DEFINE b base.StringBuffer
    DEFINE i INTEGER

    IF recording.currentTest() IS NULL THEN
        RETURN "nothing recorded yet: each step that succeeds is recorded"
    END IF
    LET steps = recording.currentSteps()
    LET b = base.StringBuffer.create()
    CALL b.append(SFMT("test '%1'", recording.currentTest()))
    IF steps.getLength() == 0 THEN
        CALL b.append(": no steps yet")
    END IF
    FOR i = 1 TO steps.getLength()
        CALL b.append(SFMT("\n%1  %2", i USING "##&", recording.asLine(steps[i])))
    END FOR
    IF recording.testCount() > 1 OR (recording.testCount() == 1 AND steps.getLength() == 0) THEN
        CALL b.append(SFMT("\n(%1 recorded in all)", counted()))
    END IF
    RETURN b.toString()
END FUNCTION

PRIVATE FUNCTION quit() RETURNS (STRING, BOOLEAN)
    IF m_confirmQuit AND recording.unsaved() AND NOT m_quitArmed THEN
        LET m_quitArmed = TRUE
        RETURN local("quit", TRUE, SFMT("%1 not saved: save <file.actions.json> keeps them, quit again leaves without saving.",
            plural(recording.stepCount(), "recorded step"))), FALSE
    END IF
    IF recording.unsaved() THEN
        RETURN local("quit", TRUE, SFMT("bye (%1 not saved)",
            plural(recording.stepCount(), "recorded step"))), TRUE
    END IF
    RETURN local("quit", TRUE, "bye"), TRUE
END FUNCTION

# ------------------------------------------------------------------ run ----

# Run an action file's tests in this session, as fgltest would: beforeAll,
# then each test (skip and only honoured) between beforeEach and afterEach,
# then afterAll. Its steps are not recorded.
PRIVATE FUNCTION runFile(path STRING) RETURNS STRING
    DEFINE err STRING
    DEFINE b, details base.StringBuffer
    DEFINE i, passed, failed, skipped, notRun INTEGER
    DEFINE hasOnly, ok, hooksOk BOOLEAN
    DEFINE r protocol.Reply

    IF m_ended THEN
        RETURN local("run", FALSE, endedText())
    END IF
    LET err = script.load(path)
    IF err IS NOT NULL THEN
        RETURN local("run", FALSE, err)
    END IF
    LET b = base.StringBuffer.create()
    LET hasOnly = FALSE
    FOR i = 1 TO script.testCount()
        IF core.isTrue(script.testIsOnly(i)) THEN
            LET hasOnly = TRUE
        END IF
    END FOR
    LET passed = 0
    LET failed = 0
    LET skipped = 0
    LET notRun = 0

    LET details = base.StringBuffer.create()
    LET hooksOk = runSteps(script.beforeAllSteps(), "beforeAll", details)
    IF NOT hooksOk THEN
        CALL line(b, "FAIL beforeAll" || details.toString())
    END IF
    FOR i = 1 TO script.testCount()
        IF core.isTrue(script.testIsSkipped(i)) OR (hasOnly AND NOT core.isTrue(script.testIsOnly(i))) THEN
            LET skipped = skipped + 1
            CALL line(b, "SKIP " || script.testName(i))
            CONTINUE FOR
        END IF
        IF NOT hooksOk OR m_ended THEN
            LET notRun = notRun + 1
            CALL line(b, SFMT("NOT RUN %1: %2", script.testName(i),
                IIF(m_ended, "the application has ended", "beforeAll failed")))
            CONTINUE FOR
        END IF
        LET details = base.StringBuffer.create()
        LET ok = runSteps(script.beforeEachSteps(), "beforeEach", details)
        IF ok THEN
            LET ok = runSteps(script.testStepsAt(i), NULL, details)
        END IF
        IF NOT runSteps(script.afterEachSteps(), "afterEach", details) THEN
            LET ok = FALSE
        END IF
        IF ok THEN
            LET passed = passed + 1
            CALL line(b, "PASS " || script.testName(i))
        ELSE
            LET failed = failed + 1
            CALL line(b, "FAIL " || script.testName(i) || details.toString())
        END IF
    END FOR
    IF NOT m_ended THEN
        LET details = base.StringBuffer.create()
        IF NOT runSteps(script.afterAllSteps(), "afterAll", details) THEN
            LET hooksOk = FALSE
            CALL line(b, "FAIL afterAll" || details.toString())
        END IF
    END IF
    CALL line(b, SFMT("%1 passed, %2 failed, %3 skipped%4", passed, failed, skipped,
        IIF(notRun > 0, SFMT(", %1 not run", notRun), "")))

    LET r = protocol.reply()
    LET r.ok = (failed == 0 AND notRun == 0 AND hooksOk)
    LET r.appEnded = m_ended
    IF NOT r.ok THEN
        LET m_failures = m_failures + 1
        LET r.error = SFMT("%1 of %2 tests did not pass", failed + notRun, passed + failed + notRun)
    END IF
    RETURN emit("run", r, b.toString())
END FUNCTION

# Send each step to the session, noting in `details` the ones that fail. As in
# fgltest, a step the driver could not carry out ends the list: the rest would
# only add noise.
PRIVATE FUNCTION runSteps(steps script.StepList, hook STRING, details base.StringBuffer) RETURNS BOOLEAN
    DEFINE req protocol.Request
    DEFINE r protocol.Reply
    DEFINE lost, ok BOOLEAN
    DEFINE k INTEGER
    DEFINE text, where STRING

    LET ok = TRUE
    FOR k = 1 TO steps.getLength()
        IF m_ended THEN
            CALL details.append("\n    the application has ended")
            RETURN FALSE
        END IF
        LET req = protocol.request("step")
        LET req.step.* = steps[k].*
        CALL request(req) RETURNING r, lost
        IF core.isTrue(r.ok) THEN
            CONTINUE FOR
        END IF
        LET ok = FALSE
        IF hook IS NULL THEN
            LET where = SFMT("step %1", k)
        ELSE
            LET where = SFMT("%1 step %2", hook, k)
        END IF
        IF lost THEN
            LET text = lostText()
        ELSE
            LET text = render.reply("step", FALSE, r, m_lastMessage, m_lastError)
        END IF
        CALL details.append(SFMT("\n    %1: %2\n      %3", where, recording.asLine(steps[k]),
            indent(text, "      ")))
        IF r.error IS NOT NULL OR lost THEN
            EXIT FOR
        END IF
    END FOR
    RETURN ok
END FUNCTION

# ------------------------------------------------------------ helpers ----

# Send a request and read its reply. TRUE when the session went away: the
# reply then says so, and nothing more can be sent.
PRIVATE FUNCTION request(req protocol.Request) RETURNS (protocol.Reply, BOOLEAN)
    DEFINE line STRING
    DEFINE r protocol.Reply

    LET line = m_send(protocol.encodeRequest(req))
    IF line IS NULL THEN
        LET m_lost = TRUE
        LET m_ended = TRUE
        LET r = protocol.reply()
        LET r.ok = FALSE
        LET r.appEnded = TRUE
        LET r.error = lostText()
        RETURN r, TRUE
    END IF
    LET r = protocol.decodeReply(line)
    IF core.isTrue(r.appEnded) THEN
        LET m_ended = TRUE
    END IF
    RETURN r, FALSE
END FUNCTION

# An answer the shell gives itself. A failed one counts as a failure.
PRIVATE FUNCTION local(command STRING, ok BOOLEAN, text STRING) RETURNS STRING
    DEFINE r protocol.Reply
    LET r = protocol.reply()
    LET r.ok = ok
    LET r.appEnded = m_ended
    IF NOT ok THEN
        LET r.error = text
        LET m_failures = m_failures + 1
    END IF
    RETURN emit(command, r, text)
END FUNCTION

# The answer as shown: the text, or the reply as JSON with the text in it.
PRIVATE FUNCTION emit(command STRING, r protocol.Reply, text STRING) RETURNS STRING
    IF m_json THEN
        LET r.command = command
        LET r.output = text
        RETURN protocol.encodeReply(r)
    END IF
    RETURN text
END FUNCTION

PRIVATE FUNCTION endedText() RETURNS STRING
    RETURN "the application has ended: save <file.actions.json> keeps the recording, quit leaves"
END FUNCTION

PRIVATE FUNCTION lostText() RETURNS STRING
    IF LENGTH(m_lostNote) > 0 THEN
        RETURN SFMT("the session closed unexpectedly (%1)", m_lostNote)
    END IF
    RETURN "the session closed unexpectedly"
END FUNCTION

PRIVATE FUNCTION counted() RETURNS STRING
    RETURN SFMT("%1, %2", plural(recording.testCount(), "test"), plural(recording.stepCount(), "step"))
END FUNCTION

PRIVATE FUNCTION plural(n INTEGER, noun STRING) RETURNS STRING
    IF n == 1 THEN
        RETURN SFMT("1 %1", noun)
    END IF
    RETURN SFMT("%1 %2s", n, noun)
END FUNCTION

PRIVATE FUNCTION line(b base.StringBuffer, s STRING)
    IF b.getLength() > 0 THEN
        CALL b.append("\n")
    END IF
    CALL b.append(s)
END FUNCTION

# `text` with each line after the first indented by `prefix`.
PRIVATE FUNCTION indent(text STRING, prefix STRING) RETURNS STRING
    DEFINE b base.StringBuffer
    LET b = base.StringBuffer.create()
    CALL b.append(text)
    CALL b.replace("\n", "\n" || prefix, 0)
    RETURN b.toString()
END FUNCTION
