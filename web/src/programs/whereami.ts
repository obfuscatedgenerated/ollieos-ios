import type {Program} from "ollieos/src/types";
import {call_capability, require_privileged_capability} from "./platform_helpers";

interface LocationResult {
    latitude: number;
    longitude: number;
    altitude: number;
    horizontal_accuracy: number;
}

export default {
    name: "whereami",
    description: "Shows your current location.",
    usage_suffix: "",
    arg_descriptions: {},
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term} = data;

        const platform = await require_privileged_capability(kernel, term, "location", "Read your location");
        if (!platform) {
            return 1;
        }

        const location = await call_capability<LocationResult>(platform, term, "location");
        if (!location) {
            return 1;
        }

        term.writeln(`${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)} (±${Math.round(location.horizontal_accuracy)} m)`);
        term.writeln(`Altitude: ${Math.round(location.altitude)} m`);
        term.writeln(`https://www.openstreetmap.org/?mlat=${location.latitude}&mlon=${location.longitude}#map=16/${location.latitude}/${location.longitude}`);
        return 0;
    }
} as Program;
