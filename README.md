# STL Bulk Downloader
Built using deliriyum's MyMiniFactory Model Downloader
https://gist.github.com/deliriyum/d353b9528e970e242b1915bb51da2a61

This app Downloads files you own from MyMiniFactory.
This is not a scraper, it uses API calls.
This does not download files that you do not own.
Update: Now more efficient and dodges rate limit trigger.

Download Here -> https://github.com/Zerohaus/STL_Bulk_Downloader/releases

# WINDOWS
Steps:
1. Install the Bulk Downloader
2. You may get a Windows Defender warning, ignore this. (we didn't purchase a Microsoft license)
3. Open the application

### Step 1 - Connect your account
4. Click > Open MyMiniFactory (MMF)
5. Login to your MMF account and go to your profile page (leave this window open while downloading)
6. Back in the app click > Capture session
7. The label at the top right of Step 1 should change to connected. If it doesn't, open "Not connecting?" for checks, a re-check button, and manual credential entry.

### Step 2 - Choose your models
8. Pick which models to load:
   - **Everything I own** - models you have purchased or own in your Library
   - **Only models I made** - for creators who want to download their own files
   - **One creator only** - filters your Library down to a single creator ID
9. Click > Load my models
10. If you change the selection above, click Load my models again
11. Use the search box to find particular models, and "Download in batches of" to split a large library into chunks
12. "Set a category for every model" is optional. It writes the same category tags into every model JSON, which is useful if you want to upload to another marketplace.
13. Failed models can be re-run later from "Retry failed models, or export the list"

### Step 3 - Download
14. Set "Save to" to the folder you want the files in
15. It's recommended to leave "Test one file first, before downloading everything" selected
16. Click > Start download
17. If you chose a batch size, download the following batch with > Download next batch
18. "Run log" shows the detailed output if you need to see what's happening


# MAC
Also Available
MMF Downloader

---

## Developer docs

- [README-DESKTOP.md](README-DESKTOP.md) — output layout, pacing, environment variables
- [CHANGELOG.md](CHANGELOG.md) — release notes
- [DESKTOP_EXE.md](DESKTOP_EXE.md) — building the installer
- [_tools/MMF_DOWNLOADER_FINDINGS.md](_tools/MMF_DOWNLOADER_FINDINGS.md) — measured notes on the API, rate limiting, and archive conventions
