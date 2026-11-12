// builds and boots the kernel for the ios app. mirrors upstream's os_loader, with the app's own programs registered
// and the ios platform api passed to the kernel
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { ImageAddon } from "@xterm/addon-image";

import {ANSI, NEWLINE} from "ollieos/src/kernel/term_ctl";
import {Kernel} from "ollieos/src/kernel";
import {ProgramRegistry} from "ollieos/src/kernel/prog_registry";
import * as programs from "ollieos/src/programs/@ALL";
import {SoundRegistry} from "ollieos/src/kernel/sfx_registry";
import type {AbstractFileSystem} from "ollieos/src/kernel/filesystem";
import {LocalStorageFS} from "ollieos/src/fs_impl/localstorage";
import {OPFSFileSystem} from "ollieos/src/fs_impl/opfs";
import {initial_fs_setup} from "ollieos/src/initial_fs_setup";
import {DOMWindowManager} from "ollieos/src/window_impl/dom";
import {PorterBridgeNetworkManager} from "ollieos/src/network_impl/porter";
import {XTermTerminal} from "ollieos/src/term_impl/xterm";
import type {Program} from "ollieos/src/types";
import "ollieos/src/load_global_externals";

import {IOSPlatformAPI} from "./ios_platform";
import * as ios_programs from "./programs/@ALL";
import {IOS_PRIVILEGE_AGENT_NAME} from "./programs/ios_privilege_agent";

const PRIVILEGE_AGENT_PATH = "/sys/privilege_agent";

export const boot_ios = async (on_init_spawned?: (kernel: Kernel) => Promise<void>) => {
    // claim the native bridge before anything else can run
    const platform = IOSPlatformAPI.claim();

    // register upstream programs, then the app's own
    const prog_reg = new ProgramRegistry();
    for (const prog of [...Object.values(programs), ...Object.values(ios_programs)]) {
        await prog_reg.registerProgram({
            program: prog as Program<unknown>,
            built_in: true,
        });
    }

    const sfx_reg = new SoundRegistry();
    sfx_reg.register_file("reader_on", "public/sfx/reader_on.mp3");
    sfx_reg.register_file("reader_off", "public/sfx/reader_off.mp3");

    // try opfs but use localstorage if not available, or already in use
    let fs: AbstractFileSystem;
    if (!localStorage.getItem("fs") && navigator.storage && "getDirectory" in navigator.storage) {
        fs = new OPFSFileSystem();
    } else {
        fs = new LocalStorageFS();
    }

    if (!(await fs.is_ready())) {
        await new Promise<void>((resolve) => {
            const interval = setInterval(async () => {
                if (await fs.is_ready()) {
                    clearInterval(interval);
                    resolve();
                }
            }, 10);
        });
    }

    // fresh installs use face id for privilege requests when available (existing choices are left alone)
    const fresh_install = !(await fs.exists(PRIVILEGE_AGENT_PATH));

    await initial_fs_setup(fs);

    if (fresh_install && platform?.supports("authenticate")) {
        await fs.write_file(PRIVILEGE_AGENT_PATH, IOS_PRIVILEGE_AGENT_NAME);
    }

    const wm = new DOMWindowManager();
    const net_manager = new PorterBridgeNetworkManager();

    const term = new XTermTerminal({
        screenReaderMode: false,
        cursorBlink: true,
    });

    const fit = new FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon());
    term.loadAddon(new ImageAddon());

    const render = <HTMLElement>document.querySelector("#terminal");
    term.open(render);
    fit.fit();

    if (window.innerWidth < 600) {
        const wrapped = term.word_wrap(`${ANSI.BG.red + ANSI.FG.white}Warning: The screen that the terminal is running on is rather small!${NEWLINE + NEWLINE}Some programs may not display correctly, consider using a larger screen such as a computer or tablet.${NEWLINE + NEWLINE}An alternative interface is in the works. You can also use the command "legacy" to view the old (outdated) site.${ANSI.STYLE.reset_all}`, term.cols);
        term.writeln(wrapped);
    }

    // disable F1 help
    window.addEventListener("keydown", (keyboard_event) => {
        if (keyboard_event.code === "F1") {
            keyboard_event.preventDefault();
        }
    });

    window.addEventListener("resize", () => {
        fit.fit();
    });

    const kernel = new Kernel(term, fs, prog_reg, sfx_reg, wm, net_manager, platform ?? undefined);
    kernel.set_env_info(document.body.dataset.version, "ios");

    return await kernel.boot(on_init_spawned);
};
