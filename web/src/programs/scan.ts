import type {Program} from "ollieos/src/types";
import {call_capability, require_privileged_capability} from "./platform_helpers";

interface ScanResult {
    cancelled: boolean;
    text?: string;
    type?: string | null;
}

export default {
    name: "scan",
    description: "Scans a QR code or barcode with the camera and prints its contents.",
    usage_suffix: "",
    arg_descriptions: {},
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term} = data;

        const platform = await require_privileged_capability(kernel, term, "scan_code", "Use the camera to scan a code");
        if (!platform) {
            return 1;
        }

        const result = await call_capability<ScanResult>(platform, term, "scan_code");
        if (!result) {
            return 1;
        }

        if (result.cancelled) {
            term.writeln("Scan cancelled.");
            return 1;
        }

        term.writeln(result.text);
        return 0;
    }
} as Program;
