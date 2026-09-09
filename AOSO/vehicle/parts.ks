// AOSO/vehicle/parts.ks
// The "part database": a model of the vessel's part hierarchy and staging
// stack so the rest of AOSO can reason about how the ship is actually built
// -- which engines are boosters that must be jettisoned once empty, which are
// the core/sustainer, and where the payload/lander sits at the top of the
// chain -- instead of treating every engine as one undifferentiated lump.
//
// Why this exists: vehicle/staging.ks used to only stage once *every* ignited
// engine had flamed out. On a vehicle with radial boosters the boosters run
// dry while the core is still burning, so that condition was never met, the
// spent boosters never got dropped, their near-empty tanks dragged
// vehicle/resources.ks's active-stage propellant reading below the abort
// threshold (and their dead weight/asymmetric drag made the ascent oscillate),
// and the ascent aborted. Understanding the staging stack lets AOSO shed the
// empty boosters and keep flying, which is the whole point of having a part
// database.
//
// Every suffix used here is a documented stock kOS Part suffix, per this
// project's "no invented suffixes" stance (see core/addons.ks):
//   PART:DECOUPLEDIN - the stage number in which the part is jettisoned, or -1
//                      if it is never decoupled. Stage numbers count DOWN as
//                      the flight proceeds, so a HIGHER DECOUPLEDIN separates
//                      EARLIER: the highest-numbered engine group is physically
//                      lowest in the stack (the boosters), and a -1 group is
//                      the never-jettisoned core/lander at the top of the chain.
//   PART:PARENT / PART:HASPARENT - walked to measure hierarchy depth from the
//                      root command part (Vessel:ROOTPART) down to the tips.
//   ENGINE:IGNITION / ENGINE:FLAMEOUT - live engine state used to tell a spent
//                      booster (ignited but flamed out) apart from one still
//                      burning. Engine is-a Part, so it also exposes DECOUPLEDIN.
// DECOUPLEDIN is compared only between engines (relative separation order),
// never against STAGE:NUMBER, so the model is immune to any off-by-one between
// a part's decouple-stage index and the live staging counter.
//
// The scanned summary is JSON-safe (only strings/numbers/lists/lexicons) and
// persisted to PART_DB_FILE so a reload/scene-change can inspect the last
// known stack without a rescan. The live decision helpers below instead read
// current engine state directly, since flameout/ignition change tick to tick.

GLOBAL AOSO_PARTS IS LEXICON().

// Builds AOSO_PARTS: the top of the chain (root part), hierarchy depth, and
// the staging stack expressed as engine "layers" ordered boosters-first
// (highest DECOUPLEDIN) down to the never-jettisoned core (-1) last. Called on
// boot and again after every staging event (vehicle/staging.ks) so the model
// always reflects the vessel as it is now.
FUNCTION aoso_parts_scan {
    LOCAL plist IS LIST().
    LIST PARTS IN plist.
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.

    // Top of the chain: the root command part everything hangs from.
    LOCAL root_title IS "".
    IF SHIP:ROOTPART:ISTYPE("Part") { SET root_title TO SHIP:ROOTPART:TITLE. }

    // Deepest part in the tree, measured by walking PARENT links up to the
    // root. Purely descriptive (how tall the stack of parts is), so it is
    // computed once here rather than on every guidance tick.
    LOCAL max_depth IS 0.
    FOR p IN plist {
        LOCAL depth IS 0.
        LOCAL cur IS p.
        UNTIL NOT cur:HASPARENT {
            SET cur TO cur:PARENT.
            SET depth TO depth + 1.
        }
        IF depth > max_depth { SET max_depth TO depth. }
    }

    // Group engines by the stage they are jettisoned in.
    LOCAL groups IS LEXICON().
    FOR e IN elist {
        LOCAL d IS e:DECOUPLEDIN.
        LOCAL key IS "" + d.
        IF NOT groups:HASKEY(key) {
            SET groups[key] TO LEXICON(
                "decoupled_in", d,
                "engines", 0,
                "engines_lit", 0,
                "engines_flamedout", 0
            ).
        }
        SET groups[key]["engines"] TO groups[key]["engines"] + 1.
        IF e:IGNITION {
            SET groups[key]["engines_lit"] TO groups[key]["engines_lit"] + 1.
            IF e:FLAMEOUT { SET groups[key]["engines_flamedout"] TO groups[key]["engines_flamedout"] + 1. }
        }
    }

    // Order layers boosters-first: descending DECOUPLEDIN puts the earliest-
    // separated group (highest number) first and the never-decoupled core
    // (-1, the lowest possible value) last, no special-casing needed. kOS's
    // LIST has no built-in sort; there are only a handful of distinct groups,
    // so a simple selection sort is more than fast enough.
    LOCAL unsorted IS LIST().
    FOR k IN groups:KEYS { unsorted:ADD(groups[k]). }
    LOCAL layers IS LIST().
    UNTIL unsorted:LENGTH = 0 {
        LOCAL best_idx IS 0.
        FOR i IN RANGE(0, unsorted:LENGTH) {
            IF unsorted[i]["decoupled_in"] > unsorted[best_idx]["decoupled_in"] { SET best_idx TO i. }
        }
        layers:ADD(unsorted[best_idx]).
        unsorted:REMOVE(best_idx).
    }

    // Tag each layer with a human-readable role: the never-decoupled group is
    // the CORE (sustainer + payload/lander at the top of the chain); the first
    // (highest DECOUPLEDIN) decoupled group is the BOOSTER set dropped first;
    // any decoupled groups between are intermediate STAGEs.
    FOR i IN RANGE(0, layers:LENGTH) {
        LOCAL d IS layers[i]["decoupled_in"].
        LOCAL role IS "STAGE".
        IF d < 0 {
            SET role TO "CORE".
        } ELSE IF i = 0 {
            SET role TO "BOOSTER".
        }
        SET layers[i]["role"] TO role.
    }

    SET AOSO_PARTS TO LEXICON(
        "root", root_title,
        "part_count", plist:LENGTH,
        "engine_count", elist:LENGTH,
        "max_depth", max_depth,
        "layers", layers,
        "scanned_at", TIME:SECONDS
    ).

    aoso_log_info("PARTS", "Hierarchy: root='" + root_title + "' depth=" + max_depth +
        " engines=" + elist:LENGTH + " layers=" + layers:LENGTH + ".").

    aoso_parts_save().
    RETURN AOSO_PARTS.
}

