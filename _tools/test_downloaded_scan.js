// A creator who adds models over time should mean downloading only the new
// ones. The record of what has been fetched is the folders themselves, not a
// saved list, because the saved list is pruned to whatever catalogue is loaded
// -- switch creators and come back, and it would look like nothing was ever
// downloaded.
//
//   node _tools/test_downloaded_scan.js
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

// the real function, lifted out of main.js so this tests what ships
const src = fs.readFileSync(path.join(__dirname, "..", "electron", "main.js"), "utf8");
const start = src.indexOf("function scanDownloadedModelIds");
const body = src.slice(start, src.indexOf("function getAllowedOpenPathRoots"));
const scanDownloadedModelIds = new Function("fs", "path", "return " + body)(fs, path);

const root = fs.mkdtempSync(path.join(os.tmpdir(), "dlscan-"));
process.on("exit", () => fs.rmSync(root, { recursive: true, force: true }));

function model(folder, id, name, withArchive) {
    const dir = path.join(root, folder, "stl_files", `${id}_${name}`);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `model_${id}.json`), "{}");
    if (withArchive) {
        fs.writeFileSync(path.join(dir, `${name}.zip`), "PK");
    }
}

let pass = 0;
function check(label, expected, actual) {
    const ok = JSON.stringify(expected) === JSON.stringify(actual);
    console.log("  " + (ok ? "PASS" : "FAIL") + "  " + label);
    if (!ok) {
        console.log("        expected " + JSON.stringify(expected));
        console.log("        actual   " + JSON.stringify(actual));
    }
    assert.ok(ok, label);
    pass += 1;
}

// a creator downloaded over three sessions, plus a second creator alongside
model("Creator", 101, "Alpha", true);
model("Creator", 102, "Beta", true);
model("Creator_2", 103, "Gamma", true);
model("Creator_3", 104, "Delta", true);
model("Creator_3", 105, "Half", false);      // no archive: must be retried
model("OtherCreator", 999, "Theirs", true);  // must not leak in
model("Creator_originals", 777, "Backup", true); // backups are not downloads

const r = scanDownloadedModelIds({ basePath: path.join(root, "Creator") });

check("finds models across every batch folder", [101, 102, 103, 104], r.ids);
check("counts a folder with no archive as unfinished", 1, r.incomplete);
check("another creator's models are not counted", false, r.ids.includes(999));
check("an _originals backup is not counted as downloaded", false, r.ids.includes(777));
check("reports which folders it looked in", ["Creator", "Creator_2", "Creator_3"], r.folders);

// pointing at a batch folder must behave the same as pointing at the creator
const fromBatch = scanDownloadedModelIds({ basePath: path.join(root, "Creator_3") });
check("works when pointed at a batch folder", [101, 102, 103, 104], fromBatch.ids);

// the thing this exists for: only the new models are left to fetch
const catalogueToday = [101, 102, 103, 104, 105, 201, 202];
const alreadyDone = new Set(r.ids);
const toFetch = catalogueToday.filter((id) => !alreadyDone.has(id));
check("only new models (and the unfinished one) are queued", [105, 201, 202], toFetch);

// a folder that does not exist yet must not throw
const missing = scanDownloadedModelIds({ basePath: path.join(root, "NeverSeen") });
check("an unknown creator reports nothing, without failing", [], missing.ids);

console.log("\n" + pass + "/" + pass + " passed");
