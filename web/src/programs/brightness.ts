import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

export default {
    name: "brightness",
    description: "Shows or sets the screen brightness.",
    usage_suffix: "[level]",
    arg_descriptions: {
        "Arguments:": {
            "level": "Brightness from 0 to 100. If omitted, the current brightness is shown."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        const platform = require_capability(kernel, term, "brightness");
        if (!platform) {
            return 1;
        }

        let brightness_args = {};
        if (args[0] !== undefined) {
            const percentage = parseInt(args[0], 10);
            if (isNaN(percentage) || percentage < 0 || percentage > 100) {
                write_error(term, "Level must be from 0 to 100.");
                return 1;
            }
            brightness_args = {level: percentage / 100};
        }

        const brightness = await call_capability<{ level: number }>(platform, term, "brightness", brightness_args);
        if (!brightness) {
            return 1;
        }

        term.writeln(`Brightness: ${Math.round(brightness.level * 100)}%`);
        return 0;
    }
} as Program;
