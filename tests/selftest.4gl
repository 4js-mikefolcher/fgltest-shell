# selftest — fgltest-shell's own test suite.
#
#   fglrun tests/selftest        (or: make check)
#
# Runs with NO GGC engine, NO scenario server and NO application. The fake
# driver stands in for GGC, and the shell reaches its session by a function
# call instead of a socket, so the whole shell — words, commands, recording,
# the session's answers, what is shown, `run` — is exercised anywhere a
# compiler is available. Exits non-zero on any failure.

IMPORT os
IMPORT util
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.script
IMPORT FGL com.fourjs.fgltest.shell.words
IMPORT FGL com.fourjs.fgltest.shell.protocol
IMPORT FGL com.fourjs.fgltest.shell.commands
IMPORT FGL com.fourjs.fgltest.shell.recording
IMPORT FGL com.fourjs.fgltest.shell.render
IMPORT FGL com.fourjs.fgltest.shell.session
IMPORT FGL com.fourjs.fgltest.shell.options
IMPORT FGL com.fourjs.fgltest.shell.repl
IMPORT FGL fakedriver

DEFINE m_pass, m_fail INTEGER
DEFINE m_group STRING

# The in-process session: TRUE makes it "go away" (send returns NULL).
DEFINE m_gone BOOLEAN
# What the fake message source reports.
DEFINE m_message, m_errorLine STRING

MAIN
    CALL setup()

    CALL group("environment: a UTF-8 locale is active")
    CALL t_utf8_locale()

    CALL group("words: splitting a line")
    CALL t_words_split()
    CALL group("words: multibyte text survives either length semantics")
    CALL t_words_multibyte()
    CALL group("words: quote() is read back unchanged")
    CALL t_words_quote()

    CALL group("commands: shell commands")
    CALL t_commands_shell()
    CALL group("commands: test steps fill what their command needs")
    CALL t_commands_steps()
    CALL group("commands: mistakes are explained")
    CALL t_commands_errors()
    CALL group("commands: every fgltest command can be typed")
    CALL t_commands_coverage()

    CALL group("protocol: requests and replies round-trip")
    CALL t_protocol()

    CALL group("session: answers each request")
    CALL t_session_queries()
    CALL group("session: steps go through fgltest's dispatcher")
    CALL t_session_steps()
    CALL group("session: an application that ends ends the session")
    CALL t_session_ended()

    CALL group("render: what a person sees")
    CALL t_render()

    CALL group("recording: tests and steps")
    CALL t_recording()
    CALL group("recording: saved files are fgltest action files")
    CALL t_recording_save()

    CALL group("repl: steps are carried out and recorded")
    CALL t_repl_steps()
    CALL group("repl: quit asks again when steps are unsaved")
    CALL t_repl_quit()
    CALL group("repl: --json answers are protocol replies")
    CALL t_repl_json()
    CALL group("repl: an ended application or a lost session")
    CALL t_repl_ended()
    CALL group("repl: run replays an action file in the session")
    CALL t_repl_run()

    CALL group("options: the command line")
    CALL t_options()
    CALL group("options: the application's command and name")
    CALL t_options_application()
    CALL group("options: a detached session")
    CALL t_options_detached()
    CALL group("detached: the shell carries on across calls")
    CALL t_detached_state()

    CALL group("release: the version is the same everywhere")
    CALL t_version()

    CALL summary()
END MAIN

# A window like the ones inspect reads: an editable field, a read-only one, a
# hidden one, a disabled one, and a table.
FUNCTION aui() RETURNS STRING
    RETURN '<Form name="customer">'
        || '<FormField name="formonly.name" colName="name" varType="STRING">'
        || '<Edit/></FormField>'
        || '<FormField name="formonly.code" colName="code" varType="STRING" noEntry="1">'
        || '<Edit/></FormField>'
        || '<FormField name="formonly.secret" colName="secret" hidden="1"><Edit/></FormField>'
        || '<FormField name="formonly.off" colName="off" active="0"><ComboBox/></FormField>'
        || '<Table name="orders">'
        || '<TableColumn name="formonly.item" colName="item" varType="STRING"/>'
        || '</Table>'
        || '</Form>'
END FUNCTION

# ------------------------------------------------------------ framework ----

FUNCTION setup()
    CALL fakedriver.reset()
    CALL core.setDriver(fakedriver.asDriver())
    CALL core.clearDriverError()
    CALL core.clearFatal()
    CALL core.resetResults()
    LET m_gone = FALSE
    LET m_message = NULL
    LET m_errorLine = NULL
    CALL session.setApplication("customers")
    CALL session.setMessageSource(FUNCTION fakeMessages)
END FUNCTION

# A shell on a fresh application: the fake driver with aui() and a few
# actions, a session that answers in-process, and a recording started.
FUNCTION freshShell(json BOOLEAN, confirmQuit BOOLEAN)
    DEFINE text STRING
    DEFINE ok BOOLEAN
    CALL setup()
    CALL fakedriver.setAui(aui())
    CALL fakedriver.setForm("customer", "Customer")
    CALL fakedriver.setWindow("w_customer", "Customers")
    CALL fakedriver.addAction("accept", TRUE)
    CALL fakedriver.addAction("cancel", TRUE)
    CALL fakedriver.addAction("delete", FALSE)
    CALL fakedriver.setTable(3, 1)
    CALL repl.init(FUNCTION inProcess, json, confirmQuit)
    CALL repl.setLostNote("see the log")
    CALL repl.hello() RETURNING text, ok
    IF NOT ok THEN
        CALL check("the in-process session says hello: " || text, FALSE)
    END IF
END FUNCTION

# repl's link to the session, without a socket.
FUNCTION inProcess(request STRING) RETURNS STRING
    DEFINE reply STRING
    DEFINE over BOOLEAN
    IF m_gone THEN
        RETURN NULL
    END IF
    CALL session.handle(request) RETURNING reply, over
    RETURN reply
END FUNCTION

FUNCTION fakeMessages() RETURNS (STRING, STRING)
    RETURN m_message, m_errorLine
END FUNCTION

# One line through the shell; its answer.
FUNCTION shell(line STRING) RETURNS STRING
    DEFINE text STRING
    DEFINE done BOOLEAN
    CALL repl.execute(line) RETURNING text, done
    RETURN text
END FUNCTION

FUNCTION group(name STRING)
    LET m_group = name
    DISPLAY SFMT("# %1", name)
END FUNCTION

FUNCTION check(label STRING, cond BOOLEAN)
    IF cond THEN
        LET m_pass = m_pass + 1
        DISPLAY SFMT("ok %1 - %2", m_pass + m_fail, label)
    ELSE
        LET m_fail = m_fail + 1
        DISPLAY SFMT("not ok %1 - %2 [%3]", m_pass + m_fail, label, m_group)
    END IF
