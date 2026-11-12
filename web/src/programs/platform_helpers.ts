import type {Kernel, UserspaceKernel} from "ollieos/src/kernel";
import type {AbstractPlatformAPI, UserspacePlatformAPI} from "ollieos/src/kernel/platform";
import {ANSI, type AbstractTerminal} from "ollieos/src/kernel/term_ctl";

export const write_error = (term: AbstractTerminal, message: string): void => {
    term.writeln(`${ANSI.PREFABS.error}${message}${ANSI.STYLE.reset_all}`);
};

export const describe_error = (error: unknown): string => {
    return error instanceof Error ? error.message : String(error);
};

/**
 * Gets the userspace platform API if it supports the capability, otherwise explains why not.
 */
export const require_capability = (kernel: UserspaceKernel, term: AbstractTerminal, capability_name: string): UserspacePlatformAPI | null => {
    const platform = kernel.get_platform();
    if (!platform?.supports(capability_name)) {
        write_error(term, `This needs the "${capability_name}" platform capability, which isn't available here.`);
        return null;
    }

    return platform;
};

/**
 * Requests privileges (if not already privileged) and returns the full platform API for a privileged capability.
 */
export const require_privileged_capability = async (kernel: UserspaceKernel, term: AbstractTerminal, capability_name: string, reason: string): Promise<AbstractPlatformAPI | null> => {
    if (!kernel.get_platform()?.supports(capability_name)) {
        write_error(term, `This needs the "${capability_name}" platform capability, which isn't available here.`);
        return null;
    }

    const privileged_kernel = kernel.privileged ? kernel as unknown as Kernel : await kernel.request_privilege(reason);
    if (!privileged_kernel) {
        write_error(term, "Privilege request denied.");
        return null;
    }

    return privileged_kernel.get_platform();
};

/**
 * Calls a capability, writing any error to the terminal.
 * @returns The result, or null if the call failed.
 */
export const call_capability = async <Result>(platform: UserspacePlatformAPI | AbstractPlatformAPI, term: AbstractTerminal, capability_name: string, args?: unknown): Promise<Result | null> => {
    try {
        return await platform.call(capability_name, args) as Result;
    } catch (error) {
        write_error(term, describe_error(error));
        return null;
    }
};

export const bytes_to_base64 = (bytes: Uint8Array): string => {
    // chunked so large files don't overflow the argument limit of String.fromCharCode
    const chunk_size = 0x8000;
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += chunk_size) {
        binary += String.fromCharCode(...bytes.subarray(offset, offset + chunk_size));
    }
    return btoa(binary);
};

export const base64_to_bytes = (base64: string): Uint8Array => {
    return Uint8Array.from(atob(base64), character => character.charCodeAt(0));
};

export const file_name_from_path = (file_path: string): string => {
    return file_path.split("/").filter(part => part.length > 0).pop() ?? "file";
};
