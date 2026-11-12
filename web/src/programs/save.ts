import type {Program} from "ollieos/src/types";
import {bytes_to_base64, call_capability, file_name_from_path, require_privileged_capability, write_error} from "./platform_helpers";

export default {
    name: "save",
    description: "Saves a file from OllieOS to the Files app.",
    usage_suffix: "file",
    arg_descriptions: {
        "Arguments:": {
            "file": "The file to save."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;

        if (args.length !== 1) {
            write_error(term, "Give exactly one file.");
            return 1;
        }

        const fs = kernel.get_fs();
        const file_path = fs.absolute(args[0]);
        if (!(await fs.exists(file_path))) {
            write_error(term, `No such file: ${args[0]}`);
            return 1;
        }

        const platform = await require_privileged_capability(kernel, term, "export_file", "Save a file to the Files app");
        if (!platform) {
            return 1;
        }

        const file_bytes = await fs.read_file(file_path, true) as Uint8Array;
        const result = await call_capability<{ exported: boolean }>(platform, term, "export_file", {
            name: file_name_from_path(file_path),
            data_base64: bytes_to_base64(file_bytes),
        });
        if (!result) {
            return 1;
        }

        term.writeln(result.exported ? "Saved." : "Save cancelled.");
        return result.exported ? 0 : 1;
    }
} as Program;
