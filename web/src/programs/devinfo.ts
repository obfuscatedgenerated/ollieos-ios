import type {Program} from "ollieos/src/types";
import {ANSI} from "ollieos/src/lib/ansi";
import {call_capability, require_capability} from "./platform_helpers";

interface DeviceInfo {
    model_identifier: string;
    model: string;
    system_name: string;
    system_version: string;
    idiom: "phone" | "pad";
    screen: { width: number; height: number; scale: number };
    locale: string;
    time_zone: string;
    app_version: string | null;
}

interface NetworkPath {
    status: "satisfied" | "unsatisfied" | "requires_connection";
    interfaces: string[];
    expensive: boolean;
    constrained: boolean;
}

export default {
    name: "devinfo",
    description: "Shows information about this device.",
    usage_suffix: "",
    arg_descriptions: {},
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term} = data;
        const {FG, STYLE} = ANSI;

        const platform = require_capability(kernel, term, "device_info");
        if (!platform) {
            return 1;
        }

        const device = await call_capability<DeviceInfo>(platform, term, "device_info");
        if (!device) {
            return 1;
        }

        const write_row = (label: string, value: string) => {
            term.writeln(`${FG.cyan}${STYLE.bold}${label.padEnd(14)}${STYLE.reset_all}${value}`);
        };

        write_row("Device", `${device.model} (${device.model_identifier})`);
        write_row("System", `${device.system_name} ${device.system_version}`);
        write_row("Screen", `${device.screen.width}x${device.screen.height} pt @${device.screen.scale}x`);
        write_row("Locale", `${device.locale}, ${device.time_zone}`);
        if (device.app_version) {
            write_row("App", device.app_version);
        }

        // optional extras, skipped quietly if the platform doesn't have them
        if (platform.supports("thermal_state")) {
            const thermal = await call_capability<{ state: string }>(platform, term, "thermal_state");
            if (thermal) {
                write_row("Thermal", thermal.state);
            }
        }

        if (platform.supports("network_path")) {
            const network = await call_capability<NetworkPath>(platform, term, "network_path");
            if (network) {
                const flags = [network.expensive ? "expensive" : "", network.constrained ? "low data mode" : ""].filter(flag => flag);
                const interfaces = network.interfaces.length > 0 ? network.interfaces.join(", ") : "none";
                write_row("Network", `${network.status}, ${interfaces}${flags.length > 0 ? ` (${flags.join(", ")})` : ""}`);
            }
        }

        if (platform.supports("hardware_keyboard")) {
            const keyboard = await call_capability<{ connected: boolean }>(platform, term, "hardware_keyboard");
            if (keyboard) {
                write_row("Keyboard", keyboard.connected ? "hardware keyboard connected" : "software keyboard");
            }
        }

        return 0;
    }
} as Program;
