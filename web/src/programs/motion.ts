import type {Program} from "ollieos/src/types";
import {call_capability, require_capability} from "./platform_helpers";

interface Vector {
    x: number;
    y: number;
    z: number;
}

interface MotionSample {
    attitude: { roll: number; pitch: number; yaw: number };
    gravity: Vector;
    user_acceleration: Vector;
    rotation_rate: Vector;
}

const to_degrees = (radians: number): string => `${(radians * 180 / Math.PI).toFixed(1)}°`;
const format_vector = (vector: Vector): string => `x ${vector.x.toFixed(3)}  y ${vector.y.toFixed(3)}  z ${vector.z.toFixed(3)}`;

export default {
    name: "motion",
    description: "Reads the motion sensors once.",
    usage_suffix: "",
    arg_descriptions: {},
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term} = data;

        const platform = require_capability(kernel, term, "motion");
        if (!platform) {
            return 1;
        }

        const sample = await call_capability<MotionSample>(platform, term, "motion");
        if (!sample) {
            return 1;
        }

        term.writeln(`Attitude      roll ${to_degrees(sample.attitude.roll)}  pitch ${to_degrees(sample.attitude.pitch)}  yaw ${to_degrees(sample.attitude.yaw)}`);
        term.writeln(`Gravity       ${format_vector(sample.gravity)}`);
        term.writeln(`Acceleration  ${format_vector(sample.user_acceleration)}`);
        term.writeln(`Rotation      ${format_vector(sample.rotation_rate)}`);
        return 0;
    }
} as Program;
