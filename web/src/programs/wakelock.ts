import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

export default {
    name: "wakelock",
    description: "Keeps the screen on while enabled.",
    usage_suffix: "[on | off]",
    arg_descriptions: {
        "Arguments:": {
            "on/off": "Enable or disable the wake lock. If omitted, the current state is shown."
        }
    },
    compat: "2.0.0",
    completion: async () => ["on", "off"],
    main: async (data) => {
        const {kernel, term, args} = data;

        if (args[0] !== undefined && args[0] !== "on" && args[0] !== "off") {
            write_error(term, "Use on or off.");
            return 1;
        }

        const platform = require_capability(kernel, term, "wake_lock");
        if (!platform) {
            return 1;
        }

        const wake_lock_args = args[0] === undefined ? {} : {enabled: args[0] === "on"};
        const state = await call_capability<{ enabled: boolean }>(platform, term, "wake_lock", wake_lock_args);
        if (!state) {
            return 1;
        }

        term.writeln(state.enabled ? "Screen will stay on." : "Screen can sleep normally.");
        return 0;
    }
} as Program;
