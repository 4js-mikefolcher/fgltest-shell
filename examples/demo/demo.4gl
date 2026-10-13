# demo — a small contacts list, the application fgltest-shell's examples and
# end-to-end test drive.
#
# The main window lists contacts; its "append" action (shown as Add) opens a
# window to enter a new one, which must have a name. "cancel" (Exit) ends the
# program.

TYPE Contact RECORD
    name STRING,
    city STRING
END RECORD

DEFINE m_contacts DYNAMIC ARRAY OF Contact

MAIN
    OPEN FORM f FROM "contacts"
    DISPLAY FORM f

    LET m_contacts[1].name = "Ada Lovelace"
    LET m_contacts[1].city = "London"
    LET m_contacts[2].name = "Grace Hopper"
    LET m_contacts[2].city = "New York"
    LET m_contacts[3].name = "Alan Turing"
    LET m_contacts[3].city = "Manchester"

    DISPLAY ARRAY m_contacts TO sr_contacts.* ATTRIBUTES(UNBUFFERED)
        ON APPEND ATTRIBUTES(TEXT = "Add")
            -- The dialog has added the row; a cancelled entry removes it.
            CALL enterContact(DIALOG.getCurrentRow("sr_contacts"))
        ON ACTION cancel ATTRIBUTES(TEXT = "Exit")
            EXIT DISPLAY
    END DISPLAY
END MAIN

# Enter the new contact in row `row`. int_flag is left as the INPUT set it:
# it is ON APPEND's verdict on the row.
FUNCTION enterContact(row INTEGER)
    DEFINE rec RECORD
        c_name STRING,
        c_city STRING,
        c_phone STRING
    END RECORD

    OPEN WINDOW w_contact WITH FORM "contact"
    INITIALIZE rec.* TO NULL
    INPUT BY NAME rec.*
        AFTER INPUT
            IF NOT int_flag AND LENGTH(rec.c_name) == 0 THEN
                ERROR "A contact needs a name."
                NEXT FIELD c_name
            END IF
    END INPUT
    CLOSE WINDOW w_contact
    IF int_flag THEN
        RETURN
    END IF
    LET m_contacts[row].name = rec.c_name
    LET m_contacts[row].city = rec.c_city
    MESSAGE SFMT("Added %1.", rec.c_name)
END FUNCTION
