import type {Program} from "ollieos/src/types";
import {ANSI} from "ollieos/src/kernel/term_ctl";
import {call_capability, require_privileged_capability} from "./platform_helpers";

interface Contact {
    given_name: string;
    family_name: string;
    organization: string;
    phone_numbers: string[];
    emails: string[];
}

export default {
    name: "contacts",
    description: "Lists or searches your contacts.",
    usage_suffix: "[search]",
    arg_descriptions: {
        "Arguments:": {
            "search": "Only show contacts whose name, number or email contains this."
        }
    },
    compat: "2.0.0",
    completion: async () => [],
    main: async (data) => {
        const {kernel, term, args} = data;
        const {FG, STYLE} = ANSI;

        const platform = await require_privileged_capability(kernel, term, "contacts", "Read your contacts");
        if (!platform) {
            return 1;
        }

        const result = await call_capability<{ contacts: Contact[] }>(platform, term, "contacts");
        if (!result) {
            return 1;
        }

        const search = args.join(" ").toLowerCase();
        const matching = result.contacts.filter(contact => {
            const haystack = [contact.given_name, contact.family_name, contact.organization, ...contact.phone_numbers, ...contact.emails].join(" ").toLowerCase();
            return haystack.includes(search);
        });

        if (matching.length === 0) {
            term.writeln("No contacts found.");
            return 1;
        }

        for (const contact of matching) {
            const name = `${contact.given_name} ${contact.family_name}`.trim() || contact.organization || "(no name)";
            term.writeln(`${FG.cyan}${STYLE.bold}${name}${STYLE.reset_all}`);
            for (const detail of [...contact.phone_numbers, ...contact.emails]) {
                term.writeln(`  ${detail}`);
            }
        }

        return 0;
    }
} as Program;
