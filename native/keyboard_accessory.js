// injected into every frame at document start. the native keyboard accessory bar calls
// window.__ollieosKeyboard.pressKey / setModifier, and this turns those into keyboard events
// xterm (and ollieos programs reading domEvent.code / key) understand
(function () {
    if (window.__ollieosKeyboard) {
        return;
    }

    const SPECIAL_KEYS = {
        escape: { key: "Escape", code: "Escape", keyCode: 27 },
        tab: { key: "Tab", code: "Tab", keyCode: 9 },
        up: { key: "ArrowUp", code: "ArrowUp", keyCode: 38 },
        down: { key: "ArrowDown", code: "ArrowDown", keyCode: 40 },
        left: { key: "ArrowLeft", code: "ArrowLeft", keyCode: 37 },
        right: { key: "ArrowRight", code: "ArrowRight", keyCode: 39 },
        home: { key: "Home", code: "Home", keyCode: 36 },
        end: { key: "End", code: "End", keyCode: 35 },
        pageup: { key: "PageUp", code: "PageUp", keyCode: 33 },
        pagedown: { key: "PageDown", code: "PageDown", keyCode: 34 },
        pipe: { key: "|", code: "Backslash", keyCode: 220, shiftKey: true },
        tilde: { key: "~", code: "Backquote", keyCode: 192, shiftKey: true },
        slash: { key: "/", code: "Slash", keyCode: 191 },
        dash: { key: "-", code: "Minus", keyCode: 189 },
    };

    // f1 - f12 use keyCodes 112 - 123
    for (let functionNumber = 1; functionNumber <= 12; functionNumber++) {
        SPECIAL_KEYS[`f${functionNumber}`] = {
            key: `F${functionNumber}`,
            code: `F${functionNumber}`,
            keyCode: 111 + functionNumber,
        };
    }

    const PUNCTUATION_CODES = {
        " ": ["Space", 32],
        "[": ["BracketLeft", 219],
        "]": ["BracketRight", 221],
        "\\": ["Backslash", 220],
        "/": ["Slash", 191],
        "-": ["Minus", 189],
        "=": ["Equal", 187],
        ".": ["Period", 190],
        ",": ["Comma", 188],
        ";": ["Semicolon", 186],
        "'": ["Quote", 222],
        "`": ["Backquote", 192],
    };

    // modifier state lives on the top window so the main page and the fsedit iframe share it
    let stateWindow = window;
    try {
        if (window.top && window.top.document) {
            stateWindow = window.top;
        }
    } catch (error) {
        stateWindow = window;
    }

    if (!stateWindow.__ollieosModifiers) {
        stateWindow.__ollieosModifiers = { ctrl: false };
    }

    function reportModifiers() {
        try {
            stateWindow.webkit.messageHandlers.ollieosKeyboard.postMessage({ ...stateWindow.__ollieosModifiers });
        } catch (error) {
            // message handler missing (e.g. running in a normal browser), nothing to report to
        }
    }

    function clearModifiers() {
        if (stateWindow.__ollieosModifiers.ctrl) {
            stateWindow.__ollieosModifiers.ctrl = false;
            reportModifiers();
        }
    }

    function describeCharacter(character) {
        const upper = character.toUpperCase();

        if (character.length === 1 && upper >= "A" && upper <= "Z") {
            return {
                key: character,
                code: `Key${upper}`,
                keyCode: upper.charCodeAt(0),
                shiftKey: character !== character.toLowerCase(),
            };
        }

        if (character >= "0" && character <= "9") {
            return { key: character, code: `Digit${character}`, keyCode: character.charCodeAt(0) };
        }

        const punctuation = PUNCTUATION_CODES[character];
        if (punctuation) {
            return { key: character, code: punctuation[0], keyCode: punctuation[1] };
        }

        return { key: character, code: "", keyCode: 0 };
    }

    // follow focus down into same-origin iframes (fsedit), falling back to the terminal textarea
    function findInputTarget(searchDocument) {
        const activeElement = searchDocument.activeElement;

        if (activeElement && activeElement.tagName === "IFRAME") {
            try {
                const innerTarget = findInputTarget(activeElement.contentDocument);
                if (innerTarget) {
                    return innerTarget;
                }
            } catch (error) {
                // cross origin iframe, can't reach inside
            }
        }

        if (activeElement && activeElement !== searchDocument.body && activeElement !== searchDocument.documentElement) {
            return activeElement;
        }

        return searchDocument.querySelector(".xterm-helper-textarea");
    }

    function dispatchKey(target, description, ctrlKey) {
        if (!target) {
            return;
        }

        for (const eventType of ["keydown", "keyup"]) {
            const keyboardEvent = new KeyboardEvent(eventType, {
                key: description.key,
                code: description.code,
                ctrlKey,
                shiftKey: Boolean(description.shiftKey),
                bubbles: true,
                cancelable: true,
                composed: true,
            });

            // keyCode / which can't be set through the constructor in webkit, and xterm switches on them
            Object.defineProperty(keyboardEvent, "keyCode", { get: () => description.keyCode });
            Object.defineProperty(keyboardEvent, "which", { get: () => description.keyCode });
            keyboardEvent.__ollieosSynthetic = true;

            target.dispatchEvent(keyboardEvent);
        }
    }

    function sendDescription(target, description) {
        dispatchKey(target, description, stateWindow.__ollieosModifiers.ctrl);
        clearModifiers();
    }

    // while ctrl is armed, the next character typed on the software keyboard becomes ctrl+character
    window.addEventListener("keydown", (keyboardEvent) => {
        if (keyboardEvent.__ollieosSynthetic || !stateWindow.__ollieosModifiers.ctrl) {
            return;
        }

        if (!keyboardEvent.key || keyboardEvent.key.length !== 1) {
            return;
        }

        keyboardEvent.preventDefault();
        keyboardEvent.stopImmediatePropagation();
        sendDescription(keyboardEvent.target, describeCharacter(keyboardEvent.key));
    }, true);

    // ios sometimes skips a usable keydown (keyCode 229 / Unidentified) and only fires beforeinput
    window.addEventListener("beforeinput", (inputEvent) => {
        if (!stateWindow.__ollieosModifiers.ctrl || inputEvent.inputType !== "insertText") {
            return;
        }

        if (!inputEvent.data || inputEvent.data.length !== 1) {
            return;
        }

        inputEvent.preventDefault();
        inputEvent.stopImmediatePropagation();
        sendDescription(inputEvent.target, describeCharacter(inputEvent.data));
    }, true);

    window.__ollieosKeyboard = {
        pressKey(keyName) {
            const description = SPECIAL_KEYS[keyName];
            if (description) {
                sendDescription(findInputTarget(document), description);
            }
        },

        setModifier(modifierName, active) {
            if (modifierName in stateWindow.__ollieosModifiers) {
                stateWindow.__ollieosModifiers[modifierName] = Boolean(active);
                reportModifiers();
            }
        },
    };

    // sync the native bar after a reload so it never shows a stale highlighted ctrl
    if (stateWindow === window) {
        reportModifiers();
    }
})();
