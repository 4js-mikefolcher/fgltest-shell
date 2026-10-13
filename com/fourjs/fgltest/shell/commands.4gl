# fgltest.shell.commands — what a line typed in the shell means.
#
# Two kinds of command:
#
#   shell commands   look and manage:  fields, actions, window, tables, value,
#                    test, steps, undo, save, run, help, quit
#   test steps       fgltest's action-file commands, written as words:
#                       fill formonly.customer "Big Co"
#                       action accept
#                       assertCellAtRow prices name 3 Globe
#
# A step's words fill what the command needs in a fixed order — target,
# column, row, value — taken from fgltest's own command table
# (script.requirements), so the shell knows every command fgltest does and
# checks it the same way. A step that succeeds is recorded; see recording.

PACKAGE com.fourjs.fgltest.shell

IMPORT FGL com.fourjs.fgltest.inspect
IMPORT FGL com.fourjs.fgltest.script
IMPORT FGL com.fourjs.fgltest.shell.words

#+ A parsed line.
#+
#+ kind: none (blank or a # comment), error, step, or a shell command —
#+ help, query (name = fields, actions, window, tables or value), test, steps,
#+ undo, save, run, quit.
PUBLIC TYPE ShellCommand RECORD
    kind STRING,
    name STRING,          -- the command, as fgltest spells it
    arg STRING,           -- a shell command's argument (topic, field, name, file)
    step script.Step,     -- for kind "step"
    error STRING          -- for kind "error"
END RECORD

# The order in which a step's words fill what its command requires.
PRIVATE CONSTANT ARG_ORDER = "tcrv"

#+ Parse one line typed in the shell.
PUBLIC FUNCTION parse(line STRING) RETURNS ShellCommand
    DEFINE c ShellCommand
    DEFINE w inspect.StringList
    DEFINE err, first, req, letter, order STRING
    DEFINE i, n, minArgs, maxArgs INTEGER

    INITIALIZE c.* TO NULL
    LET c.kind = "none"
    CALL words.split(line) RETURNING w, err
    IF err IS NOT NULL THEN
        RETURN failed(c, err)
    END IF
    IF w.getLength() == 0 THEN
        RETURN c
    END IF
    LET first = w[1]
    IF first.getIndexOf("#", 1) == 1 THEN
        RETURN c
    END IF

    CALL shellCommand(first) RETURNING c.kind, c.name, minArgs, maxArgs
    IF c.kind IS NOT NULL THEN
        LET n = w.getLength() - 1
        IF n < minArgs OR n > maxArgs THEN
            RETURN failed(c, SFMT("usage: %1", usage(c.name)))
        END IF
        IF n >= 1 THEN
            LET c.arg = w[2]
        END IF
        IF c.name == "actions" AND n == 1 AND c.arg != "all" THEN
            RETURN failed(c, "usage: actions [all]")
        END IF
        RETURN c
    END IF

    # A test step: an action-file command.
    LET c.name = canonical(first)
    IF c.name IS NULL THEN
        RETURN failed(c, SFMT("unknown command '%1' — type help for the list", first))
    END IF
    LET c.kind = "step"
    LET req = script.requirements(c.name)
    LET order = ARG_ORDER   -- a CONSTANT is a literal: no methods on it
    LET n = 0
    FOR i = 1 TO order.getLength()
        IF req.getIndexOf(order.subString(i, i), 1) > 0 THEN
            LET n = n + 1
        END IF
    END FOR
    IF w.getLength() - 1 != n THEN
        RETURN failed(c, SFMT("usage: %1", usage(c.name)))
    END IF
    LET c.step.command = c.name
    LET n = 1
    FOR i = 1 TO order.getLength()
        LET letter = order.subString(i, i)
        IF req.getIndexOf(letter, 1) == 0 THEN
            CONTINUE FOR
        END IF
        LET n = n + 1
        CASE letter
            WHEN "t" LET c.step.target = w[n]
            WHEN "c" LET c.step.col = w[n]
            WHEN "r"
                IF NOT isCount(w[n]) OR w[n] == "0" THEN
                    RETURN failed(c, SFMT("the row must be a whole number of 1 or more, not '%1' — usage: %2",
                        w[n], usage(c.name)))
                END IF
                LET c.step.rowNum = w[n]
            WHEN "v" LET c.step.value = w[n]
        END CASE
    END FOR
    IF req.getIndexOf("n", 1) > 0 AND NOT isCount(c.step.value) THEN
        RETURN failed(c, SFMT("'%1' needs a whole number, not '%2' — usage: %3",
            c.name, c.step.value, usage(c.name)))
    END IF
    RETURN c
