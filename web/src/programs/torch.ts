import type {Program} from "ollieos/src/types";
import {call_capability, require_capability, write_error} from "./platform_helpers";

interface TorchState {
    on: boolean;
    level: number;
}

export default {
    name: "torch",
    description: "Controls the flashlight.",
    usage_suffix: "[on | off | toggle | level]",
    arg_descriptions: {
        "Arguments:": {
            "on/off/toggle": "Turn the torch on, off, or flip it. Defaults to toggle.",
            "level": "Brightness from 1 to 100, which also turns it on."
        }
    },
    compat: "2.0.0",
    completion: async () => ["on", "off", "toggle"],
    main: async (data) => {
        const {kernel, term, args} = data;

        const platform = require_capability(kernel, term, "torch");
        if (!platform) {
            return 1;
        }

        const action = args[0] ?? "toggle";
        let torch_args: { on: boolean; level?: number };

        if (action === "on" || action === "off") {
            torch_args = {on: action === "on"};
        } else if (action === "toggle") {
            const current = await call_capability<TorchState>(platform, term, "torch");
            if (!current) {
                return 1;
            }
            torch_args = {on: !current.on};
        } else {
            const percentage = parseInt(action, 10);
            if (isNaN(percentage) || percentage < 1 || percentage > 100) {
                write_error(term, "Use on, off, toggle or a level from 1 to 100.");
                return 1;
            }
            torch_args = {on: true, level: percentage / 100};
        }

        const state = await call_capability<TorchState>(platform, term, "torch", torch_args);
        if (!state) {
            return 1;
        }

        term.writeln(state.on ? `Torch on (${Math.round(state.level * 100)}%)` : "Torch off");
        return 0;
    }
} as Program;
