import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

export default {
    name: "notify",
    description: "Sends a notification, now or after a delay.",
    usage_suffix: "[-d seconds] [-t title] message",
    arg_descriptions: {
        "Flags:": {
            "-d": "Delay in seconds before the notification is shown. Works even if the app is closed.",
            "-t": "Notification title. Defaults to OllieOS."
        },
        "Arguments:": {
            "message": "The notification text."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        const remaining_args = [...args];
        let delay_seconds: number | undefined;
        let title: string | undefined;

        while (remaining_args[0] === "-d" || remaining_args[0] === "-t") {
            const flag = remaining_args.shift();
            const value = remaining_args.shift();
            if (value === undefined) {
                write_error(term, `Missing value for ${flag}`);
                return 1;
            }

            if (flag === "-d") {
                delay_seconds = parseFloat(value);
                if (isNaN(delay_seconds) || delay_seconds < 0) {
                    write_error(term, "Delay must be a number of seconds.");
                    return 1;
                }
            } else {
                title = value;
            }
        }

        const body = remaining_args.join(" ");
        if (!body) {
            write_error(term, "Missing message.");
            return 1;
        }

        const platform = require_capability(kernel, term, "notify");
        if (!platform) {
            return 1;
        }

        const result = await call_capability(platform, term, "notify", {title, body, delay_seconds});
        if (!result) {
            return 1;
        }

        if (delay_seconds && delay_seconds >= 1) {
            term.writeln(`Notification scheduled in ${delay_seconds}s.`);
        }
        return 0;
    }
} as Program;
