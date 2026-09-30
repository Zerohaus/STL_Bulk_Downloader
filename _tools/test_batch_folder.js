// Auto-batching names each batch folder as a SIBLING of the creator folder
// ("CobraMode_2"), never a child ("CobraMode\2"). The uploader reads every
// top-level folder inside a creator folder as a model, so a nested batch folder
// full of raw model_*.json dumps breaks the upload of its parent.
//
//   node _tools/test_batch_folder.js
const assert = require("assert");
const path = require("path");

// mirrors getNextBatchFolder() in electron/main.js, with the disk read faked
function nextBatch(current, existingDirs) {
    const cleaned = current.replace(/[\\/]+$/, "");
    const parent = path.dirname(cleaned);
    const stem = path.basename(cleaned).replace(/_\d+$/, "");
    const pattern = new RegExp("^" + stem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "_(\\d+)$");
    const nums = existingDirs
        .map((n) => { const m = pattern.exec(n); return m ? parseInt(m[1], 10) : null; })
        .filter((n) => Number.isFinite(n))
        .sort((a, b) => a - b);
    const next = nums.length ? nums[nums.length - 1] + 1 : 1;
    return { stem, next, nextPath: path.join(parent, `${stem}_${next}`) };
}

const cases = [
    // a fresh creator folder starts the series at _1 -- including the FIRST
    // batch, so folder N always holds batch N
    ["I:\\Bulk Downloader\\CreepyHero", [], "I:\\Bulk Downloader\\CreepyHero_1"],
    // continues from what is on disk rather than a session counter
    ["I:\\Bulk Downloader\\CobraMode", ["CobraMode_1", "CobraMode_2", "CobraMode_8"],
     "I:\\Bulk Downloader\\CobraMode_9"],
    // pointing at a batch folder continues the creator's series, it does not
    // start a nested "CobraMode_3_1" one
    ["I:\\Bulk Downloader\\CobraMode_3", ["CobraMode_1", "CobraMode_2", "CobraMode_3"],
     "I:\\Bulk Downloader\\CobraMode_4"],
    // another creator's folders must not be counted
    ["I:\\Bulk Downloader\\CreepyHero", ["CobraMode_5", "TinyFurniture_2"],
     "I:\\Bulk Downloader\\CreepyHero_1"],
    // _originals siblings are not batches
    ["I:\\Bulk Downloader\\CobraMode", ["CobraMode_1", "CobraMode_1_originals", "CobraMode_originals"],
     "I:\\Bulk Downloader\\CobraMode_2"],
    // a trailing slash must not swallow the folder name
    ["I:\\Bulk Downloader\\CobraMode\\", ["CobraMode_4"], "I:\\Bulk Downloader\\CobraMode_5"],
    // a creator whose name ends in digits keeps them: "Vol2" is not "Vol" + 2
    ["I:\\Bulk Downloader\\Vol2", ["Vol2_1"], "I:\\Bulk Downloader\\Vol2_2"],
    // gaps do not cause a re-use of an existing folder
    ["I:\\Bulk Downloader\\CobraMode", ["CobraMode_1", "CobraMode_7"],
     "I:\\Bulk Downloader\\CobraMode_8"]
];

let pass = 0;
for (const [current, dirs, expected] of cases) {
    const got = nextBatch(current, dirs).nextPath;
    const ok = got === expected;
    console.log("  " + (ok ? "PASS" : "FAIL") + "  " + current.padEnd(42) + " -> " + got);
    if (!ok) console.log("        expected " + expected);
    assert.strictEqual(got, expected);
    pass += 1;
}

// the shape itself: a batch folder is never inside the creator folder
const nested = nextBatch("I:\\Bulk Downloader\\CobraMode", []).nextPath;
assert.ok(!/CobraMode[\\/]\d/.test(nested), "batch folder must not nest inside the creator folder");
console.log("  PASS  batch folder is a sibling, never a child");
pass += 1;

console.log("\n%d/%d passed", pass, cases.length + 1);
