// app entry, replacing upstream's src/index.ts. the boot screen handling mirrors upstream, but the os is booted by
// ios_loader.ts, which builds the kernel itself (like ollieos_node does)
import "@xterm/xterm/css/xterm.css";

const boot_screen = document.getElementById("boot_screen");

// insert boot loader bars depending on screen size (each bar should take 1/15th of the loader's width, ignoring margins)
const loader = document.getElementById("boot_loader") as HTMLDivElement;
const bar_count = Math.floor(loader.getBoundingClientRect().width / 15);
for (let bar_index = 0; bar_index < bar_count; bar_index++) {
    const bar = document.createElement("div");
    bar.classList.add("boot_loader_bar");

    // make first 3 bars visible
    if (bar_index < 3) {
        bar.style.visibility = "visible";
    }

    loader.appendChild(bar);
}

// animate the loader bars (3 block width, scrolling across the loader with wraparound)
let tail_bar_index = 0;
const loader_interval = setInterval(() => {
    const bars = document.querySelectorAll(".boot_loader_bar") as NodeListOf<HTMLDivElement>;

    bars[tail_bar_index].style.visibility = "hidden";
    bars[(tail_bar_index + 3) % bars.length].style.visibility = "visible";
    tail_bar_index = (tail_bar_index + 1) % bars.length;

    if (boot_screen.style.opacity === "0") {
        clearInterval(loader_interval);
    }
}, 100);

const skip_intro = localStorage.getItem("nointro") === "true";

async function init_spawned() {
    boot_screen.style.opacity = "0";

    if (skip_intro) {
        boot_screen.style.display = "none";
        return;
    }

    // after faded, keep it like that for 1s before shrinking it to 0% height
    setTimeout(() => {
        boot_screen.style.height = "0";
        setTimeout(() => {
            boot_screen.style.display = "none";
        }, 500);
    }, 1000);
}

const main = async () => {
    // lazy load the loader so the boot screen shows while the os code is parsed
    const { boot_ios } = await import(
        /* webpackChunkName: "os" */
        "./ios_loader"
    );

    const success = await boot_ios(init_spawned);
    if (!success) {
        boot_screen.style.display = "none";
    }
};

if (skip_intro) {
    boot_screen.style.transition = "none";
    main();
} else {
    setTimeout(main, 3000);
}
