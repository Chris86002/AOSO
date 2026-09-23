// AOSO/ux/ui2_go.ks
// Prelaunch systems board. Lights are annunciators. The LAUNCH button
// calls aoso_launch_request(), which only sets the commit flag when every
// required light is already green. It does not steer, throttle, stage,
// or start the mission. mission/launch_hold.ks does that on a later tick.

GLOBAL AOSO_UI2_GO_MAIN IS 0.
GLOBAL AOSO_UI2_GO_BTNS IS LEXICON().
GLOBAL AOSO_UI2_GO_ARM IS 0.
GLOBAL AOSO_UI2_GO_TITLE IS 0.
GLOBAL AOSO_UI2_GO_WHY IS 0.
GLOBAL AOSO_UI2_GO_HINT IS 0.

FUNCTION aoso_ui2_go_clear {
    SET AOSO_UI2_GO_MAIN TO 0.
    SET AOSO_UI2_GO_BTNS TO LEXICON().
    SET AOSO_UI2_GO_ARM TO 0.
    SET AOSO_UI2_GO_TITLE TO 0.
    SET AOSO_UI2_GO_WHY TO 0.
    SET AOSO_UI2_GO_HINT TO 0.
}

FUNCTION aoso_ui2_go_click {
    aoso_launch_request().
}

FUNCTION aoso_ui2_go_lamp {
    PARAMETER page.
    PARAMETER lamp_id.
    PARAMETER col.
    PARAMETER row_i.
    LOCAL holder IS aoso_crt_holder(page).
    LOCAL btn IS holder:ADDBUTTON("---").
    aoso_crt_zero(btn).
    aoso_crt_move(btn, 28 + col * 214, 64 + row_i * 40, 200, 32).
    SET btn:STYLE:FONTSIZE TO 12.
    SET btn:STYLE:ALIGN TO "CENTER".
    aoso_ui2_button_bg(btn, "button_stby").
    SET AOSO_UI2_GO_BTNS[lamp_id] TO btn.
}

FUNCTION aoso_ui2_go_build {
    PARAMETER page.
    aoso_crt_page(page, "crt_go.png").
    SET AOSO_UI2_GO_MAIN TO page.
    SET AOSO_UI2_GO_BTNS TO LEXICON().

    SET AOSO_UI2_GO_TITLE TO aoso_crt_label(page, 300, 14, 160, 14).
    LOCAL i IS 0.
    UNTIL i >= AOSO_LAUNCH_ORDER:LENGTH {
        LOCAL lamp_id IS AOSO_LAUNCH_ORDER[i].
        LOCAL col IS 0.
        LOCAL row_i IS i.
        IF i >= 6 {
            SET col TO 1.
            SET row_i TO i - 6.
        }
        aoso_ui2_go_lamp(page, lamp_id, col, row_i).
        SET i TO i + 1.
    }

    SET AOSO_UI2_GO_ARM TO aoso_crt_holder(page):ADDBUTTON("").
    SET AOSO_UI2_GO_ARM:ONCLICK TO aoso_ui2_go_click@.
    aoso_crt_zero(AOSO_UI2_GO_ARM).
    aoso_crt_move(AOSO_UI2_GO_ARM, 490, 148, 200, 72).
    SET AOSO_UI2_GO_ARM:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "launch_hold.png".
    SET AOSO_UI2_GO_ARM:STYLE:HOVER:BG TO AOSO_UI2_ASSET_ROOT + "launch_hold.png".
    SET AOSO_UI2_GO_ARM:STYLE:FOCUSED:BG TO AOSO_UI2_ASSET_ROOT + "launch_hold.png".
    SET AOSO_UI2_GO_ARM:STYLE:ACTIVE:BG TO AOSO_UI2_ASSET_ROOT + "launch_hold.png".

    SET AOSO_UI2_GO_WHY TO aoso_crt_label(page, 28, 328, 680, 14).
    SET AOSO_UI2_GO_HINT TO aoso_crt_label(page, 28, 356, 680, 13).
}

FUNCTION aoso_ui2_go_face {
    PARAMETER btn.
    PARAMETER lamp_state.
    LOCAL asset_name IS "button_stby".
    IF lamp_state = "GO" { SET asset_name TO "button_on". }
    IF lamp_state = "FAIL" { SET asset_name TO "button_fail". }
    IF lamp_state = "WARN" { SET asset_name TO "button_warn". }
    aoso_ui2_button_bg(btn, asset_name).
}

