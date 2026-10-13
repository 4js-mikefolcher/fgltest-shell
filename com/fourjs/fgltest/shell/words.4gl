# fgltest.shell.words — split a command line into words.
#
#   fill formonly.customer "Big Co"      ->  fill | formonly.customer | Big Co
#   assertField formonly.note 'a "b"'    ->  assertField | formonly.note | a "b"
#
# Words are separated by spaces or tabs. A word may be quoted: "..." allows
# the escapes \" and \\, '...' is taken literally. An empty pair of quotes is
# an empty word.
#
# Byte-safe by construction: under FGL_LENGTH_SEMANTICS=BYTE (Genero's
# default) getCharAt() returns a blank for every continuation byte of a
# multibyte character, so it cannot even tell where the spaces are. Every
# delimiter here is found with getIndexOf() and every piece of text copied
# with subString(); positions agree under either semantics, and the
# delimiters are ASCII, which never occur inside a multibyte character.

PACKAGE com.fourjs.fgltest.shell

IMPORT FGL com.fourjs.fgltest.inspect

#+ Split `line` into words.
#+
#+ @return the words, and NULL or a message saying why the line cannot be split
#+         (an unterminated quote)
PUBLIC FUNCTION split(line STRING) RETURNS (inspect.StringList, STRING)
    DEFINE r inspect.StringList
    DEFINE i, len, e INTEGER
    DEFINE word STRING
    DEFINE err STRING

    LET len = line.getLength()
    LET i = 1
    WHILE i <= len
        IF isBlankAt(line, i) THEN
            LET i = i + 1
            CONTINUE WHILE
        END IF
        CASE
            WHEN line.getIndexOf('"', i) == i
                CALL doubleQuoted(line, i) RETURNING word, e, err
                IF err IS NOT NULL THEN
                    RETURN r, err
                END IF
            WHEN line.getIndexOf("'", i) == i
                LET e = line.getIndexOf("'", i + 1)
                IF e == 0 THEN
                    RETURN r, SFMT("unterminated ' quote at position %1", i)
                END IF
                LET word = piece(line, i + 1, e - 1)
            OTHERWISE
                LET e = nextBlank(line, i)
                LET word = piece(line, i, e - 1)
                LET e = e - 1
        END CASE
        LET r[r.getLength() + 1] = word
        LET i = e + 1
    END WHILE
    RETURN r, NULL
END FUNCTION

#+ `s` written as one word: as it is when it needs no quoting, else in double
#+ quotes with " and \ escaped. split() reads it back unchanged.
PUBLIC FUNCTION quote(s STRING) RETURNS STRING
    DEFINE b, r base.StringBuffer
    IF LENGTH(s) > 0 AND s.getIndexOf(" ", 1) == 0 AND s.getIndexOf(ASCII 9, 1) == 0
        AND s.getIndexOf('"', 1) == 0 AND s.getIndexOf("'", 1) == 0
        AND s.getIndexOf("\\", 1) == 0 THEN
        RETURN s
    END IF
    LET b = base.StringBuffer.create()
    CALL b.append(s)
    CALL b.replace("\\", "\\\\", 0)
    CALL b.replace('"', '\\"', 0)
    LET r = base.StringBuffer.create()
    CALL r.append('"')
    CALL r.append(b.toString())
    CALL r.append('"')
    RETURN r.toString()
END FUNCTION

# A "..." word starting at position i (the quote). Returns the word, the
# position of its closing quote, and an error if it has none.
PRIVATE FUNCTION doubleQuoted(line STRING, i INTEGER) RETURNS (STRING, INTEGER, STRING)
    DEFINE b base.StringBuffer
    DEFINE p, q, bs INTEGER

    LET b = base.StringBuffer.create()
    LET p = i + 1
    WHILE TRUE
        LET q = line.getIndexOf('"', p)
        LET bs = line.getIndexOf("\\", p)
        IF q == 0 THEN
            RETURN NULL, 0, SFMT('unterminated " quote at position %1', i)
        END IF
        IF bs > 0 AND bs < q THEN
            # An escape: \" and \\ stand for the character; any other
            # backslash is kept as it is.
            CALL b.append(piece(line, p, bs - 1))
            IF line.getIndexOf('"', bs + 1) == bs + 1 OR line.getIndexOf("\\", bs + 1) == bs + 1 THEN
                CALL b.append(piece(line, bs + 1, bs + 1))
                LET p = bs + 2
            ELSE
                CALL b.append("\\")
                LET p = bs + 1
            END IF
            CONTINUE WHILE
        END IF
        CALL b.append(piece(line, p, q - 1))
        EXIT WHILE
    END WHILE
    IF b.getLength() == 0 THEN
        RETURN "", q, NULL
    END IF
    RETURN b.toString(), q, NULL
END FUNCTION

# TRUE if position i holds a space or a tab. Tested with getIndexOf(), which
# finds the actual byte: a continuation byte can never match.
PRIVATE FUNCTION isBlankAt(line STRING, i INTEGER) RETURNS BOOLEAN
    IF line.getIndexOf(" ", i) == i OR line.getIndexOf(ASCII 9, i) == i THEN
        RETURN TRUE
    END IF
    RETURN FALSE
END FUNCTION

# The position of the first space or tab at or after i (length + 1 if none).
PRIVATE FUNCTION nextBlank(line STRING, i INTEGER) RETURNS INTEGER
    DEFINE sp, tb, n INTEGER
    LET n = line.getLength() + 1
    LET sp = line.getIndexOf(" ", i)
    LET tb = line.getIndexOf(ASCII 9, i)
    IF sp > 0 AND sp < n THEN
        LET n = sp
    END IF
    IF tb > 0 AND tb < n THEN
        LET n = tb
    END IF
    RETURN n
END FUNCTION

# subString() that yields "" for an empty range instead of failing.
PRIVATE FUNCTION piece(s STRING, a INTEGER, b INTEGER) RETURNS STRING
    IF b < a THEN
        RETURN ""
    END IF
    RETURN s.subString(a, b)
END FUNCTION