END FUNCTION

FUNCTION checkEq(label STRING, got STRING, want STRING)
    IF eq(got, want) THEN
        CALL check(label, TRUE)
    ELSE
        CALL check(SFMT("%1 (got [%2], want [%3])", label, got, want), FALSE)
    END IF
END FUNCTION

FUNCTION checkInt(label STRING, got INTEGER, want INTEGER)
    IF got == want THEN
        CALL check(label, TRUE)
    ELSE
        CALL check(SFMT("%1 (got %2, want %3)", label, got, want), FALSE)
    END IF
END FUNCTION

FUNCTION checkHas(label STRING, hay STRING, needle STRING)
    IF contains(hay, needle) THEN
        CALL check(label, TRUE)
    ELSE
        CALL check(SFMT("%1 ([%2] not in [%3])", label, needle, hay), FALSE)
    END IF
END FUNCTION

FUNCTION checkHasNot(label STRING, hay STRING, needle STRING)
    IF NOT contains(hay, needle) THEN
        CALL check(label, TRUE)
    ELSE
        CALL check(SFMT("%1 ([%2] in [%3])", label, needle, hay), FALSE)
    END IF
END FUNCTION

# "" compares as NULL in BDL, so equality needs an explicit empty-safe helper.
FUNCTION eq(a STRING, b STRING) RETURNS BOOLEAN
    IF LENGTH(a) == 0 AND LENGTH(b) == 0 THEN
        RETURN TRUE
    END IF
    IF a == b THEN
        RETURN TRUE
    END IF
    RETURN FALSE
END FUNCTION

FUNCTION contains(hay STRING, needle STRING) RETURNS BOOLEAN
    IF hay IS NULL THEN
        RETURN FALSE
    END IF
    IF hay.getIndexOf(needle, 1) > 0 THEN
        RETURN TRUE
    END IF
    RETURN FALSE
END FUNCTION

FUNCTION summary()
    DISPLAY ""
    DISPLAY SFMT("1..%1", m_pass + m_fail)
    DISPLAY SFMT("selftest: %1 passed, %2 failed", m_pass, m_fail)
    IF m_fail > 0 THEN
        EXIT PROGRAM 1
    END IF
    EXIT PROGRAM 0
END FUNCTION

FUNCTION tmpPath(name STRING) RETURNS STRING
    RETURN os.Path.join(base.Application.getProgramDir(), name)
END FUNCTION

FUNCTION writeTmp(path STRING, content STRING)
    DEFINE ch base.Channel
    LET ch = base.Channel.create()
    CALL ch.openFile(path, "w")
    CALL ch.writeLine(content)
    CALL ch.close()
END FUNCTION

FUNCTION readTmp(path STRING) RETURNS STRING
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

# ---------------------------------------------------------- environment ----

FUNCTION t_utf8_locale()
    DEFINE e STRING
    LET e = "é"
    CALL check(SFMT("a UTF-8 locale is active (LANG=%1); set LANG to one, e.g. C.UTF-8",
        fgl_getenv("LANG")), e.getCharAt(1) == e)
END FUNCTION

# ---------------------------------------------------------------- words ----

FUNCTION t_words_split()
    DEFINE w inspect.StringList
    DEFINE err STRING

    CALL words.split('fill formonly.customer "Big Co"') RETURNING w, err
    CALL check("a plain line splits", err IS NULL)
    CALL checkInt("... into three words", w.getLength(), 3)
    CALL checkEq("... a double-quoted word keeps its space", w[3], "Big Co")

    CALL words.split("  action\t accept  ") RETURNING w, err
    CALL checkInt("spaces and tabs separate words, at either end too", w.getLength(), 2)
    CALL checkEq("... the second word", w[2], "accept")

    CALL words.split('fill f "say \\"hi\\" \\\\ now"') RETURNING w, err
    CALL checkEq('\\" and \\\\ are escapes in "..."', w[3], 'say "hi" \\ now')

    CALL words.split('fill f "a\\b"') RETURNING w, err
    CALL checkEq("any other backslash is kept", w[3], "a\\b")

    CALL words.split("fill f 'a \"b\" \\n'") RETURNING w, err
    CALL checkEq("'...' is taken literally", w[3], 'a "b" \\n')

    CALL words.split('fill f ""') RETURNING w, err
    CALL checkInt('"" is an empty word', w.getLength(), 3)
    CALL check("... that is empty", LENGTH(w[3]) == 0)

    CALL words.split("") RETURNING w, err
    CALL checkInt("an empty line has no words", w.getLength(), 0)

    CALL words.split('fill f "open') RETURNING w, err
    CALL checkHas('an unterminated " is an error', err, "unterminated")
    CALL words.split("fill f 'open") RETURNING w, err
    CALL checkHas("an unterminated ' is an error", err, "unterminated")
END FUNCTION

FUNCTION t_words_multibyte()
    DEFINE w inspect.StringList
    DEFINE err STRING

    CALL words.split("fill formonly.ville Zürich") RETURNING w, err
    CALL checkEq("an unquoted multibyte word is whole", w[3], "Zürich")
    CALL words.split('fill formonly.ville "Saint-Étienne et Besançon" next') RETURNING w, err
    CALL checkEq("a quoted multibyte word is whole", w[3], "Saint-Étienne et Besançon")
    CALL checkEq("... and the word after it too", w[4], "next")
    CALL words.split("fill f 日本語 x") RETURNING w, err
    CALL checkEq("three-byte characters stay whole", w[3], "日本語")
    CALL checkInt("... and the blanks around them are found", w.getLength(), 4)
END FUNCTION

FUNCTION t_words_quote()
    DEFINE samples DYNAMIC ARRAY OF STRING
    DEFINE w inspect.StringList
    DEFINE i INTEGER
    DEFINE err, q STRING

    CALL checkEq("a plain word is not quoted", words.quote("accept"), "accept")
    CALL checkEq("an empty word is two quotes", words.quote(NULL), '""')
    LET samples[1] = "Big Co"
    LET samples[2] = 'say "hi"'
    LET samples[3] = "back\\slash"
    LET samples[4] = "it's"
    LET samples[5] = "tab\tbed"
    LET samples[6] = "Besançon ünd 日本"
    LET samples[7] = '\\"'
    FOR i = 1 TO samples.getLength()
        LET q = words.quote(samples[i])
        CALL words.split("x " || q) RETURNING w, err
        CALL check(SFMT("quote() reads back [%1] as one word", samples[i]),
            err IS NULL AND w.getLength() == 2)
        IF w.getLength() == 2 THEN
            CALL checkEq(SFMT("... unchanged [%1]", samples[i]), w[2], samples[i])
        END IF
    END FOR
