// AOSO/core/json.ks
// JSON encode/decode + file persistence helpers.
// Uses the simpleJson addon through core/addons.ks when available, otherwise
// falls back to a pure-kOS recursive-descent parser/encoder implemented here.
// Supported value types: scalar (string/number/bool), LIST, LEXICON. Nested
// structures are supported to arbitrary depth.

FUNCTION aoso_json_encode {
    PARAMETER value.

    IF value:ISTYPE("Lexicon") {
        LOCAL parts IS LIST().
        LOCAL ks IS value:KEYS.
        FOR k IN ks {
            parts:ADD("""" + aoso_json_escape(k) + """:" + aoso_json_encode(value[k])).
        }
        LOCAL s IS "{".
        FOR i IN RANGE(0, parts:LENGTH) {
            SET s TO s + parts[i].
            IF i < (parts:LENGTH - 1) { SET s TO s + ",". }
        }
        RETURN s + "}".
    } ELSE IF value:ISTYPE("List") {
        LOCAL parts IS LIST().
        FOR item IN value {
            parts:ADD(aoso_json_encode(item)).
        }
        LOCAL s IS "[".
        FOR i IN RANGE(0, parts:LENGTH) {
            SET s TO s + parts[i].
            IF i < (parts:LENGTH - 1) { SET s TO s + ",". }
        }
        RETURN s + "]".
    } ELSE IF value:ISTYPE("String") {
        RETURN """" + aoso_json_escape(value) + """".
    } ELSE IF value:ISTYPE("Boolean") {
        IF value { RETURN "true". } ELSE { RETURN "false". }
    } ELSE IF value:ISTYPE("Scalar") {
        RETURN "" + value.
    } ELSE {
        // Fallback: stringify anything unrecognized (e.g. vectors already
        // converted upstream by callers).
        RETURN """" + aoso_json_escape("" + value) + """".
    }
}

FUNCTION aoso_json_escape {
    PARAMETER s.
    LOCAL out IS "".
    FOR i IN RANGE(0, s:LENGTH) {
        LOCAL c IS s[i].
        IF c = """" { SET out TO out + "\""". }
        ELSE IF c = "\" { SET out TO out + "\\". }
        ELSE IF c = CHAR(10) { SET out TO out + "\n". }
        ELSE IF c = CHAR(13) { SET out TO out + "\r". }
        ELSE IF c = CHAR(9) { SET out TO out + "\t". }
        ELSE { SET out TO out + c. }
    }
    RETURN out.
}

// --- Pure-kOS JSON parser (recursive descent, single-pass) ----------------

FUNCTION aoso_json_decode {
    PARAMETER text.
    LOCAL state IS LEXICON("s", text, "i", 0).
    aoso_json_skip_ws(state).
    RETURN aoso_json_parse_value(state).
}

FUNCTION aoso_json_peek {
    PARAMETER state.
    IF state["i"] >= state["s"]:LENGTH { RETURN "". }
    RETURN state["s"][state["i"]].
}

FUNCTION aoso_json_skip_ws {
    PARAMETER state.
    UNTIL state["i"] >= state["s"]:LENGTH {
        LOCAL c IS state["s"][state["i"]].
        IF c = " " OR c = CHAR(9) OR c = CHAR(10) OR c = CHAR(13) {
            SET state["i"] TO state["i"] + 1.
        } ELSE {
            BREAK.
        }
    }
}

FUNCTION aoso_json_parse_value {
    PARAMETER state.
    aoso_json_skip_ws(state).
    LOCAL c IS aoso_json_peek(state).
    IF c = "{" { RETURN aoso_json_parse_object(state). }
    IF c = "[" { RETURN aoso_json_parse_array(state). }
    IF c = """" { RETURN aoso_json_parse_string(state). }
    IF c = "t" OR c = "f" { RETURN aoso_json_parse_bool(state). }
    IF c = "n" {
        SET state["i"] TO state["i"] + 4. // "null"
        RETURN "".
    }
    RETURN aoso_json_parse_number(state).
}

FUNCTION aoso_json_parse_object {
    PARAMETER state.
    LOCAL result IS LEXICON().
    SET state["i"] TO state["i"] + 1. // {
    aoso_json_skip_ws(state).
    IF aoso_json_peek(state) = "}" {
        SET state["i"] TO state["i"] + 1.
        RETURN result.
    }
    UNTIL FALSE {
        aoso_json_skip_ws(state).
        LOCAL key IS aoso_json_parse_string(state).
        aoso_json_skip_ws(state).
        SET state["i"] TO state["i"] + 1. // :
        LOCAL val IS aoso_json_parse_value(state).
        result:ADD(key, val).
        aoso_json_skip_ws(state).
        IF aoso_json_peek(state) = "," {
            SET state["i"] TO state["i"] + 1.
        } ELSE {
            SET state["i"] TO state["i"] + 1. // }
            BREAK.
        }
    }
    RETURN result.
}

FUNCTION aoso_json_parse_array {
    PARAMETER state.
    LOCAL result IS LIST().
    SET state["i"] TO state["i"] + 1. // [
    aoso_json_skip_ws(state).
    IF aoso_json_peek(state) = "]" {
        SET state["i"] TO state["i"] + 1.
        RETURN result.
    }
    UNTIL FALSE {
        LOCAL val IS aoso_json_parse_value(state).
        result:ADD(val).
        aoso_json_skip_ws(state).
        IF aoso_json_peek(state) = "," {
            SET state["i"] TO state["i"] + 1.
        } ELSE {
            SET state["i"] TO state["i"] + 1. // ]
            BREAK.
        }
    }
    RETURN result.
}

FUNCTION aoso_json_parse_string {
    PARAMETER state.
    SET state["i"] TO state["i"] + 1. // opening quote
    LOCAL out IS "".
    UNTIL FALSE {
        LOCAL c IS aoso_json_peek(state).
        IF c = """" {
            SET state["i"] TO state["i"] + 1.
            BREAK.
        } ELSE IF c = "\" {
            SET state["i"] TO state["i"] + 1.
            LOCAL e IS aoso_json_peek(state).
            IF e = "n" { SET out TO out + CHAR(10). }
            ELSE IF e = "r" { SET out TO out + CHAR(13). }
            ELSE IF e = "t" { SET out TO out + CHAR(9). }
            ELSE { SET out TO out + e. }
            SET state["i"] TO state["i"] + 1.
        } ELSE {
            SET out TO out + c.
            SET state["i"] TO state["i"] + 1.
        }
    }
    RETURN out.
}

FUNCTION aoso_json_parse_bool {
    PARAMETER state.
    IF aoso_json_peek(state) = "t" {
        SET state["i"] TO state["i"] + 4. // true
        RETURN TRUE.
    }
    SET state["i"] TO state["i"] + 5. // false
    RETURN FALSE.
}

FUNCTION aoso_json_parse_number {
    PARAMETER state.
    LOCAL start IS state["i"].
    UNTIL state["i"] >= state["s"]:LENGTH {
        LOCAL c IS state["s"][state["i"]].
        IF (c >= "0" AND c <= "9") OR c = "-" OR c = "+" OR c = "." OR c = "e" OR c = "E" {
            SET state["i"] TO state["i"] + 1.
        } ELSE {
            BREAK.
        }
    }
    LOCAL sub IS state["s"]:SUBSTRING(start, state["i"] - start).
    RETURN sub:TONUMBER(0).
}

// --- File persistence -------------------------------------------------

FUNCTION aoso_json_write {
    PARAMETER file_path.
    PARAMETER value.
    IF aoso_addon_simplejson_available() {
        aoso_addon_simplejson_write(file_path, value).
        RETURN TRUE.
    }
    LOCAL text IS aoso_json_encode(value).
    LOCAL f IS OPEN(file_path).
    f:CLEAR().
    f:WRITELN(text).
    RETURN TRUE.
}

FUNCTION aoso_json_read {
    PARAMETER file_path.
    PARAMETER default_value IS LEXICON().
    IF NOT EXISTS(file_path) { RETURN default_value. }
    IF aoso_addon_simplejson_available() {
        RETURN aoso_addon_simplejson_read(file_path, default_value).
    }
    LOCAL f IS OPEN(file_path).
    LOCAL text IS "".
    LOCAL lines IS f:READALL().
    UNTIL lines:LENGTH = 0 {
        SET text TO text + lines:POP().
    }
    IF text:LENGTH = 0 { RETURN default_value. }
    RETURN aoso_json_decode(text).
}
