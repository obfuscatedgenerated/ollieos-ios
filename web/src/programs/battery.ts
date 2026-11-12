import type {Program} from "ollieos/src/types";
import {ANSI} from "ollieos/src/kernel/term_ctl";
import {call_capability, require_capability} from "./platform_helpers";

interface BatteryInfo {
    level: number | null;
    state: "unknown" | "unplugged" | "charging" | "full";
    low_power_mode: boolean;
}

export default {
    name: "battery",
    description: "Shows the battery level and charging state.",
    usage_suffix: "",
    arg_descriptions: {},
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term} = data;
        const {FG, STYLE} = ANSI;

        const platform = require_capability(kernel, term, "battery");
        if (!platform) {
            return 1;
        }

        const battery = await call_capability<BatteryInfo>(platform, term, "battery");
        if (!battery) {
            return 1;
        }

        if (battery.level === null) {
            term.writeln(`Battery level unknown (${battery.state})`);
        } else {
            const percentage = Math.round(battery.level * 100);
            const level_colour = percentage <= 20 ? FG.red : percentage <= 50 ? FG.yellow : FG.green;
            term.writeln(`Battery: ${level_colour}${STYLE.bold}${percentage}%${STYLE.reset_all} (${battery.state})`);
        }

        if (battery.low_power_mode) {
            term.writeln(`${FG.yellow}Low Power Mode is on${STYLE.reset_all}`);
        }

        return 0;
    }
} as Program;