END FUNCTION

# ------------------------------------------------------------- commands ----

FUNCTION t_commands_shell()
    DEFINE c commands.ShellCommand

    LET c = commands.parse("")
    CALL checkEq("a blank line is nothing", c.kind, "none")
    LET c = commands.parse("   # a comment")
    CALL checkEq("a comment is nothing", c.kind, "none")
    LET c = commands.parse("FIELDS")
    CALL checkEq("shell commands ignore case", c.kind, "query")
    CALL checkEq("... and are named as written in help", c.name, "fields")
    LET c = commands.parse("actions all")
    CALL checkEq("actions all", c.arg, "all")
    LET c = commands.parse("actions some")
    CALL checkEq("actions takes only 'all'", c.kind, "error")
    LET c = commands.parse("value formonly.name")
    CALL checkEq("value takes a field", c.arg, "formonly.name")
    LET c = commands.parse('test "adds a customer"')
    CALL checkEq("test takes a name", c.kind, "test")
    CALL checkEq("... which may have spaces", c.arg, "adds a customer")
    LET c = commands.parse("save")
    CALL checkEq("save needs a file", c.kind, "error")
    CALL checkHas("... and says how to call it", c.error, "save <file.actions.json>")
    LET c = commands.parse("exit")
    CALL checkEq("exit is quit", c.kind, "quit")
    LET c = commands.parse("?")
    CALL checkEq("? is help", c.kind, "help")
END FUNCTION

FUNCTION t_commands_steps()
    DEFINE c commands.ShellCommand

    LET c = commands.parse('fill formonly.customer "Big Co"')
    CALL checkEq("fill is a step", c.kind, "step")
    CALL checkEq("... target", c.step.target, "formonly.customer")
    CALL checkEq("... value", c.step.value, "Big Co")

    LET c = commands.parse("ASSERTFIELD formonly.n 3")
    CALL checkEq("a step's command ignores case and is spelled as fgltest spells it",
        c.step.command, "assertField")

    LET c = commands.parse("selectRow orders 4")
    CALL checkEq("selectRow: table", c.step.target, "orders")
    CALL checkInt("... row", c.step.rowNum, 4)

    LET c = commands.parse("focusCell orders item 2")
    CALL checkEq("focusCell: table", c.step.target, "orders")
    CALL checkEq("... column", c.step.col, "item")
    CALL checkInt("... row", c.step.rowNum, 2)

    LET c = commands.parse("assertCellAtRow orders item 2 Globe")
    CALL checkEq("assertCellAtRow: column", c.step.col, "item")
    CALL checkInt("... row", c.step.rowNum, 2)
    CALL checkEq("... value", c.step.value, "Globe")

    LET c = commands.parse("enter hello")
    CALL checkEq("enter takes only a value", c.step.value, "hello")
    CALL check("... no target", c.step.target IS NULL)

    LET c = commands.parse("clear")
    CALL checkEq("clear takes nothing", c.kind, "step")

    LET c = commands.parse("pause 250")
    CALL checkEq("pause takes milliseconds", c.step.value, "250")
END FUNCTION

FUNCTION t_commands_errors()
    DEFINE c commands.ShellCommand

    LET c = commands.parse("frobnicate x")
    CALL checkEq("an unknown command is an error", c.kind, "error")
    CALL checkHas("... that points to help", c.error, "help")
    LET c = commands.parse("fill formonly.customer")
    CALL checkHas("too few words: the usage", c.error, "fill <field> <value>")
    LET c = commands.parse("action accept now")
    CALL checkHas("too many words: the usage", c.error, "action <action>")
    LET c = commands.parse("selectRow orders zero")
    CALL checkHas("a row must be a number", c.error, "whole number of 1 or more")
    LET c = commands.parse("selectRow orders 0")
    CALL checkHas("... of 1 or more", c.error, "whole number of 1 or more")
    LET c = commands.parse("pause soon")
    CALL checkHas("pause needs a number", c.error, "whole number")
    LET c = commands.parse('fill f "open')
    CALL checkHas("an unterminated quote is reported", c.error, "unterminated")
    CALL checkHas("help names a step's arguments", commands.help("assertCellAtRow"),
        "assertCellAtRow <table> <column> <row> <value>")
    CALL checkHas("help for an unknown command says so", commands.help("nope"), "unknown command")
END FUNCTION

# Every command fgltest's action files know can be typed, with as many words
# as it needs, and help describes it: a command added to fgltest that the
# shell does not describe is caught here.
FUNCTION t_commands_coverage()
    DEFINE cmds inspect.StringList
    DEFINE c commands.ShellCommand
    DEFINE i, k INTEGER
    DEFINE req, line, h, all STRING

    LET cmds = script.commands()
    LET all = commands.help(NULL)
    FOR i = 1 TO cmds.getLength()
        LET req = script.requirements(cmds[i])
        LET line = cmds[i]
        FOR k = 1 TO req.getLength()
            CASE req.subString(k, k)
                WHEN "t" LET line = line || " t"
                WHEN "c" LET line = line || " c"
                WHEN "r" LET line = line || " 1"
                WHEN "v" LET line = line || " 1"
            END CASE
        END FOR
        LET c = commands.parse(line)
        CALL checkEq(SFMT("'%1' parses as a step", line), c.kind, "step")
        LET h = commands.help(cmds[i])
        CALL check(SFMT("help describes %1", cmds[i]), h.getIndexOf("\n  ", 1) > 0
            AND h.getLength() > h.getIndexOf("\n  ", 1) + 3)
        CALL checkHas(SFMT("the command list has %1", cmds[i]), all, "  " || cmds[i])
    END FOR
END FUNCTION

# ------------------------------------------------------------- protocol ----

