import type {Program} from "ollieos/src/types";
import {bytes_to_base64, call_capability, file_name_from_path, require_capability, write_error} from "./platform_helpers";

export default {
    name: "share",
    description: "Opens the share sheet for a file, text or a link.",
    usage_suffix: "file | -t text | -u url",
    arg_descriptions: {
        "Flags:": {
            "-t": "Share the following text instead of a file.",
            "-u": "Share a link instead of a file."
        },
        "Arguments:": {
            "file": "The file to share."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        if (args.length === 0) {
            write_error(term, "Give a file, -t text or -u url.");
            return 1;
        }

        const platform = require_capability(kernel, term, "share");
        if (!platform) {
            return 1;
        }

        let share_args: Record<string, string>;

        if (args[0] === "-t") {
            share_args = {text: args.slice(1).join(" ")};
        } else if (args[0] === "-u") {
            if (!args[1]) {
                write_error(term, "Missing url.");
                return 1;
            }
            share_args = {url: args[1]};
        } else {
            const fs = kernel.get_fs();
            const file_path = fs.absolute(args[0]);
            if (!(await fs.exists(file_path))) {
                write_error(term, `No such file: ${args[0]}`);
                return 1;
            }

            const file_bytes = await fs.read_file(file_path, true) as Uint8Array;
            share_args = {
                file_name: file_name_from_path(file_path),
                file_base64: bytes_to_base64(file_bytes),
            };
        }

        const result = await call_capability<{ completed: boolean }>(platform, term, "share", share_args);
        if (!result) {
            return 1;
        }

        if (!result.completed) {
            term.writeln("Share cancelled.");
        }
        return 0;
    }
} as Program;
