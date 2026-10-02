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
const start = src.indexOf("function downloadLedgerPath");
const body = src.slice(start, src.indexOf("function getAllowedOpenPathRoots"));
const api = new Function("fs", "path", body + "; return { scanDownloadedModelIds, recordDownloadedIds };")(fs, path);
const { scanDownloadedModelIds, recordDownloadedIds } = api;

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

// ---- the case that matters at scale: a large catalogue is uploaded and the
// folders deleted to reclaim the disk. The record has to survive that, or the
// next time the creator adds a model the whole catalogue comes down again.
recordDownloadedIds({ basePath: path.join(root, "Creator"), ids: r.ids });
for (const f of ["Creator", "Creator_2", "Creator_3"]) {
    fs.rmSync(path.join(root, f), { recursive: true, force: true });
}

const afterDelete = scanDownloadedModelIds({ basePath: path.join(root, "Creator") });
check("record survives deleting every folder", [101, 102, 103, 104], afterDelete.ids);
check("nothing is left on disk to find", 0, afterDelete.onDiskCount);
check("so the ledger is what knew", 4, afterDelete.ledgerCount);

const stillToFetch = catalogueToday.filter((id) => !new Set(afterDelete.ids).has(id));
check("still queues only the new models after deletion", [105, 201, 202], stillToFetch);

// each creator keeps its own ledger
recordDownloadedIds({ basePath: path.join(root, "OtherCreator"), ids: [999] });
const other = scanDownloadedModelIds({ basePath: path.join(root, "OtherCreator") });
check("one creator's ledger does not leak into another", false, other.ids.includes(101));

// recording the same models twice must not grow the ledger
const again = recordDownloadedIds({ basePath: path.join(root, "Creator"), ids: [101, 102] });
check("re-recording adds nothing", 0, again.added);

// pointing at a batch folder must find the creator's ledger
const viaBatch = scanDownloadedModelIds({ basePath: path.join(root, "Creator_7") });
check("ledger is found when pointed at a batch folder", [101, 102, 103, 104], viaBatch.ids);

console.log("\n" + pass + "/" + pass + " passed");