FUNCTION t_protocol()
    DEFINE req, back protocol.Request
    DEFINE r protocol.Reply
    DEFINE err, text STRING

    LET req = protocol.request("step")
    LET req.step.command = "focusCell"
    LET req.step.target = "orders"
    LET req.step.col = "item"
    LET req.step.rowNum = 2
    LET text = protocol.encodeRequest(req)
    CALL checkHas("a step's column is named as in action files", text, '"column":"item"')
    CALL checkHas("... and its row", text, '"row":2')
    CALL protocol.decodeRequest(text) RETURNING back, err
    CALL check("a request reads back", err IS NULL)
    CALL checkEq("... op", back.op, "step")
    CALL checkEq("... column", back.step.col, "item")
    CALL checkInt("... row", back.step.rowNum, 2)

    CALL protocol.decodeRequest("not json") RETURNING back, err
    CALL checkHas("a line that is not JSON is not a request", err, "not a request")
    CALL protocol.decodeRequest('{"target":"x"}') RETURNING back, err
    CALL checkHas("nor is one without an op", err, "not a request")

    LET r = protocol.decodeReply("garbage")
    CALL check("an unreadable reply is a failure", NOT core.isTrue(r.ok))
    CALL checkHas("... that says so", r.error, "unreadable reply")
    LET r = protocol.decodeReply('{"error":"x"}')
    CALL check("a reply without ok reads as a failure, not NULL", r.ok IS NOT NULL AND NOT r.ok)
    CALL check("... and appEnded as FALSE, not NULL", r.appEnded IS NOT NULL AND NOT r.appEnded)
END FUNCTION

# --------------------------------------------------------------- session ----

# Ask the in-process session; its decoded reply.
FUNCTION ask(json STRING) RETURNS protocol.Reply
    DEFINE reply STRING
    DEFINE over BOOLEAN
    CALL session.handle(json) RETURNING reply, over
    RETURN protocol.decodeReply(reply)
END FUNCTION

FUNCTION t_session_queries()
    DEFINE r protocol.Reply
    DEFINE reply STRING
    DEFINE over BOOLEAN

    CALL setup()
    CALL fakedriver.setAui(aui())
    CALL fakedriver.setForm("customer", "Customer")
    CALL fakedriver.setWindow("w_customer", "Customers")
    CALL fakedriver.addAction("accept", TRUE)
    CALL fakedriver.setTable(3, 2)
    CALL fakedriver.setFieldValue("formonly.name", "Ada")
    CALL fakedriver.setCurrentValue("now")

    LET r = ask('{"op":"hello"}')
    CALL checkEq("hello gives the version", r.version, protocol.VERSION)
    CALL checkEq("... and the application", r.application, "customers")

    LET r = ask('{"op":"fields"}')
    CALL checkInt("fields lists the window's fields", r.fields.getLength(), 5)
    LET r = ask('{"op":"actions"}')
    CALL checkEq("actions lists the actions", r.actions[1].name, "accept")
    LET r = ask('{"op":"window"}')
    CALL checkEq("window: its name", r.window.windowName, "w_customer")
    CALL checkEq("... the form's title", r.window.formTitle, "Customer")
    LET r = ask('{"op":"tables"}')
    CALL checkEq("tables: the name", r.tables[1].name, "orders")
    CALL checkInt("... rows", r.tables[1].rows, 3)
    CALL checkInt("... current row", r.tables[1].currentRow, 2)
    LET r = ask('{"op":"value","target":"formonly.name"}')
    CALL checkEq("value of a field", r.value, "Ada")
    LET r = ask('{"op":"value"}')
    CALL checkEq("value of the current field", r.value, "now")

    LET m_message = "Saved."
    LET r = ask('{"op":"window"}')
    CALL checkEq("the application's MESSAGE line comes with each reply", r.message, "Saved.")
    LET m_message = NULL

    LET r = ask('{"op":"dance"}')
    CALL checkHas("an unknown request is refused", r.error, "unknown request")
    LET r = ask("{")
    CALL check("so is a line that is not JSON", NOT r.ok)

    CALL session.handle('{"op":"bye"}') RETURNING reply, over
    CALL check("bye ends the session", over)
END FUNCTION

FUNCTION t_session_steps()
    DEFINE r protocol.Reply

    CALL setup()
    CALL fakedriver.setAui(aui())
    LET r = ask('{"op":"step","step":{"command":"fill","target":"formonly.name","value":"Ada"}}')
    CALL check("a step that works is ok", r.ok)
    CALL checkEq("... and reached the driver", fakedriver.logAt(fakedriver.logCount()), "setField(formonly.name,Ada)")

    LET r = ask('{"op":"step","step":{"command":"assertField","target":"formonly.name","value":"Ada"}}')
    CALL check("an assertion that holds is ok", r.ok)
    CALL checkInt("... with its check", r.checks.getLength(), 1)

    LET r = ask('{"op":"step","step":{"command":"assertField","target":"formonly.name","value":"Bob"}}')
    CALL check("an assertion that fails is not ok", NOT r.ok)
    CALL checkHas("... and says why", r.checks[1].detail, "Bob")

    CALL fakedriver.failOn("formonly.nosuch")
    LET r = ask('{"op":"step","step":{"command":"fill","target":"formonly.nosuch","value":"x"}}')
    CALL check("a step the driver cannot carry out is not ok", NOT r.ok)
    CALL checkHas("... and gives the driver's error", r.error, "formonly.nosuch")
    LET r = ask('{"op":"step","step":{"command":"fill","target":"formonly.name","value":"x"}}')
    CALL check("... which does not stick to the next request", r.ok)

    LET r = ask('{"op":"step","step":{"command":"twirl"}}')
    CALL checkHas("an unknown step command is refused", r.error, "unknown command")
END FUNCTION

FUNCTION t_session_ended()
    DEFINE r protocol.Reply
    DEFINE reply STRING
    DEFINE over BOOLEAN

    CALL setup()
    CALL fakedriver.setAui(aui())
    CALL fakedriver.endOn("quit")
    CALL session.handle('{"op":"step","step":{"command":"action","target":"quit"}}') RETURNING reply, over
    LET r = protocol.decodeReply(reply)
    CALL check("an action that ends the application: appEnded", r.appEnded)
    CALL check("... the step itself is ok", r.ok)
    CALL check("... the session is over", over)

    CALL setup()
    CALL fakedriver.setAui('<UserInterface><Window name="w"><Form name="f"/>'
        || '<Menu style="winmsg" text="ERROR" comment="Program stopped at '
        || "'app.4gl'" || ', line number 12.&#10;FORMS statement error number -8083.&#10;"/>'
        || '</Window></UserInterface>')
    CALL session.handle('{"op":"fields"}') RETURNING reply, over
    LET r = protocol.decodeReply(reply)
    CALL check("a runtime error box: the application ended", r.appEnded)
    CALL checkHas("... with the error", r.appError, "-8083")
    CALL check("... and the session is over", over)
    CALL setup()
END FUNCTION

# ---------------------------------------------------------------- render ----

