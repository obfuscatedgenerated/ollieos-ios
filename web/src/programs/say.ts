import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

export default {
    name: "say",
    description: "Speaks text aloud.",
    usage_suffix: "[-r rate] [-l language] text",
    arg_descriptions: {
        "Flags:": {
            "-r": "Speaking rate, where 1 is normal speed (e.g. 0.5, 1.5).",
            "-l": "Voice language code (e.g. en-GB, fr-FR)."
        },
        "Arguments:": {
            "text": "The text to speak."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        const remaining_args = [...args];
        let rate: number | undefined;
        let language: string | undefined;

        while (remaining_args[0] === "-r" || remaining_args[0] === "-l") {
            const flag = remaining_args.shift();
            const value = remaining_args.shift();
            if (value === undefined) {
                write_error(term, `Missing value for ${flag}`);
                return 1;
            }

            if (flag === "-r") {
                rate = parseFloat(value);
                if (isNaN(rate) || rate <= 0) {
                    write_error(term, "Rate must be a positive number.");
                    return 1;
                }
            } else {
                language = value;
            }
        }

        const text = remaining_args.join(" ");
        if (!text) {
            write_error(term, "Nothing to say.");
            return 1;
        }

        const platform = require_capability(kernel, term, "say");
        if (!platform) {
            return 1;
        }

        return await call_capability(platform, term, "say", {text, rate, language}) ? 0 : 1;
    }
} as Program;
