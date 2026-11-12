import {AbstractPlatformAPI, type PlatformCapability} from "ollieos/src/kernel/platform";

interface PlatformHandoff {
    token: string;
    capabilities: PlatformCapability[];
}

interface NativePlatformHandler {
    postMessage(message: unknown): Promise<unknown>;
}

declare global {
    interface Window {
        __ollieos_claim_platform?: () => PlatformHandoff | null;
        webkit?: {
            messageHandlers?: Record<string, NativePlatformHandler | undefined>;
        };
    }
}

const NATIVE_HANDLER_NAME = "ollieosPlatform";

/**
 * Talks to PlatformBridge in the app. The native side only accepts requests carrying the token handed over at boot,
 * which only this class holds, so programs have to go through the kernel's platform API (and its privilege checks).
 */
export class IOSPlatformAPI extends AbstractPlatformAPI {
    readonly #token: string;
    readonly #capabilities: PlatformCapability[];
    readonly #post_to_native: (message: unknown) => Promise<unknown>;

    /**
     * Claims the one-time handoff the app injects at document start. Must be called during boot, before any program runs.
     * @returns The platform API, or null when not running in the app (e.g. testing in a desktop browser).
     */
    static claim(): IOSPlatformAPI | null {
        const claim_handoff = window.__ollieos_claim_platform;
        const native_handler = window.webkit?.messageHandlers?.[NATIVE_HANDLER_NAME];
        if (!claim_handoff || !native_handler) {
            return null;
        }

        const handoff = claim_handoff();
        if (!handoff) {
            return null;
        }

        // bind now so patching the handler's prototype later can't intercept requests
        return new IOSPlatformAPI(handoff, native_handler.postMessage.bind(native_handler));
    }

    private constructor(handoff: PlatformHandoff, post_to_native: (message: unknown) => Promise<unknown>) {
        super();
        this.#token = handoff.token;
        this.#capabilities = handoff.capabilities.map(capability => ({...capability}));
        this.#post_to_native = post_to_native;
    }

    get_platform_name(): string {
        return "ios";
    }

    get_capabilities(): PlatformCapability[] {
        return this.#capabilities.map(capability => ({...capability}));
    }

    protected async _call_internal(capability_name: string, args: unknown): Promise<unknown> {
        return this.#post_to_native({
            token: this.#token,
            capability: capability_name,
            args: args ?? {},
        });
    }
}