FUNCTION t_render()
    DEFINE r protocol.Reply
    DEFINE text STRING

    LET r = protocol.reply()
    LET r.fields[1].name = "formonly.name"
    LET r.fields[1].widget = "Edit"
    LET r.fields[1].active = TRUE
    LET r.fields[1].hidden = FALSE
    LET r.fields[1].readOnly = FALSE
    LET r.fields[2].name = "formonly.code"
    LET r.fields[2].widget = "Edit"
    LET r.fields[2].active = TRUE
    LET r.fields[2].readOnly = TRUE
    LET r.fields[3].name = "formonly.secret"
    LET r.fields[3].hidden = TRUE
    LET r.fields[4].name = "formonly.off"
    LET r.fields[4].active = FALSE
    LET text = render.reply("fields", FALSE, r, NULL, NULL)
    CALL checkHas("an editable field", text, "formonly.name    editable  Edit")
    CALL checkHas("a read-only one", text, "read-only")
    CALL checkHas("a hidden one", text, "formonly.secret  hidden")
    CALL checkHas("a disabled one", text, "formonly.off     disabled")

    LET r = protocol.reply()
    LET r.actions[1].name = "accept"
    LET r.actions[1].active = TRUE
    LET r.actions[2].name = "delete"
    LET r.actions[2].active = FALSE
    LET r.actions[3].name = "cancel"
    LET r.actions[3].active = TRUE
    CALL checkEq("actions: the active ones on a line", render.reply("actions", FALSE, r, NULL, NULL), "accept  cancel")
    CALL checkHas("actions all: the inactive ones too", render.reply("actions", TRUE, r, NULL, NULL), "delete  (inactive)")

    LET r = protocol.reply()
    CALL checkEq("a step with no checks: ok", render.reply("step", FALSE, r, NULL, NULL), "ok")
    LET r.checks[1].passed = TRUE
    LET r.checks[1].message = "value equals [x]"
    CALL checkEq("a check that held", render.reply("step", FALSE, r, NULL, NULL), "ok: value equals [x]")
    LET r.checks[1].passed = FALSE
    LET r.checks[1].detail = "expected [y] to equal [x]"
    CALL checkEq("a check that did not", render.reply("step", FALSE, r, NULL, NULL), "FAIL: expected [y] to equal [x]")
    LET r = protocol.reply()
    LET r.ok = FALSE
    LET r.error = "(GGC-7) not found"
    CALL checkEq("a driver error", render.reply("step", FALSE, r, NULL, NULL), "ERROR: (GGC-7) not found")

    LET r = protocol.reply()
    LET r.message = "Saved."
    CALL checkHas("a new MESSAGE line is shown", render.reply("step", FALSE, r, NULL, NULL), "application message: Saved.")
    CALL checkHasNot("... but not again", render.reply("step", FALSE, r, "Saved.", NULL), "Saved.")
    LET r.message = NULL
    LET r.errorLine = "Bad date"
    CALL checkHas("a new ERROR line is shown", render.reply("step", FALSE, r, NULL, NULL), "application error line: Bad date")

    LET r = protocol.reply()
    LET r.value = "x y"
    CALL checkEq("a value is bracketed", render.reply("value", FALSE, r, NULL, NULL), "[x y]")

    LET r = protocol.reply()
    LET r.ok = FALSE
    LET r.appEnded = TRUE
    LET r.error = "(GGC-12) The scenario has already ended."
    LET text = render.reply("fields", FALSE, r, NULL, NULL)
    CALL checkEq("once the application has ended, a query says only that", text, "the application has ended")
    LET r.appError = "Program stopped at 'a.4gl', line number 3."
    CALL checkHas("... or the runtime error it stopped with", render.reply("step", FALSE, r, NULL, NULL),
        "stopped with a runtime error: Program stopped")
END FUNCTION

# ------------------------------------------------------------- recording ----

FUNCTION aStep(command STRING, target STRING, value STRING) RETURNS script.Step
    DEFINE s script.Step
    INITIALIZE s.* TO NULL
    LET s.command = command
    LET s.target = target
    LET s.value = value
    RETURN s
END FUNCTION

FUNCTION t_recording()
    DEFINE err STRING
    DEFINE steps script.StepList

    CALL recording.start("customers")
    CALL check("nothing recorded: nothing unsaved", NOT recording.unsaved())
    CALL check("... and no current test", recording.currentTest() IS NULL)
    CALL recording.add(aStep("action", "accept", NULL))
    CALL checkEq("a step with no test starts 'test 1'", recording.currentTest(), "test 1")
    CALL check("... and is unsaved", recording.unsaved())

    LET err = recording.startTest("second")
    CALL check("a new test", err IS NULL)
    LET err = recording.startTest("renamed")
    CALL checkEq("an empty current test is renamed instead", recording.currentTest(), "renamed")
    CALL checkInt("... so one test has steps", recording.testCount(), 1)
    LET err = recording.startTest("test 1")
    CALL checkHas("test names are unique", err, "already recorded")

    CALL recording.add(aStep("fill", "formonly.name", "Big Co"))
    CALL recording.add(aStep("action", "accept", NULL))
    CALL checkEq("undo drops the last step", recording.undo(), "action accept")
    CALL checkEq("... the one before next", recording.undo(), 'fill formonly.name "Big Co"')
    CALL check("... then there is none left in this test", recording.undo() IS NULL)
    LET steps = recording.currentSteps()
    CALL checkInt("the current test is empty again", steps.getLength(), 0)
    CALL checkInt("the earlier test keeps its step", recording.stepCount(), 1)
END FUNCTION

FUNCTION t_recording_save()
    DEFINE s script.Step
    DEFINE path, err, json STRING
    DEFINE steps script.StepList
    DEFINE c commands.ShellCommand

    LET path = tmpPath("recorded.actions.json")
    CALL recording.start("customers")
    LET err = recording.save(path)
    CALL checkHas("nothing to save yet", err, "nothing recorded")

    LET err = recording.startTest("adds a customer")
    CALL recording.add(aStep("fill", "formonly.name", "Zoë \"Z\" Ünal"))
    CALL recording.add(aStep("fill", "formonly.note", NULL))
    CALL recording.add(aStep("action", "accept", NULL))
    INITIALIZE s.* TO NULL
    LET s.command = "assertCellAtRow"
    LET s.target = "orders"
    LET s.col = "item"
    LET s.rowNum = 2
    LET s.value = "Globe"
    CALL recording.add(s)

    LET json = recording.toJson()
    CALL checkHasNot("a step writes only what its command uses", json, '"row": 0')
    CALL checkHas("... a row where it is used", json, '"row": 2')
    CALL checkHas("an empty value is written as an empty string", json, '"value": ""')
    CALL checkHasNot("... never as null", json, "null")

    LET err = recording.save(path)
    CALL check("the recording saves: " || NVL(err, "ok"), err IS NULL)
    CALL check("... and is no longer unsaved", NOT recording.unsaved())
    LET err = script.load(path)
    CALL check("fgltest loads the saved file", err IS NULL)
    CALL checkEq("... the application", script.appName(), "customers")
    CALL checkEq("... the test", script.testName(1), "adds a customer")
    LET steps = script.testStepsAt(1)
    CALL checkInt("... its steps", steps.getLength(), 4)
    CALL checkEq("... multibyte text and quotes intact", steps[1].value, "Zoë \"Z\" Ünal")
    CALL checkInt("... the row", steps[4].rowNum, 2)

    # A step shown as a line reads back as the same step.
    LET c = commands.parse(recording.asLine(steps[1]))
    CALL checkEq("asLine() parses back to the same value", c.step.value, steps[1].value)
    LET c = commands.parse(recording.asLine(steps[4]))
    CALL checkEq("... column", c.step.col, "item")
    CALL checkInt("... row", c.step.rowNum, 2)
    CALL os.Path.delete(path) RETURNING err