FUNCTION aoso_parts_get {
    PARAMETER key.
    PARAMETER default_value IS 0.
    IF AOSO_PARTS:HASKEY(key) { RETURN AOSO_PARTS[key]. }
    RETURN default_value.
}

FUNCTION aoso_parts_save {
    aoso_json_write(AOSO_CONST["PART_DB_FILE"], AOSO_PARTS).
}

FUNCTION aoso_parts_load {
    LOCAL loaded IS aoso_json_read(AOSO_CONST["PART_DB_FILE"], LEXICON()).
    IF loaded:ISTYPE("Lexicon") AND loaded:HASKEY("scanned_at") {
        SET AOSO_PARTS TO loaded.
        RETURN TRUE.
    }
    RETURN FALSE.
}

// --- Live decision helpers (read current engine state, not the snapshot) ---

// TRUE if any engine is ignited and still producing (not flamed out). An
// active engine at zero throttle still counts as ignited/not-flamed-out, which
// is the intended reading: it can produce thrust the moment the throttle opens.
FUNCTION aoso_parts_has_burning_engine {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    FOR e IN elist {
        IF e:IGNITION AND NOT e:FLAMEOUT { RETURN TRUE. }
    }
    RETURN FALSE.
}

// TRUE if any engine on the vessel has not been ignited yet -- i.e. a
// lower/upper-stage engine that a future staging event will light. Used to
// decide there is still a thrust path forward before ever declaring a fuel
// abort.
FUNCTION aoso_parts_has_unignited_engine {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.
    FOR e IN elist {
        IF NOT e:IGNITION { RETURN TRUE. }
    }
    RETURN FALSE.
}

// TRUE when there is a spent booster group the very next staging action can
// jettison without discarding any still-burning engine -- i.e. empty boosters
// ready to drop while the core keeps thrusting.
//
// Boosters and the core are all ignited at liftoff; the boosters have a HIGHER
// DECOUPLEDIN (separated earlier) than the core. So if the soonest-separated
// spent (flamed-out) engine separates strictly before the soonest-separated
// still-burning engine, staging drops only spent boosters and leaves the core
// running. A -1 (never-decoupled) engine is treated as separating last, so a
// spent core engine is never mistaken for a droppable booster.
FUNCTION aoso_parts_boosters_ready_to_jettison {
    LOCAL elist IS LIST().
    LIST ENGINES IN elist.

    LOCAL have_spent IS FALSE.
    LOCAL have_burning IS FALSE.
    LOCAL spent_drop IS -1.    // soonest separation (max DECOUPLEDIN) among spent engines
    LOCAL burn_drop IS -1.     // soonest separation among still-burning engines
    FOR e IN elist {
        IF e:IGNITION {
            LOCAL d IS e:DECOUPLEDIN.
            IF e:FLAMEOUT {
                SET have_spent TO TRUE.
                IF d > spent_drop { SET spent_drop TO d. }
            } ELSE {
                SET have_burning TO TRUE.
                IF d > burn_drop { SET burn_drop TO d. }
            }
        }
    }

    IF NOT have_spent { RETURN FALSE. }
    IF NOT have_burning { RETURN FALSE. }   // full flameout is staging.ks's other path
    IF spent_drop < 0 { RETURN FALSE. }     // spent engines aren't on a decoupled stage
    RETURN spent_drop > burn_drop.          // boosters separate before the core does
}

// TRUE if the vehicle currently has, or can stage to obtain, engine thrust:
//   - an engine is ignited and still burning now, OR
//   - spent boosters can be jettisoned so the core keeps burning, OR
//   - there is an un-ignited engine a lower stage can still light.
// vehicle/resources.ks uses this so a low active-stage propellant reading only
// aborts once thrust is genuinely unrecoverable -- mid-ascent it means "stage",
// not "abort".
FUNCTION aoso_parts_thrust_recoverable {
    IF aoso_parts_has_burning_engine() { RETURN TRUE. }
    IF STAGE:NUMBER <= 0 { RETURN FALSE. }   // nothing left to stage to
    IF aoso_parts_boosters_ready_to_jettison() { RETURN TRUE. }
    IF aoso_parts_has_unignited_engine() { RETURN TRUE. }
    RETURN FALSE.
}
