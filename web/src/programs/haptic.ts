import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

const HAPTIC_STYLES = ["light", "medium", "heavy", "soft", "rigid", "success", "warning", "error", "selection"];

export default {
    name: "haptic",
    description: "Plays a haptic (vibration) pattern.",
    usage_suffix: "[style]",
    arg_descriptions: {
        "Arguments:": {
            "style": `One of ${HAPTIC_STYLES.join(", ")}. Defaults to medium.`
        }
    },
    compat: "2.0.0",
    completion: async () => HAPTIC_STYLES,
    main: async (data) => {
        const {kernel, term, args} = data;

        const style = args[0] ?? "medium";
        if (!HAPTIC_STYLES.includes(style)) {
            write_error(term, `Unknown style "${style}". Use one of: ${HAPTIC_STYLES.join(", ")}`);
            return 1;
        }

        const platform = require_capability(kernel, term, "haptic");
        if (!platform) {
            return 1;
        }

        return await call_capability(platform, term, "haptic", {style}) ? 0 : 1;
    }
} as Program;
