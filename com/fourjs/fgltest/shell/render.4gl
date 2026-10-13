# fgltest.shell.render — replies as the shell shows them to a person.
#
# (`fgltest_shell --json` prints the protocol's JSON replies instead.)

PACKAGE com.fourjs.fgltest.shell

IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.shell.protocol

#+ The text for a reply to request `op` (one or more lines, no trailing
#+ newline). The application's MESSAGE and ERROR lines are shown when they
#+ differ from `lastMessage` / `lastError`, the ones the shell showed last.
PUBLIC FUNCTION reply(op STRING, actionsAll BOOLEAN, r protocol.Reply,
    lastMessage STRING, lastError STRING) RETURNS STRING
    DEFINE b base.StringBuffer

    LET b = base.StringBuffer.create()
    # Once the application has ended there is nothing to list: a query's
    # answer would only show an empty window.
    IF core.isTrue(r.appEnded) AND op != "step" THEN
        LET op = NULL
    END IF
    CASE op
        WHEN "fields" CALL showFields(b, r)
        WHEN "actions" CALL showActions(b, r, actionsAll)
        WHEN "window" CALL showWindow(b, r)
        WHEN "tables" CALL showTables(b, r)
        WHEN "value" CALL showValue(b, r)
        WHEN "step" CALL showStep(b, r)
    END CASE
    # Once the application has ended, every request fails for that reason
    # alone (GGC: "the scenario has already ended"): say it once, below.
    IF r.error IS NOT NULL AND op != "step" AND NOT core.isTrue(r.appEnded) THEN
        CALL add(b, "ERROR: " || r.error)
    END IF
    IF LENGTH(r.errorLine) > 0 AND NOT same(r.errorLine, lastError) THEN
        CALL add(b, "application error line: " || r.errorLine)
    END IF
    IF LENGTH(r.message) > 0 AND NOT same(r.message, lastMessage) THEN
        CALL add(b, "application message: " || r.message)
    END IF
    IF core.isTrue(r.appEnded) THEN
        IF r.appError IS NOT NULL THEN
            CALL add(b, "the application stopped with a runtime error: " || r.appError)
        ELSE
            CALL add(b, "the application has ended")
        END IF
    END IF
    RETURN b.toString()
END FUNCTION

PRIVATE FUNCTION showFields(b base.StringBuffer, r protocol.Reply)
    DEFINE i, w INTEGER
    DEFINE state STRING
    IF r.fields.getLength() == 0 THEN
        CALL add(b, "(no fields in the current window)")
        RETURN
    END IF
    FOR i = 1 TO r.fields.getLength()
        IF r.fields[i].name.getLength() > w THEN
            LET w = r.fields[i].name.getLength()
        END IF
    END FOR
    FOR i = 1 TO r.fields.getLength()
        CASE
            WHEN core.isTrue(r.fields[i].hidden) LET state = "hidden"
            WHEN NOT core.isTrue(r.fields[i].active) LET state = "disabled"
            WHEN core.isTrue(r.fields[i].readOnly) LET state = "read-only"
            OTHERWISE LET state = "editable"
        END CASE
        CALL add(b, SFMT("%1%2  %3  %4", r.fields[i].name,
            pad(w - r.fields[i].name.getLength()), state, r.fields[i].widget))
    END FOR
END FUNCTION

PRIVATE FUNCTION showActions(b base.StringBuffer, r protocol.Reply, all BOOLEAN)
    DEFINE i INTEGER
    DEFINE line base.StringBuffer
    LET line = base.StringBuffer.create()
    FOR i = 1 TO r.actions.getLength()
        IF core.isTrue(all) THEN
            IF core.isTrue(r.actions[i].active) THEN
                CALL add(b, r.actions[i].name)
            ELSE
                CALL add(b, r.actions[i].name || "  (inactive)")
            END IF
        ELSE
            IF core.isTrue(r.actions[i].active) THEN
                IF line.getLength() > 0 THEN
                    CALL line.append("  ")
                END IF
                CALL line.append(r.actions[i].name)
            END IF
        END IF
    END FOR
    IF NOT core.isTrue(all) THEN
        IF line.getLength() == 0 THEN
            CALL add(b, "(no active actions)")
        ELSE
            CALL add(b, line.toString())
        END IF
    END IF
END FUNCTION

PRIVATE FUNCTION showWindow(b base.StringBuffer, r protocol.Reply)
    CALL add(b, SFMT("window %1%2", r.window.windowName, titled(r.window.windowTitle)))
    CALL add(b, SFMT("form   %1%2", r.window.formName, titled(r.window.formTitle)))
END FUNCTION

PRIVATE FUNCTION showTables(b base.StringBuffer, r protocol.Reply)
    DEFINE i INTEGER
    IF r.tables.getLength() == 0 THEN
        CALL add(b, "(no tables in the current window)")
        RETURN
    END IF
    FOR i = 1 TO r.tables.getLength()
        CALL add(b, SFMT("%1: %2 rows, current row %3",
            r.tables[i].name, r.tables[i].rows, r.tables[i].currentRow))
    END FOR
END FUNCTION

PRIVATE FUNCTION showValue(b base.StringBuffer, r protocol.Reply)
    IF r.error IS NULL THEN
        CALL add(b, SFMT("[%1]", r.value))
    END IF
END FUNCTION

PRIVATE FUNCTION showStep(b base.StringBuffer, r protocol.Reply)
    DEFINE i INTEGER
    IF r.error IS NOT NULL AND NOT core.isTrue(r.appEnded) THEN
        CALL add(b, "ERROR: " || r.error)
    END IF
    FOR i = 1 TO r.checks.getLength()
        IF core.isTrue(r.checks[i].passed) THEN
            CALL add(b, "ok: " || r.checks[i].message)
        ELSE
            CALL add(b, SFMT("FAIL: %1", r.checks[i].detail))
        END IF
    END FOR
    IF r.error IS NULL AND r.checks.getLength() == 0 AND core.isTrue(r.ok) THEN
        CALL add(b, "ok")
    END IF
END FUNCTION

PRIVATE FUNCTION add(b base.StringBuffer, s STRING)
    IF b.getLength() > 0 THEN
        CALL b.append(ASCII 10)
    END IF
    CALL b.append(s)
END FUNCTION

PRIVATE FUNCTION titled(t STRING) RETURNS STRING
    IF LENGTH(t) == 0 THEN
        RETURN ""
    END IF
    RETURN SFMT('  "%1"', t)
END FUNCTION

PRIVATE FUNCTION pad(n INTEGER) RETURNS STRING
    DEFINE b base.StringBuffer
    DEFINE i INTEGER
    LET b = base.StringBuffer.create()
    FOR i = 1 TO n
        CALL b.append(" ")
    END FOR
    RETURN b.toString()
END FUNCTION

# Equal, with NULL and "" the same.
PRIVATE FUNCTION same(a STRING, b STRING) RETURNS BOOLEAN
    IF LENGTH(a) == 0 AND LENGTH(b) == 0 THEN
        RETURN TRUE
    END IF
    IF a == b THEN
        RETURN TRUE
    END IF
    RETURN FALSE
END FUNCTION
