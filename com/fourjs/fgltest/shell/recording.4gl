# fgltest.shell.recording — the tests being recorded in the shell, and the
# fgltest action file they are saved as.
#
# Every step that succeeds in the shell is added to the current test; `test
# <name>` starts another. save() writes an ordinary fgltest action file and
# then loads it back with fgltest's own loader, so a file the shell saves is
# one fgltest will run — the batch replay of an interactive session.

PACKAGE com.fourjs.fgltest.shell

IMPORT util
IMPORT FGL com.fourjs.fgltest.core
IMPORT FGL com.fourjs.fgltest.script
IMPORT FGL com.fourjs.fgltest.shell.words

PRIVATE TYPE Test RECORD
    name STRING,
    steps script.StepList
END RECORD

PRIVATE DEFINE m_application STRING
PRIVATE DEFINE m_tests DYNAMIC ARRAY OF Test
PRIVATE DEFINE m_unsaved BOOLEAN

# The whole recording, as state() writes it.
PRIVATE TYPE State RECORD
    application STRING,
    tests DYNAMIC ARRAY OF Test,
    unsaved BOOLEAN
END RECORD

#+ Start an empty recording for application `app`.
PUBLIC FUNCTION start(app STRING)
    LET m_application = app
    CALL m_tests.clear()
    LET m_unsaved = FALSE
END FUNCTION

#+ Start recording a new test called `name`. A current test with no steps yet
#+ is renamed instead.
#+
#+ @return NULL, or why the name cannot be used (a test already has it)
PUBLIC FUNCTION startTest(name STRING) RETURNS STRING
    DEFINE i, n INTEGER
    FOR i = 1 TO m_tests.getLength()
        IF m_tests[i].name == name THEN
            RETURN SFMT("a test called '%1' is already recorded — test names must be unique", name)
        END IF
    END FOR
    LET n = m_tests.getLength()
    IF n > 0 THEN
        IF m_tests[n].steps.getLength() == 0 THEN
            LET m_tests[n].name = name
            RETURN NULL
        END IF
    END IF
    LET m_tests[n + 1].name = name
    RETURN NULL
END FUNCTION

#+ Record a step in the current test (starting "test 1" if there is none).
PUBLIC FUNCTION add(step script.Step)
    DEFINE n, k INTEGER
    LET n = m_tests.getLength()
    IF n == 0 THEN
        LET n = 1
        LET m_tests[1].name = "test 1"
    END IF
    LET k = m_tests[n].steps.getLength() + 1
    LET m_tests[n].steps[k].* = step.*
    LET m_unsaved = TRUE
END FUNCTION

#+ Drop the current test's last step.
#+
#+ @return the dropped step as a shell line, or NULL if there was none
PUBLIC FUNCTION undo() RETURNS STRING
    DEFINE n, k INTEGER
    DEFINE line STRING
    LET n = m_tests.getLength()
    IF n == 0 THEN
        RETURN NULL
    END IF
    LET k = m_tests[n].steps.getLength()
    IF k == 0 THEN
        RETURN NULL
    END IF
    LET line = asLine(m_tests[n].steps[k])
    CALL m_tests[n].steps.deleteElement(k)
    LET m_unsaved = TRUE
    RETURN line
END FUNCTION

#+ The current test's name (NULL before anything is recorded).
PUBLIC FUNCTION currentTest() RETURNS STRING
    IF m_tests.getLength() == 0 THEN
        RETURN NULL
    END IF
    RETURN m_tests[m_tests.getLength()].name
END FUNCTION

#+ The current test's steps.
PUBLIC FUNCTION currentSteps() RETURNS script.StepList
    DEFINE none script.StepList
    IF m_tests.getLength() == 0 THEN
        RETURN none
    END IF
    RETURN m_tests[m_tests.getLength()].steps
END FUNCTION

#+ Steps recorded across all tests.
PUBLIC FUNCTION stepCount() RETURNS INTEGER
    DEFINE i, n INTEGER
    FOR i = 1 TO m_tests.getLength()
        LET n = n + m_tests[i].steps.getLength()
    END FOR
    RETURN n
END FUNCTION

#+ Tests that have at least one step (the ones save() writes).
PUBLIC FUNCTION testCount() RETURNS INTEGER
    DEFINE i, n INTEGER
    FOR i = 1 TO m_tests.getLength()
        IF m_tests[i].steps.getLength() > 0 THEN
            LET n = n + 1
        END IF
    END FOR
    RETURN n
END FUNCTION

#+ TRUE if steps were recorded or dropped since the last save.
PUBLIC FUNCTION unsaved() RETURNS BOOLEAN
    RETURN (m_unsaved AND stepCount() > 0)
END FUNCTION

