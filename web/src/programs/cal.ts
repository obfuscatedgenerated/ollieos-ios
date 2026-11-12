import type {Program} from "ollieos/src/types";
import {ANSI} from "ollieos/src/kernel/term_ctl";
import {call_capability, require_privileged_capability, write_error} from "./platform_helpers";

interface CalendarEvent {
    title: string | null;
    start: string;
    end: string;
    all_day: boolean;
    location: string | null;
    calendar: string | null;
}

const format_event_time = (event: CalendarEvent): string => {
    const start = new Date(event.start);
    const day = start.toLocaleDateString(undefined, {weekday: "short", day: "numeric", month: "short"});
    if (event.all_day) {
        return `${day}, all day`;
    }

    const time_options: Intl.DateTimeFormatOptions = {hour: "2-digit", minute: "2-digit"};
    return `${day}, ${start.toLocaleTimeString(undefined, time_options)}-${new Date(event.end).toLocaleTimeString(undefined, time_options)}`;
};

export default {
    name: "cal",
    description: "Shows upcoming calendar events, or adds one.",
    usage_suffix: "[days] | add title start [end]",
    arg_descriptions: {
        "Arguments:": {
            "days": "How many days ahead to show. Defaults to 7.",
            "add": "Add an event. start and end are dates like 2026-11-20T14:00 (end defaults to an hour later)."
        }
    },
    compat: "2.0.0",
    completion: async () => ["add"],
    main: async (data) => {
        const {kernel, term, args} = data;
        const {FG, STYLE} = ANSI;

        if (args[0] === "add") {
            const [, title, start_text, end_text] = args;
            const start = start_text ? new Date(start_text) : null;
            const end = end_text ? new Date(end_text) : null;
            if (!title || !start || isNaN(start.getTime()) || (end && isNaN(end.getTime()))) {
                write_error(term, "Usage: cal add title start [end], with dates like 2026-11-20T14:00");
                return 1;
            }

            const platform = await require_privileged_capability(kernel, term, "calendar_add", `Add "${title}" to your calendar`);
            if (!platform) {
                return 1;
            }

            const result = await call_capability(platform, term, "calendar_add", {
                title,
                start: start.toISOString(),
                end: end?.toISOString(),
            });
            if (!result) {
                return 1;
            }

            term.writeln(`Added "${title}".`);
            return 0;
        }

        const days = args[0] ? parseInt(args[0], 10) : 7;
        if (isNaN(days) || days < 1) {
            write_error(term, "Days must be a positive number.");
            return 1;
        }

        const platform = await require_privileged_capability(kernel, term, "calendar_events", "Read your calendar");
        if (!platform) {
            return 1;
        }

        const result = await call_capability<{ events: CalendarEvent[] }>(platform, term, "calendar_events", {days});
        if (!result) {
            return 1;
        }

        if (result.events.length === 0) {
            term.writeln(`Nothing in the next ${days} day${days === 1 ? "" : "s"}.`);
            return 0;
        }

        for (const event of result.events) {
            const location = event.location ? ` ${FG.gray}@ ${event.location}${STYLE.reset_all}` : "";
            term.writeln(`${FG.cyan}${format_event_time(event)}${STYLE.reset_all}  ${STYLE.bold}${event.title ?? "(untitled)"}${STYLE.reset_all}${location}`);
        }

        return 0;
    }
} as Program;
