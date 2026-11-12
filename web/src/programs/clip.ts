import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, require_privileged_capability} from "./platform_helpers";

export default {
    name: "clip",
    description: "Reads or writes the clipboard.",
    usage_suffix: "[text]",
    arg_descriptions: {
        "Arguments:": {
            "text": "Text to copy. If omitted, the clipboard is printed (needs privileges)."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        if (args.length > 0) {
            const platform = require_capability(kernel, term, "clipboard_write");
            if (!platform) {
                return 1;
            }

            return await call_capability(platform, term, "clipboard_write", {text: args.join(" ")}) ? 0 : 1;
        }

        const platform = await require_privileged_capability(kernel, term, "clipboard_read", "Read the clipboard");
        if (!platform) {
            return 1;
        }

        const clipboard = await call_capability<{ text: string | null }>(platform, term, "clipboard_read");
        if (!clipboard) {
            return 1;
        }

        if (clipboard.text !== null) {
            term.writeln(clipboard.text);
        }
        return 0;
    }
} as Program;