#+ The recording as an fgltest action file (pretty-printed JSON). Only the
#+ members a step uses are written, and tests with no steps are left out (an
#+ action file may not have one).
PUBLIC FUNCTION toJson() RETURNS STRING
    DEFINE root, t, o util.JSONObject
    DEFINE tests, steps util.JSONArray
    DEFINE i, k INTEGER
    DEFINE req STRING
    DEFINE s script.Step

    LET root = util.JSONObject.create()
    CALL root.put("application", m_application)
    LET tests = util.JSONArray.create()
    FOR i = 1 TO m_tests.getLength()
        IF m_tests[i].steps.getLength() == 0 THEN
            CONTINUE FOR
        END IF
        LET t = util.JSONObject.create()
        CALL t.put("name", m_tests[i].name)
        LET steps = util.JSONArray.create()
        FOR k = 1 TO m_tests[i].steps.getLength()
            LET s.* = m_tests[i].steps[k].*
            LET req = script.requirements(s.command)
            LET o = util.JSONObject.create()
            CALL o.put("command", s.command)
            IF req.getIndexOf("t", 1) > 0 THEN
                CALL o.put("target", s.target)
            END IF
            IF req.getIndexOf("c", 1) > 0 THEN
                CALL o.put("column", s.col)
            END IF
            IF req.getIndexOf("r", 1) > 0 THEN
                CALL o.put("row", s.rowNum)
            END IF
            IF req.getIndexOf("v", 1) > 0 THEN
                IF LENGTH(s.value) == 0 THEN
                    # BDL's "" is NULL, which would be written as null and
                    # fail to load; an empty JSON string comes from parsing.
                    CALL o.put("value", emptyString())
                ELSE
                    CALL o.put("value", s.value)
                END IF
            END IF
            CALL steps.put(steps.getLength() + 1, o)
        END FOR
        CALL t.put("steps", steps)
        CALL tests.put(tests.getLength() + 1, t)
    END FOR
    CALL root.put("tests", tests)
    RETURN util.JSON.format(root.toString())
END FUNCTION

#+ Write the recording to `path` as an fgltest action file, then load it back
#+ with fgltest's loader to make sure fgltest will run it.
#+
#+ @return NULL when saved, else what went wrong
PUBLIC FUNCTION save(path STRING) RETURNS STRING
    DEFINE ch base.Channel
    DEFINE err STRING

    IF stepCount() == 0 THEN
        RETURN "nothing recorded yet: steps that succeed are recorded"
    END IF
    LET ch = base.Channel.create()
    TRY
        CALL ch.openFile(path, "w")
        CALL ch.writeLine(toJson())
        CALL ch.close()
    CATCH
        RETURN SFMT("cannot write '%1'", path)
    END TRY
    LET err = script.load(path)
    IF err IS NOT NULL THEN
        RETURN SFMT("saved, but fgltest does not accept the file: %1", err)
    END IF
    LET m_unsaved = FALSE
    RETURN NULL
END FUNCTION

#+ The recording as it stands, empty tests and all, for restore(): a shell
#+ that lives only for one `--send` keeps the recording between calls.
PUBLIC FUNCTION state() RETURNS STRING
    DEFINE st State
    LET st.application = m_application
    CALL m_tests.copyTo(st.tests)
    LET st.unsaved = core.isTrue(m_unsaved)
    RETURN util.JSON.stringify(st)
END FUNCTION

#+ Carry on with a recording state() wrote.
#+
#+ @return NULL, or why `text` is not one
PUBLIC FUNCTION restore(text STRING) RETURNS STRING
    DEFINE st State
    TRY
        CALL util.JSON.parse(text, st)
    CATCH
        RETURN "the saved recording cannot be read"
    END TRY
    LET m_application = st.application
    CALL st.tests.copyTo(m_tests)
    LET m_unsaved = core.isTrue(st.unsaved)
    RETURN NULL
END FUNCTION

#+ A step written as the shell line that records it, e.g.
#+ `fill formonly.customer "Big Co"`.
PUBLIC FUNCTION asLine(s script.Step) RETURNS STRING
    DEFINE b base.StringBuffer
    DEFINE req STRING
    LET req = script.requirements(s.command)
    LET b = base.StringBuffer.create()
    CALL b.append(s.command)
    IF req.getIndexOf("t", 1) > 0 THEN
        CALL b.append(" " || words.quote(s.target))
    END IF
    IF req.getIndexOf("c", 1) > 0 THEN
        CALL b.append(" " || words.quote(s.col))
    END IF
    IF req.getIndexOf("r", 1) > 0 THEN
        CALL b.append(SFMT(" %1", s.rowNum))
    END IF
    IF req.getIndexOf("v", 1) > 0 THEN
        CALL b.append(" " || words.quote(s.value))
    END IF
    RETURN b.toString()
END FUNCTION

# A STRING holding an empty string rather than NULL. A BDL "" literal is NULL;
# util.JSON.parse() gives a JSON "" as a real empty string.
PRIVATE FUNCTION emptyString() RETURNS STRING
    DEFINE r RECORD v STRING END RECORD
    CALL util.JSON.parse('{"v":""}', r)
    RETURN r.v
END FUNCTION