FUNCTION aoso_ui2_go_arm_face {
    PARAMETER art_name.
    IF NOT AOSO_UI2_GO_ARM:ISTYPE("BUTTON") { RETURN. }
    LOCAL file IS AOSO_UI2_ASSET_ROOT + art_name + ".png".
    SET AOSO_UI2_GO_ARM:STYLE:BG TO file.
    SET AOSO_UI2_GO_ARM:STYLE:HOVER:BG TO file.
    SET AOSO_UI2_GO_ARM:STYLE:FOCUSED:BG TO file.
    SET AOSO_UI2_GO_ARM:STYLE:ACTIVE:BG TO file.
}

FUNCTION aoso_ui2_go_update {
    IF NOT AOSO_UI2_GO_MAIN:ISTYPE("WIDGET") { RETURN. }
    aoso_launch_board_eval(FALSE).
    IF NOT AOSO_LAUNCH_BOARD:HASKEY("items") { RETURN. }

    LOCAL items IS AOSO_LAUNCH_BOARD["items"].
    FOR lamp_id IN AOSO_LAUNCH_ORDER {
        IF AOSO_UI2_GO_BTNS:HASKEY(lamp_id) {
            IF items:HASKEY(lamp_id) {
                LOCAL lamp IS items[lamp_id].
                LOCAL lamp_btn IS AOSO_UI2_GO_BTNS[lamp_id].
                LOCAL lamp_state IS lamp["state"].
                aoso_ui2_go_face(lamp_btn, lamp_state).
                SET lamp_btn:TEXT TO lamp["label"] + CHAR(10) + lamp_state + "  " + lamp["detail"].
            }
        }
    }

    LOCAL armed IS FALSE.
    IF AOSO_LAUNCH_BOARD:HASKEY("arm") { SET armed TO AOSO_LAUNCH_BOARD["arm"]. }
    LOCAL committed IS FALSE.
    IF AOSO_LAUNCH_BOARD:HASKEY("commit") { SET committed TO AOSO_LAUNCH_BOARD["commit"]. }
    LOCAL on_pad IS aoso_launch_hold_active().

    LOCAL art_name IS "launch_hold".
    LOCAL title_txt IS "CHECKING".
    IF NOT on_pad {
        SET art_name TO "launch_hold".
        SET title_txt TO "NOT PAD".
    } ELSE {
        IF committed {
            SET art_name TO "launch_commit".
            SET title_txt TO "COMMIT".
        } ELSE {
            IF armed {
                SET art_name TO "launch_go".
                SET title_txt TO "ARMED".
            } ELSE {
                LOCAL why_txt IS "".
                IF AOSO_LAUNCH_BOARD:HASKEY("reason") { SET why_txt TO AOSO_LAUNCH_BOARD["reason"]. }
                IF why_txt:CONTAINS("FAIL") {
                    SET art_name TO "launch_nogo".
                    SET title_txt TO "NO GO".
                } ELSE {
                    SET art_name TO "launch_hold".
                    SET title_txt TO "HOLD".
                }
            }
        }
    }
    aoso_ui2_go_arm_face(art_name).
    aoso_ui2_set_text(AOSO_UI2_GO_TITLE, "go_title", title_txt).

    LOCAL why_line IS "".
    IF AOSO_LAUNCH_BOARD:HASKEY("reason") { SET why_line TO AOSO_LAUNCH_BOARD["reason"]. }
    LOCAL cert_txt IS "".
    IF AOSO_LAUNCH_BOARD:HASKEY("cert") { SET cert_txt TO AOSO_LAUNCH_BOARD["cert"]. }
    IF cert_txt <> "" { SET why_line TO why_line + "   CERT " + cert_txt. }
    aoso_ui2_set_text(AOSO_UI2_GO_WHY, "go_why", why_line).

    LOCAL hint_txt IS "Browse the other pages. The ship stays on the pad until LAUNCH is green and you press it.".
    IF committed { SET hint_txt TO "Commit accepted. Ascent may take the stack.". }
    IF NOT on_pad { SET hint_txt TO "Launch commit is only required while the ship is PRELAUNCH.". }
    aoso_ui2_set_text(AOSO_UI2_GO_HINT, "go_hint", hint_txt).
}