END FUNCTION

# ------------------------------------------------------------------ repl ----

FUNCTION t_repl_steps()
    DEFINE text STRING

    CALL freshShell(FALSE, TRUE)
    LET text = shell("fields")
    CALL checkHas("fields", text, "formonly.name")
    LET text = shell("actions")
    CALL checkEq("actions: the active ones", text, "accept  cancel")
    LET text = shell("window")
    CALL checkHas("window", text, "w_customer")
    LET text = shell("tables")
    CALL checkHas("tables", text, "orders: 3 rows, current row 1")

    LET text = shell('test "adds a customer"')
    CALL checkEq("test starts a test", text, "recording test 'adds a customer'")
    LET text = shell('fill formonly.name "Big Co"')
    CALL checkEq("a step that works: ok", text, "ok")
    LET text = shell("assertField formonly.name 'Big Co'")
    CALL checkHas("an assertion that holds", text, "ok: value equals [Big Co]")
    LET text = shell("assertField formonly.name Small")
    CALL checkHas("one that does not", text, "FAIL: ")
    CALL checkHas("... is not recorded", text, "(not recorded)")
    CALL fakedriver.failOn("formonly.nosuch")
    LET text = shell("fill formonly.nosuch x")
    CALL checkHas("a step the driver cannot do", text, "ERROR: ")
    LET text = shell("bogus")
    CALL checkHas("a line that is not a command", text, "unknown command")
    CALL checkInt("failures are counted", repl.failures(), 3)

    LET text = shell("steps")
    CALL checkHas("steps lists the test", text, "test 'adds a customer'")
    CALL checkHas("... and the steps that worked", text, '1  fill formonly.name "Big Co"')
    CALL checkHas("...", text, "2  assertField formonly.name \"Big Co\"")
    CALL checkHasNot("... only those", text, "Small")
    LET text = shell("undo")
    CALL checkHas("undo says what it dropped", text, "dropped: assertField")
    CALL checkInt("one step is left", recording.stepCount(), 1)
    LET text = shell("help fill")
    CALL checkHas("help for a command", text, "fill <field> <value>")

    LET m_message = "Added Ada."
    LET text = shell("action accept")
    CALL checkHas("the application's MESSAGE is shown", text, "application message: Added Ada.")
    LET m_message = NULL
    LET m_errorLine = "A contact needs a name."
    LET text = shell("action accept")
    CALL checkHas("then its ERROR", text, "application error line: A contact needs a name.")
    LET m_message = "Added Ada."
    LET m_errorLine = NULL
    LET text = shell("action cancel")
    CALL checkHasNot("a MESSAGE still on screen after an ERROR is not shown again", text, "Added Ada.")
    LET m_message = "Added Bob."
    LET text = shell("action accept")
    CALL checkHas("a new one is", text, "application message: Added Bob.")
    LET m_message = NULL
END FUNCTION

FUNCTION t_repl_quit()
    DEFINE text, path STRING
    DEFINE done BOOLEAN
    DEFINE err STRING

    CALL freshShell(FALSE, TRUE)
    CALL repl.execute("quit") RETURNING text, done
    CALL check("nothing recorded: quit quits", done)

    CALL freshShell(FALSE, TRUE)
    LET text = shell("action accept")
    CALL repl.execute("quit") RETURNING text, done
    CALL check("unsaved steps: quit asks again", NOT done)
    CALL checkHas("... saying why", text, "1 recorded step not saved")
    LET text = shell("fields")
    CALL repl.execute("quit") RETURNING text, done
    CALL check("... and asks again after another command", NOT done)
    CALL repl.execute("quit") RETURNING text, done
    CALL check("a second quit in a row quits", done)
    CALL checkInt("asking again is not a failure", repl.failures(), 0)

    CALL freshShell(FALSE, TRUE)
    LET path = tmpPath("quit.actions.json")
    LET text = shell("action accept")
    LET text = shell("save " || path)
    CALL checkHas("save says what it saved", text, "saved 1 test, 1 step to")
    CALL repl.execute("quit") RETURNING text, done
    CALL check("saved: quit quits", done)
    CALL os.Path.delete(path) RETURNING err

    CALL freshShell(FALSE, FALSE)
    LET text = shell("action accept")
    CALL repl.execute("quit") RETURNING text, done
    CALL check("a script is not asked again", done)
END FUNCTION

FUNCTION t_repl_json()
    DEFINE text STRING
    DEFINE r protocol.Reply
    DEFINE o util.JSONObject

    CALL freshShell(TRUE, FALSE)
    LET text = shell("fields")
    LET r = protocol.decodeReply(text)
    CALL check("a query answers with one JSON reply", r.ok)
    CALL checkEq("... naming the command", r.command, "fields")
    CALL checkInt("... with the fields", r.fields.getLength(), 5)
    CALL checkHas("... and the text a person would see", r.output, "formonly.name")
    CALL check("... on one line", NOT contains(text, "\n"))

    LET text = shell("assertField formonly.name nobody")
    LET r = protocol.decodeReply(text)
    CALL check("a failing step: ok is false", NOT r.ok)
    CALL checkEq("... the command as fgltest spells it", r.command, "assertField")
    CALL check("... the check that failed", NOT r.checks[1].passed)

    LET text = shell("steps")
    LET o = util.JSONObject.parse(text)
    CALL check("a shell command answers in JSON too", o.get("ok"))
    CALL checkHas("... its text in output", o.get("output"), "nothing recorded")

    LET text = shell("nonsense")
    LET r = protocol.decodeReply(text)
    CALL check("so does a mistake", NOT r.ok)
    CALL checkHas("... with the error", r.error, "unknown command")
    LET text = shell("")
    CALL check("a blank line answers nothing", text IS NULL)
