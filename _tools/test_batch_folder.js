// The renderer has to work out the base folder before asking main.js for the
// next batch number. Getting this wrong puts a download in the wrong place, so
// the cases are pinned here.
//
//   node _tools/test_batch_folder.js
const assert = require("assert");

function baseFor(current) {
    return /[\\/]\d+$/.test(current) ? current.replace(/[\\/]\d+$/, "") : current;
}

const cases = [
    // already inside a numbered batch folder -> step back up to the parent
    ["I:\\Bulk Downloader\\CobraMode\\6", "I:\\Bulk Downloader\\CobraMode"],
    ["I:/Bulk Downloader/CobraMode/12", "I:/Bulk Downloader/CobraMode"],
    // a plain creator folder is already the base
    ["I:\\Bulk Downloader\\CobraMode", "I:\\Bulk Downloader\\CobraMode"],
    ["I:/Bulk Downloader/CobraMode", "I:/Bulk Downloader/CobraMode"],
    // a name that merely ends in digits is NOT a batch folder: the digits have
    // to be the whole segment, or "Creator 2024" would lose its year
    ["I:\\Bulk Downloader\\Creator 2024", "I:\\Bulk Downloader\\Creator 2024"],
    ["I:\\Bulk Downloader\\Vol2", "I:\\Bulk Downloader\\Vol2"],
    ["I:\\Bulk Downloader\\TinyFurniture_b01", "I:\\Bulk Downloader\\TinyFurniture_b01"]
];

let pass = 0;
for (const [input, expected] of cases) {
    const got = baseFor(input);
    const ok = got === expected;
    console.log("  %s  %s -> %s", ok ? "PASS" : "FAIL", input, got);
    if (!ok) console.log("        expected %s", expected);
    assert.strictEqual(got, expected);
    pass += 1;
}
console.log("\n%d/%d passed", pass, cases.length);