END FUNCTION

#+ How to call a command, e.g. "fill <field> <value>".
PUBLIC FUNCTION usage(name STRING) RETURNS STRING
    DEFINE req, kind, canon STRING
    DEFINE minArgs, maxArgs INTEGER
    DEFINE b base.StringBuffer

    CALL shellCommand(name) RETURNING kind, canon, minArgs, maxArgs
    IF kind IS NOT NULL THEN
        CASE canon
            WHEN "help" RETURN "help [command]"
            WHEN "actions" RETURN "actions [all]"
            WHEN "value" RETURN "value [field]"
            WHEN "test" RETURN "test <name>"
            WHEN "save" RETURN "save <file.actions.json>"
            WHEN "run" RETURN "run <file.actions.json>"
        END CASE
        RETURN canon
    END IF
    LET canon = canonical(name)
    IF canon IS NULL THEN
        RETURN name
    END IF
    LET req = script.requirements(canon)
    LET b = base.StringBuffer.create()
    CALL b.append(canon)
    IF req.getIndexOf("t", 1) > 0 THEN
        CALL b.append(SFMT(" <%1>", targetNoun(canon)))
    END IF
    IF req.getIndexOf("c", 1) > 0 THEN
        CALL b.append(" <column>")
    END IF
    IF req.getIndexOf("r", 1) > 0 THEN
        CALL b.append(" <row>")
    END IF
    IF req.getIndexOf("v", 1) > 0 THEN
        CALL b.append(SFMT(" <%1>", valueNoun(canon)))
    END IF
    RETURN b.toString()
END FUNCTION

#+ The help text: everything when `topic` is NULL, else that command's usage
#+ and what it does.
PUBLIC FUNCTION help(topic STRING) RETURNS STRING
    DEFINE b base.StringBuffer
    DEFINE cmds inspect.StringList
    DEFINE i INTEGER
    DEFINE nl, kind, canon STRING
    DEFINE minArgs, maxArgs INTEGER

    LET nl = ASCII 10
    IF LENGTH(topic) > 0 THEN
        CALL shellCommand(topic) RETURNING kind, canon, minArgs, maxArgs
        IF kind IS NULL THEN
            LET canon = canonical(topic)
        END IF
        IF canon IS NULL THEN
            RETURN SFMT("unknown command '%1' — type help for the list", topic)
        END IF
        RETURN SFMT("%1%2  %3", usage(canon), nl, describe(canon))
    END IF

    LET b = base.StringBuffer.create()
    CALL b.append("Look at the application:" || nl)
    CALL line(b, "fields")
    CALL line(b, "actions")
    CALL line(b, "window")
    CALL line(b, "tables")
    CALL line(b, "value")
    CALL b.append(nl || "Record a test (each step that succeeds is recorded):" || nl)
    CALL line(b, "test")
    CALL line(b, "steps")
    CALL line(b, "undo")
    CALL line(b, "save")
    CALL line(b, "run")
    CALL line(b, "help")
    CALL line(b, "quit")
    CALL b.append(nl || "Test steps (fgltest action-file commands; quote a word with spaces):" || nl)
    LET cmds = script.commands()
    FOR i = 1 TO cmds.getLength()
        CALL line(b, cmds[i])
    END FOR
    RETURN b.toString()
END FUNCTION

# ------------------------------------------------------------ helpers ----