END FUNCTION

FUNCTION t_repl_ended()
    DEFINE text STRING

    CALL freshShell(FALSE, TRUE)
    CALL fakedriver.endOn("exit")
    LET text = shell("action exit")
    CALL checkHas("an action that ends the application says so", text, "the application has ended")
    CALL check("... the shell knows", repl.ended())
    CALL checkInt("... the step itself worked and is recorded", recording.stepCount(), 1)
    LET text = shell("fields")
    CALL checkHas("then a request is refused", text, "the application has ended")
    CALL checkHas("... pointing to save", text, "save <file.actions.json>")
    LET text = shell("steps")
    CALL checkHas("the recording is still there", text, "action exit")

    CALL freshShell(FALSE, TRUE)
    LET m_gone = TRUE
    LET text = shell("fields")
    CALL checkHas("a session that disappears is reported", text, "the session closed unexpectedly")
    CALL checkHas("... with where to look", text, "see the log")
    CALL check("... and nothing more is sent", repl.ended())
    LET text = shell("action accept")
    CALL checkHas("a step after that is refused", text, "the application has ended")
    CALL checkInt("nothing is recorded", recording.stepCount(), 0)
    LET m_gone = FALSE
END FUNCTION

FUNCTION t_repl_run()
    DEFINE path, text STRING

    LET path = tmpPath("run.actions.json")
    CALL writeTmp(path, '{"application":"customers",'
        || '"beforeEach":[{"command":"pause","value":"1"}],'
        || '"tests":['
        || '{"name":"fills","steps":[{"command":"fill","target":"formonly.name","value":"Ada"},'
        ||     '{"command":"assertField","target":"formonly.name","value":"Ada"}]},'
        || '{"name":"wrong","steps":[{"command":"assertField","target":"formonly.name","value":"Bob"},'
        ||     '{"command":"assertFormName","value":"customer"}]},'
        || '{"name":"skipped","skip":true,"steps":[{"command":"action","target":"accept"}]},'
        || '{"name":"broken","steps":[{"command":"fill","target":"formonly.nosuch","value":"x"},'
        ||     '{"command":"action","target":"accept"}]}'
        || ']}')
    CALL freshShell(FALSE, TRUE)
    CALL fakedriver.failOn("formonly.nosuch")
    LET text = shell("run " || path)
    CALL checkHas("a passing test", text, "PASS fills")
    CALL checkHas("a failing one", text, "FAIL wrong")
    CALL checkHas("... with the step", text, "step 1: assertField formonly.name Bob")
    CALL checkHas("... and why", text, "FAIL: expected [Ada] to equal [Bob]")
    CALL checkHasNot("... checks that held are not listed", text, "step 2: assertFormName")
    CALL checkHas("a skipped one", text, "SKIP skipped")
    CALL checkHas("a step the driver cannot do fails its test", text, "FAIL broken")
    CALL checkHasNot("... and ends it", text, "step 2: action accept")
    CALL checkHas("the summary", text, "1 passed, 2 failed, 1 skipped")
    CALL checkInt("run's steps are not recorded", recording.stepCount(), 0)
    CALL checkInt("a run with failures is one failure", repl.failures(), 1)
    CALL checkEq("beforeEach ran before each test that ran", fakedriver.logAt(1), "pause(1)")

    CALL writeTmp(path, '{"application":"customers","tests":['
        || '{"name":"one","steps":[{"command":"action","target":"accept"}]},'
        || '{"name":"two","only":true,"steps":[{"command":"action","target":"cancel"}]}]}')
    CALL freshShell(FALSE, TRUE)
    LET text = shell("run " || path)
    CALL checkHas("only: the others are skipped", text, "SKIP one")
    CALL checkHas("... and it runs", text, "PASS two")

    CALL writeTmp(path, '{"application":"customers","tests":[{"name":"x"}]}')
    LET text = shell("run " || path)
    CALL checkHas("a file fgltest would not accept is refused", text, "is not valid")
    LET text = shell("run " || tmpPath("missing.actions.json"))
    CALL checkHas("so is a file that is not there", text, "cannot read")
    CALL os.Path.delete(path) RETURNING text
END FUNCTION

# --------------------------------------------------------------- options ----

FUNCTION argv(line STRING) RETURNS inspect.StringList
    DEFINE w inspect.StringList
    DEFINE err STRING
    CALL words.split(line) RETURNING w, err
    RETURN w
END FUNCTION

FUNCTION t_options()
    DEFINE o options.Options
    DEFINE err STRING

    CALL options.parse(argv("--workdir /app --json orders -x 3")) RETURNING o, err
    CALL check("a program with options", err IS NULL)
    CALL checkEq("... the program", o.program, "orders")
    CALL checkInt("... the program's own arguments, options or not", o.arguments.getLength(), 2)
    CALL checkEq("...", o.arguments[1], "-x")
    CALL check("... --json", o.json)
    CALL checkEq("... --workdir", o.workdir, "/app")

    CALL options.parse(argv("-- -odd")) RETURNING o, err
    CALL checkEq("-- marks the program", o.program, "-odd")

    CALL options.parse(argv("--script t.shell --save t.actions.json --port 6600 --timeout 5 app")) RETURNING o, err
    CALL check("values", err IS NULL)
    CALL checkEq("... --script", o.script, "t.shell")
    CALL checkEq("... --save", o.save, "t.actions.json")
    CALL checkInt("... --port", o.port, 6600)
    CALL checkInt("... --timeout", o.timeout, 5)

    CALL options.parse(argv("--help")) RETURNING o, err
    CALL check("--help needs no application", o.help AND err IS NULL)
    CALL options.parse(argv("-V")) RETURNING o, err
    CALL check("-V is --version", o.version AND err IS NULL)

    CALL options.parse(argv("--frob app")) RETURNING o, err
    CALL checkHas("an unknown option", err, "unknown option '--frob'")
    CALL options.parse(argv("app --json")) RETURNING o, err
    CALL check("after the program, an option is the program's", err IS NULL AND NOT o.json)
    CALL options.parse(argv("--port")) RETURNING o, err
    CALL checkHas("an option without its value", err, "--port needs a value")
    CALL options.parse(argv("--port 99999 app")) RETURNING o, err
    CALL checkHas("a port out of range", err, "port number")
    CALL options.parse(argv("--timeout 0 app")) RETURNING o, err
    CALL checkHas("a timeout of 0", err, "number of seconds")
    CALL options.parse(argv("--json")) RETURNING o, err
    CALL checkHas("no application", err, "say which application")
    CALL options.parse(argv("--url http://x/ua/r/app app")) RETURNING o, err
    CALL checkHas("two applications", err, "only one of")
    CALL options.parse(argv("--suite s app")) RETURNING o, err
    CALL checkHas("--suite without --config", err, "--suite needs --config")
    CALL options.parse(argv("--workdir /x --url http://x/ua/r/app")) RETURNING o, err
    CALL checkHas("--workdir with --url", err, "--workdir goes with")
    CALL checkHas("the usage lists the options", options.usage(), "--session-port")
