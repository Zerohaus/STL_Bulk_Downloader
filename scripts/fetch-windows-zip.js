#!/usr/bin/env node
/**
 * Downloads Info-ZIP 3.0 (GnuWin32 build) for Windows into tools/.
 * Run: npm run vendor:zip
 * License: Info-ZIP — see tools/README.md
 */

const fs = require("fs");
const path = require("path");
const https = require("https");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const TOOLS_DIR = path.join(ROOT, "tools");
const BIN_ZIP_URL =
    "https://downloads.sourceforge.net/project/gnuwin32/zip/3.0/zip-3.0-bin.zip";
const DEP_ZIP_URL =
    "https://downloads.sourceforge.net/project/gnuwin32/zip/3.0/zip-3.0-dep.zip";
const REQUIRED_FILES = ["zip.exe", "zip32z64.dll", "bzip2.dll"];

function download(url, destPath) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(destPath);

        const request = (currentUrl) => {
            https
                .get(currentUrl, (response) => {
                    if (
                        response.statusCode >= 300 &&
                        response.statusCode < 400 &&
                        response.headers.location
                    ) {
                        response.resume();
                        request(response.headers.location);
                        return;
                    }

                    if (response.statusCode !== 200) {
                        reject(
                            new Error(
                                `HTTP ${response.statusCode} downloading ${currentUrl}`
                            )
                        );
                        return;
                    }

                    response.pipe(file);
                    file.on("finish", () => {
                        file.close(() => resolve(destPath));
                    });
                })
                .on("error", reject);
        };

        request(url);
    });
}

function extractZip(archivePath, destinationDir) {
    fs.mkdirSync(destinationDir, { recursive: true });

    if (process.platform === "win32") {
        execFileSync(
            "powershell",
            [
                "-NoProfile",
                "-Command",
                `Expand-Archive -Path '${archivePath.replace(/'/g, "''")}' -DestinationPath '${destinationDir.replace(/'/g, "''")}' -Force`
            ],
            { stdio: "inherit" }
        );
        return;
    }

    execFileSync("unzip", ["-q", "-o", archivePath, "-d", destinationDir], {
        stdio: "inherit"
    });
}

async function main() {
    if (process.platform !== "win32") {
        console.log("vendor:zip is only required on Windows (macOS/Linux use system zip).");
        return;
    }

    const tmpDir = fs.mkdtempSync(path.join(require("os").tmpdir(), "mmf-vendor-zip-"));
    const binArchive = path.join(tmpDir, "zip-bin.zip");
    const depArchive = path.join(tmpDir, "zip-dep.zip");
    const extractRoot = path.join(tmpDir, "extracted");

    console.log("Downloading GnuWin32 zip 3.0 binaries...");
    await download(BIN_ZIP_URL, binArchive);
    await download(DEP_ZIP_URL, depArchive);

    extractZip(binArchive, extractRoot);
    extractZip(depArchive, extractRoot);

    const sourceBin = path.join(extractRoot, "bin");
    if (!fs.existsSync(path.join(sourceBin, "zip.exe"))) {
        throw new Error(`zip.exe not found after extract (expected ${sourceBin})`);
    }

    fs.mkdirSync(TOOLS_DIR, { recursive: true });
    for (const name of fs.readdirSync(sourceBin)) {
        fs.copyFileSync(path.join(sourceBin, name), path.join(TOOLS_DIR, name));
    }

    const missing = REQUIRED_FILES.filter(
        (name) => !fs.existsSync(path.join(TOOLS_DIR, name))
    );
    if (missing.length > 0) {
        throw new Error(`Missing required files in tools/: ${missing.join(", ")}`);
    }

    console.log(`Installed bundled zip to ${TOOLS_DIR}`);
    for (const name of REQUIRED_FILES) {
        const stat = fs.statSync(path.join(TOOLS_DIR, name));
        console.log(`  ${name} (${stat.size} bytes)`);
    }

    fs.rmSync(tmpDir, { recursive: true, force: true });
}

main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
});