# A shell command's kind, spelling and argument count (kind NULL if `word`
# is not one). Matched without regard to case.
PRIVATE FUNCTION shellCommand(word STRING) RETURNS (STRING, STRING, INTEGER, INTEGER)
    DEFINE w STRING
    LET w = word.toLowerCase()
    CASE w
        WHEN "help" RETURN "help", "help", 0, 1
        WHEN "?" RETURN "help", "help", 0, 1
        WHEN "fields" RETURN "query", "fields", 0, 0
        WHEN "actions" RETURN "query", "actions", 0, 1
        WHEN "window" RETURN "query", "window", 0, 0
        WHEN "tables" RETURN "query", "tables", 0, 0
        WHEN "value" RETURN "query", "value", 0, 1
        WHEN "test" RETURN "test", "test", 1, 1
        WHEN "steps" RETURN "steps", "steps", 0, 0
        WHEN "undo" RETURN "undo", "undo", 0, 0
        WHEN "save" RETURN "save", "save", 1, 1
        WHEN "run" RETURN "run", "run", 1, 1
        WHEN "quit" RETURN "quit", "quit", 0, 0
        WHEN "exit" RETURN "quit", "quit", 0, 0
    END CASE
    RETURN NULL, NULL, 0, 0
END FUNCTION

# The action-file command `word` names, spelled as fgltest spells it (NULL if
# none): "assertfield" is assertField.
PRIVATE FUNCTION canonical(word STRING) RETURNS STRING
    DEFINE cmds inspect.StringList
    DEFINE i INTEGER
    DEFINE w STRING
    LET w = word.toLowerCase()
    LET cmds = script.commands()
    FOR i = 1 TO cmds.getLength()
        IF cmds[i].toLowerCase() == w THEN
            RETURN cmds[i]
        END IF
    END FOR
    RETURN NULL
END FUNCTION

PRIVATE FUNCTION targetNoun(cmd STRING) RETURNS STRING
    CASE
        WHEN cmd == "action" OR cmd MATCHES "assertAction*" RETURN "action"
        WHEN cmd == "key" RETURN "key"
        WHEN cmd == "selectRow" OR cmd == "focusCell" OR cmd == "assertTableExists"
            OR cmd MATCHES "assertCell*" OR cmd MATCHES "assertRowCount*"
            OR cmd == "assertCurrentRow"
            RETURN "table"
    END CASE
    RETURN "field"
END FUNCTION

PRIVATE FUNCTION valueNoun(cmd STRING) RETURNS STRING
    CASE
        WHEN cmd == "pause" RETURN "milliseconds"
        WHEN cmd == "assertCurrentRow" RETURN "row"
        WHEN cmd == "assertFieldCount" OR cmd MATCHES "assertRowCount*" RETURN "count"
        WHEN cmd MATCHES "*Matches" RETURN "regex"
        WHEN cmd == "assertFormName" RETURN "form"
        WHEN cmd == "assertWindowName" RETURN "window"
        WHEN cmd MATCHES "*Title" RETURN "title"
        WHEN cmd MATCHES "*Contains" RETURN "text"
    END CASE
    RETURN "value"
END FUNCTION