END FUNCTION

FUNCTION t_options_application()
    DEFINE o options.Options
    DEFINE err STRING

    CALL options.parse(argv("bin/orders.42m -x 3")) RETURNING o, err
    CALL checkEq("a program runs with fglrun and its arguments", options.applicationCommand(o),
        "fglrun bin/orders.42m -x 3")
    CALL checkEq("... and is named after the program", options.applicationName(o), "orders")
    CALL options.parse(argv("--command-line 'fglrun -d orders arg'")) RETURNING o, err
    CALL checkEq("--command-line is used as it is", options.applicationCommand(o), "fglrun -d orders arg")
    CALL checkEq("... named after the program fglrun runs", options.applicationName(o), "orders")
    CALL options.parse(argv("--app billing orders")) RETURNING o, err
    CALL checkEq("--app names it", options.applicationName(o), "billing")
    CALL options.parse(argv("--config c.json --suite smoke")) RETURNING o, err
    CALL check("a config has no command of its own", options.applicationCommand(o) IS NULL)
    CALL checkEq("... and is named after the suite", options.applicationName(o), "smoke")
    CALL checkEq("a suite's command line names its program", options.commandName("fglrun demo"), "demo")
    CALL checkEq("... after fglrun's options", options.commandName("/opt/fgl/bin/fglrun -M app/orders.42m x"), "orders")
    CALL checkEq("... or its first word", options.commandName("./run.sh"), "run")
    CALL check("... and nothing for none", options.commandName(NULL) IS NULL)
END FUNCTION

FUNCTION t_options_detached()
    DEFINE o options.Options
    DEFINE err STRING

    CALL options.parse(argv("--detach --idle 600 --workdir /app orders")) RETURNING o, err
    CALL check("--detach with an application", err IS NULL AND o.detach)
    CALL checkInt("... --idle", o.idle, 600)
    CALL options.parse(argv('--send fields --send "fill f x"')) RETURNING o, err
    CALL check("--send needs no application", err IS NULL)
    CALL checkInt("... and repeats", o.send.getLength(), 2)
    CALL checkEq("... in order", o.send[2], "fill f x")
    CALL options.parse(argv("--stop --session s.json")) RETURNING o, err
    CALL check("--stop", err IS NULL AND o.stop)
    CALL checkEq("... --session", o.session, "s.json")

    CALL options.parse(argv("--detach")) RETURNING o, err
    CALL checkHas("--detach without an application", err, "say which application")
    CALL options.parse(argv("--send fields orders")) RETURNING o, err
    CALL checkHas("--send with an application", err, "give them no application")
    CALL options.parse(argv("--send fields --stop")) RETURNING o, err
    CALL checkHas("--send with --stop", err, "not both")
    CALL options.parse(argv("--send fields --script t.shell")) RETURNING o, err
    CALL checkHas("--send with --script", err, "do not go with --send")
    CALL options.parse(argv("--detach --save x.json orders")) RETURNING o, err
    CALL checkHas("--detach with --save", err, "do not go with --detach")
    CALL options.parse(argv("--idle 0 --detach orders")) RETURNING o, err
    CALL checkHas("an idle time of 0", err, "number of seconds")
END FUNCTION

# A detached session's shell lives for one call: what it knew — the
# recording, whether the application ended, the MESSAGE last shown — must
# come back in the next one.
FUNCTION t_detached_state()
    DEFINE text, shellState, recState STRING
    DEFINE done BOOLEAN

    CALL freshShell(FALSE, FALSE)
    LET text = shell('test "first"')
    LET text = shell("fill formonly.name Ada")
    LET m_message = "Added Ada."
    LET text = shell("action accept")
    LET m_message = NULL
    LET text = shell('test "second"')
    LET shellState = repl.state()
    LET recState = recording.state()

    # The next call: a new shell, restored instead of greeted.
    CALL recording.start("other")
    CALL repl.init(FUNCTION inProcess, FALSE, FALSE)
    CALL repl.restore(shellState)
    CALL check("the recording comes back", recording.restore(recState) IS NULL)
    CALL checkInt("... its steps", recording.stepCount(), 2)
    CALL checkEq("... the current test, even with no steps yet", recording.currentTest(), "second")
    CALL check("... and that it is unsaved", recording.unsaved())
    LET m_message = "Added Ada."
    LET text = shell("fields")
    CALL checkHasNot("a MESSAGE shown in an earlier call is not shown again", text, "Added Ada.")
    LET m_message = NULL
    LET text = shell("action cancel")
    CALL checkInt("steps recorded now join the restored ones", recording.stepCount(), 3)
    CALL checkHas("a bad saved recording is refused", recording.restore("{"), "cannot be read")

    CALL fakedriver.endOn("exit")
    LET text = shell("action exit")
    LET shellState = repl.state()
    CALL repl.init(FUNCTION inProcess, FALSE, FALSE)
    CALL repl.restore(shellState)
    CALL check("that the application ended comes back", repl.ended())
    LET text = shell("fields")
    CALL checkHas("... so the next call asks nothing of it", text, "the application has ended")

    CALL repl.execute("quit") RETURNING text, done
    CALL check("quit from a script quits", done)
    CALL checkHas("... saying what was not saved", text, "bye (4 recorded steps not saved)")
END FUNCTION

# --------------------------------------------------------------- release ----

FUNCTION t_version()
    DEFINE root, manifest, changelog, v STRING
    DEFINE m util.JSONObject

    LET root = os.Path.join(base.Application.getProgramDir(), "..")
    LET manifest = readTmp(os.Path.join(root, "fglpkg.json"))
    LET changelog = readTmp(os.Path.join(root, "CHANGELOG.md"))
    IF manifest IS NULL OR changelog IS NULL THEN
        CALL check("fglpkg.json and CHANGELOG.md can be read", FALSE)
        RETURN
    END IF
    LET m = util.JSONObject.parse(manifest)
    LET v = m.get("version")
    CALL checkEq("protocol.VERSION matches fglpkg.json", protocol.VERSION, v)
    CALL check("CHANGELOG.md has a section for this version",
        contains(changelog, SFMT("## [%1] - ", protocol.VERSION)))
END FUNCTION