# What a command does, in one line.
PRIVATE FUNCTION describe(cmd STRING) RETURNS STRING
    CASE cmd
        WHEN "fields" RETURN "List the current window's fields: editable, read-only, disabled or hidden."
        WHEN "actions" RETURN "List the active actions (with all, every action and whether it is active)."
        WHEN "window" RETURN "Show the current window and form, with their titles."
        WHEN "tables" RETURN "List the current window's tables, with their row counts and current rows."
        WHEN "value" RETURN "Show a field's value (without a field, the current field's)."
        WHEN "test" RETURN "Start recording a new test with this name."
        WHEN "steps" RETURN "Show the steps recorded so far in the current test."
        WHEN "undo" RETURN "Drop the last recorded step (it is not undone in the application)."
        WHEN "save" RETURN "Write the recorded tests to an fgltest action file."
        WHEN "run" RETURN "Run an fgltest action file's tests in this session."
        WHEN "help" RETURN "List the commands, or describe one."
        WHEN "quit" RETURN "End the session (asks again if there are unsaved steps)."
        WHEN "action" RETURN "Trigger an action, such as a button or a menu option."
        WHEN "field" RETURN "Move the focus to a field."
        WHEN "enter" RETURN "Type a value into the field that has the focus."
        WHEN "fill" RETURN "Move to a field, as a user would, and put a value in it."
        WHEN "clear" RETURN "Clear the field that has the focus."
        WHEN "key" RETURN "Press a key, such as Return or F5."
        WHEN "pause" RETURN "Wait a number of milliseconds."
        WHEN "selectRow" RETURN "Move to a table row (rows count from 1)."
        WHEN "focusCell" RETURN "Move to a table cell."
        WHEN "assertField" RETURN "Check that a field has this value."
        WHEN "assertFieldNot" RETURN "Check that a field does not have this value."
        WHEN "assertFieldContains" RETURN "Check that a field's value contains this text."
        WHEN "assertFieldMatches" RETURN "Check that a field's value matches this regular expression."
        WHEN "assertCurrent" RETURN "Check the value of the field that has the focus."
        WHEN "assertFormName" RETURN "Check the current form's name."
        WHEN "assertFormTitle" RETURN "Check the current form's title."
        WHEN "assertWindowName" RETURN "Check the current window's name."
        WHEN "assertWindowTitle" RETURN "Check the current window's title."
        WHEN "assertActionActive" RETURN "Check that an action is active."
        WHEN "assertActionInactive" RETURN "Check that an action is not active."
        WHEN "assertActionExists" RETURN "Check that an action exists."
        WHEN "assertActionMissing" RETURN "Check that an action does not exist."
        WHEN "assertFieldEnabled" RETURN "Check that a field is enabled."
        WHEN "assertFieldDisabled" RETURN "Check that a field is not enabled."
        WHEN "assertFieldEditable" RETURN "Check that a field can be edited."
        WHEN "assertFieldReadOnly" RETURN "Check that a field cannot be edited."
        WHEN "assertFieldExists" RETURN "Check that a field exists."
        WHEN "assertFieldMissing" RETURN "Check that a field does not exist."
        WHEN "assertFieldCount" RETURN "Check the number of fields."
        WHEN "assertTableExists" RETURN "Check that a table exists."
        WHEN "assertCell" RETURN "Check a cell of the current row."
        WHEN "assertCellContains" RETURN "Check that a cell of the current row contains this text."
        WHEN "assertCellMatches" RETURN "Check that a cell of the current row matches this regular expression."
        WHEN "assertCellAtRow" RETURN "Move to a row, then check one of its cells."
        WHEN "assertRowCount" RETURN "Check a table's number of rows."
        WHEN "assertRowCountAtLeast" RETURN "Check that a table has at least this many rows."
        WHEN "assertRowCountAtMost" RETURN "Check that a table has at most this many rows."
        WHEN "assertCurrentRow" RETURN "Check a table's current row."
    END CASE
    RETURN ""
END FUNCTION

# One command in the list: its usage, then what it does in a column (or on
# the next line, under it, when the usage is too long for the column).
PRIVATE FUNCTION line(b base.StringBuffer, cmd STRING)
    DEFINE u STRING
    LET u = usage(cmd)
    CALL b.append("  ")
    CALL b.append(u)
    IF u.getLength() > 32 THEN
        CALL b.append(ASCII 10)
        CALL b.append(spaces(36))
    ELSE
        CALL b.append(spaces(34 - u.getLength()))
    END IF
    CALL b.append(describe(cmd))
    CALL b.append(ASCII 10)
END FUNCTION

PRIVATE FUNCTION spaces(n INTEGER) RETURNS STRING
    DEFINE b base.StringBuffer
    DEFINE i INTEGER
    LET b = base.StringBuffer.create()
    CALL b.append(" ")
    FOR i = 2 TO n
        CALL b.append(" ")
    END FOR
    RETURN b.toString()
END FUNCTION

PRIVATE FUNCTION isCount(v STRING) RETURNS BOOLEAN
    IF v IS NULL OR LENGTH(v) == 0 OR LENGTH(v) > 9 THEN
        RETURN FALSE
    END IF
    RETURN v.matches("^[0-9]+$")
END FUNCTION

PRIVATE FUNCTION failed(c ShellCommand, msg STRING) RETURNS ShellCommand
    LET c.kind = "error"
    LET c.error = msg
    RETURN c
END FUNCTION
