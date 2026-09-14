# MyMiniFactory bulk downloader — findings & recommendations

Handoff notes from a session that downloaded ~120 of 180 missing NovaMinis models
(creator 525152) into an existing 1,545-folder library, and had to reverse-engineer
the layout conventions and fight the rate limiter to do it.

Everything below was **measured against real responses and the existing library**, not
inferred. Counts are given so you can judge how strong each claim is.

---

## 1. Endpoint map

| Endpoint | Auth | Rate limited | Notes |
|---|---|---|---|
| `GET /api/v2/objects/<id>` | **yes** (401 without) | **no** (in practice) | Kept answering normally throughout every download lockout. Metadata passes are cheap. |
| `GET /download/<id>` | yes | **yes** | Whole model, **one request**. 302s to a signed CDN URL. |
| `GET /download/<id>?downloadfile=<name>` | yes | **yes** | One file. 3–4 requests per model. |
| `dl4.myminifactory.com/object-images/...` | **no** | no | Images are public. No cookie needed. |
| `dlcc.myminifactory.com/.../generated-zips/...?exp=&sig=` | signed URL | **no** | Where the bytes actually come from. |

### The single most important fact

`/download/<id>` 302s to a **signed CDN URL** on `dlcc.myminifactory.com`. The rate limit
lives on the **origin request that mints the signature**, not on the CDN transfer.

Consequences:

- Fetching files individually costs **3–4× more rate-limit budget for identical bytes**.
  Switching to one request per model took the throttle rate from constant to occasional
  and cooldowns to zero.
- **Transfer volume is essentially free.** A 1 GB model costs the same against the limit
  as a 40 MB one. Do not optimise for bytes; optimise for *request count*.

Not every model has a generated zip. When there is none, `/download/<id>` redirects back
to the object page and you get `text/html` instead of a zip (observed on model 831302).
Detect that and fall back to per-file. **Check `Content-Type`, and validate the result is
actually a zip — do not trust HTTP 200.**

### `archive_download_url` is a red herring

It was `null` on **all 180** models even when fully authenticated, and `is_bought` was
`false` on every one (access is via subscription, not purchase — downloads authorise fine
regardless). Do not gate anything on either field.

### Degraded cached metadata

Some cached `model_*.json` files were re-fetched **without** a login and came back with
`description: null` and `description_html: ""` (e.g. 368452, 698874, 389011, 419697),
even though the real text exists. If you have a session, prefer the live API response
field-by-field and fall back to cache — this *repairs* those records instead of
propagating empty descriptions.

---

## 2. Rate limiting — the part that actually costs you

### Two failure modes that look alike and are not

| Signal | What it is | Correct response |
|---|---|---|
| `403`, **no** `cf-mitigated` header | MyMiniFactory app throttle | Transient. Long quiet period. |
| `429` + **`cf-mitigated: challenge`** | Cloudflare "Just a moment…" JS page | **Timed cooldown, NOT a dead token.** Wait it out. |

They are distinguishable **only** by the `cf-mitigated` response header. Check it.

**A `cf-mitigated: challenge` does NOT mean `cf_clearance` is dead.** This cost real time
to learn: the run stopped and asked the user for a fresh cookie, twice. The *same untouched
cookie* started working again a few minutes later. Treat a challenge as a 30–60 minute
cooldown, not as a credential failure.

### The escalation ladder — the actual trap

403s arrive in a worsening pattern before Cloudflare locks you out:

```
model 1: 403 → 1 retry  → OK
model 2: 403 → 2 retries → OK
model 3: 403 → 3 retries → OK
model 4: 429 cf-mitigated: challenge   ← locked out
```

**Retrying quickly after a 403 is what drives the escalation.** A 4s → 8s → 16s backoff
feels polite but is aggressive enough to keep the penalty window alive — every attempt
inside the window renews it. That is how 52 successful models turned into a hard lockout,
and how a single file burned 8 minutes across four escalating retries and then downloaded
first try minutes later.

**Rule: after a block, do not touch the endpoint at all for T minutes.** No retries, no
probes. When T expires, probe with *one cheap request*, not a real download. If it fails,
double T.

### It is a rolling volume quota, not a rate limit

After switching to one-request-per-model, pacing was tried at 6s, 10s, and 15s+ between
models. Throttling stayed at roughly 80% and the adaptive pacer pinned itself at its
ceiling regardless.

That is the signature of a **volume quota over a rolling window**, not a per-second rate.
Past a certain daily/hourly volume, spacing stops helping. The remedies are to spread the
work across days or accept the grind — there is no delay value that "fixes" it.

### Other hygiene

- `cf_clearance` is bound to **User-Agent and IP**. Pin the UA to the browser that minted
  the cookie; a mismatch invalidates it instantly.
- Reuse one keep-alive session rather than opening a fresh connection per request.
- Add ±30% jitter to every interval so you neither march in lockstep with a fixed window
  boundary nor look robotic.

---

## 3. Architecture for a multi-day unattended run

The design below is what the current script *should* have been. For 2,000 files the goal
is "runs for days, needs a human ~never".

### 3.1 Cap the rate, not the delay  ← the key inversion

The current script has a **delay ceiling** (120s) — a cap on how *slow* it will go. That is
backwards. It races as fast as it can, takes punishment, and pins itself against a limit on
its own patience.

Instead derive a **target rate from a deadline**:

```
2000 files ÷ 5 days = 16.7/hour = one every ~3.6 minutes
```

~52 models succeeded before the first lockout, so 17/hour is an order of magnitude under
any plausible quota and should never see a 403. **The run takes 5 days either way** —
racing buys nothing.

- Treat the deadline rate as a **hard ceiling you may drop below but never exceed**.
- Implement as a **token bucket**: small capacity (3–5), refilled at the target rate, so it
  cannot burst even after an idle stretch.
- On a block: halve the target rate. On sustained success: additive increase (+10%) back
  toward — never past — the deadline cap. (AIMD, like TCP congestion control.)

### 3.2 Persist everything, because the process will die

The run died twice to causes unrelated to Cloudflare: a chat fork and a process exit. Over
five days expect reboots, updates, network drops.

- **Journal on disk** (SQLite or JSONL): one row per item — `pending / done / failed /
  permanently_failed`, attempt count, last error, timestamps.
- **Derive resume from disk truth**, not memory. The current script already does this and
  it is why nothing was ever lost — keep that property.
- **Persist the token-bucket state.** If a restart resets the bucket to full it immediately
  bursts and gets blocked. Subtle and it bites hard.
- **Detach the process** — Windows Task Scheduler, NSSM as a service, or at minimum a
  detached process writing to a log. Not something tied to a terminal or an agent session.

### 3.3 Route by error class, not by a retry counter

"N consecutive failures then stop" is too blunt — it conflates a rate limit with a dead
session, which is exactly the misdiagnosis that halted an otherwise healthy run.

| Signal | Meaning | Response |
|---|---|---|
| `403`, no `cf-mitigated` | app throttle | quiet 5–15 min, halve rate |
| `429` + `cf-mitigated` | Cloudflare cooldown | quiet 30–60 min, halve rate |
| `401` / redirect to login | session actually dead | pause, wait for human |
| `404` / `410` | item gone | permanently failed, never retry |
| `5xx` | server hiccup | 3 retries, then requeue to the back |

Only the auth row needs a human. Everything else self-heals.

### 3.4 Learn the quota instead of guessing

Keep a rolling count of successes in the trailing 1h and 24h. When a block hits, record
those numbers — that is an empirical upper bound on the quota. Self-impose a budget at
~60% of the lowest observed bound. After a few days the script knows the real limit better
than any hardcoded delay.

### 3.5 Make the human-in-the-loop part graceful

Credential expiry is the only thing that genuinely needs a person.

- On an auth-class failure, **pause and watch the cookie file's mtime**. The user drops in
  a fresh cookie whenever they notice; the run picks it up and continues. No restart, no
  lost progress.
- Notify on entering that state (and only that state).
- Read the cookie **from a file**, never a command-line argument — keeps it out of the
  process list and shell history.

> **Boundary:** all of the above is about *waiting out* limits and refreshing the user's own
> session. Automating the *solving* of a Cloudflare challenge is defeating bot detection and
> is out of scope. At deadline-driven pacing you should not be challenged at all.

---

## 4. Layout conventions (NovaMinis library)

These were derived by reproducing the 1,545 folders the app had already built. They are
**not** guesses — each was validated against the whole library. Two of them were wrong in
the first implementation and required repacking 57 archives.

### 4.1 Folder and file naming

```
stl_files\<id>_<Slug>\
    <Slug>.zip
    images\thumbnail_image.jpg      ← the is_primary image, at ORIGINAL size (e.g. 3240²)
    images\<sanitised-name>.jpg     ← every non-primary image
    model_<id>.json
```

**Sanitiser** — delete `< > : " / \ | ? *` **and the apostrophe**, collapse whitespace runs
to a single `_`, collapse runs of `_`, trim. `& [ ] ( ) ! - .` are **kept**.

- Folder slug: cap at 80 chars. → **reproduced 1545/1545 existing folder names exactly.**
- Image names: same sanitiser, extension kept, **no length cap**.
  → **reproduced 1728/1729** (the one miss is a genuinely absent file in an old folder).
- Archive member names: same sanitiser. → **88%** of the library (254/290 sampled).

Image URLs frequently contain literal spaces and apostrophes
(`FRONT - 001A Jul24  Dragon's Bounty -PAT-SM-STORE.jpg`), so **percent-encode the request
URL but save under the sanitised name**.

### 4.2 `model_<id>.json` (the reduced one, inside the folder)

Keys in order: `name`, `description`, `tags`, `price`, `categories`.

- `price` is a **float** (`3.99`), not the API's `{currency, symbol, value}` object.
- `categories` is the fixed selection configured in the app's `desktop-settings.json`
  (`categorySelection`), identical in all 1,545 folders.
- `description` is the **raw** API text; `clean_competitor_mentions.py` strips storefront
  promos afterwards as a separate pass.
- Format: 2-space indent, **CRLF**, UTF-8 **without BOM**, trailing newline,
  `ensure_ascii=False` (the `•` bullets are literal UTF-8).

Verified: after running the project's own cleaner, output was **byte-identical to 365 of
380** sampled existing files. The 15 differences are a known anomaly where 30/1544 folders
have the 5 configured category *names* appended to `tags` — a minority pattern, not the
convention.

### 4.3 Archive contents

- **Flat** — no directories.
- **Nested zips are expanded, recursively.** A model whose `files.items` is a single
  `Mausoleum 02.zip` has that zip's *contents* in the archive, not the zip. Nesting can be
  two deep: the whole-model download of *The Grand Bridge* is an archive containing
  `The Grand Bridge.zip`, which in turn holds the meshes. **Cap the recursion depth.**
- **Compression is conditional** — measured across the entire library:

  | Model's file list | Compression | Count |
  |---|---|---|
  | plain files | `ZIP_STORED` | **1533 / 1533** |
  | contains a `.zip` | `ZIP_DEFLATED` | **36 / 45** |

  This matters: a model delivered as a zip gets expanded and its contents are already
  compressed, so storing them raw bloats the archive badly — *The Grand Bridge* went
  1041 MB → 1852 MB before this rule was applied.

- Verify each downloaded file's byte count against the API's declared `size` before
  committing it.

---

## 5. Anti-patterns — things that were tried and made it worse

1. **Fast exponential backoff on 403** (4/8/16s). Escalated a healthy run into a hard
   lockout. Use long quiet periods instead.
2. **Treating `cf-mitigated: challenge` as a dead credential.** Stopped the run and asked
   for a new cookie twice; the old cookie was fine both times.
3. **Per-file downloads.** 4× the rate-limit cost for the same bytes.
4. **A delay ceiling instead of a rate cap.** Guarantees you eventually sit at max delay
   still getting throttled.
5. **Tuning the inter-request delay to beat a volume quota.** Cannot work. 6s, 10s and 15s
   all produced ~80% throttling.
6. **Repacking without an explicit allow-list.** A scoped-by-heuristic repack initially
   targeted 100 archives, ~43 of which were the *original* app-built folders — the very
   reference for the conventions. Any in-place rewrite must require an explicit id list.
7. **Buffering members in memory.** The largest single file here is 1041 MB. Stream through
   a scratch file.
8. **Building directly into the live output directory.** Assemble in staging and move the
   folder in only when complete, so a downstream uploader never sees a half-built model.
   (Cleanup on `BaseException`, not `Exception`, so Ctrl-C leaves nothing partial.)

---

## 6. Validation methodology worth keeping

The two convention bugs (member-name sanitising, conditional compression) produced
**working, valid zips** and would never have been caught by testing the downloader against
itself. They were only found by **differential comparison against the pre-existing
library**:

- reproduce every existing folder/image name from its metadata and count exact matches;
- cross-tabulate archive properties (compression, entry names, entry sets) against metadata
  properties across all 1,545 folders;
- treat any rule below ~95% agreement as "not yet understood", and go look at the
  exceptions.

Build that comparison harness **before** the downloader, and keep it as a post-run
verification sweep.

---

## 7. What is now implemented (v2.0.0)

Second-pass notes, after a further full-library pull brought the totals to **413 models /
175 GB / zero failed downloads across two libraries**. This section records which findings
are now built into the shipped scripts, and where.

| Finding | Where it lives now |
| --- | --- |
| `/download/<id>` returns a whole model in one request | `try_whole_model_archive` in `mmf_download_stl_files_enhanced.sh`; per-file walk is the fallback |
| Fetched archives can be incomplete | `whole_model_archive_is_complete` verifies the entry set against `files.items[]` before trusting it |
| Request count is the lever, not delay | Whole-model route first; `MMF_STL_FILE_DELAY_SEC` demoted to a floor |
| A pace that is fine one day is not fine the next | `widen_adaptive_delay` / `note_adaptive_success` (×1.8 up, slow creep down) |
| 403 without `cf-mitigated` is an app throttle, not a dead cookie | `is_app_throttle_failure` + `wait_out_app_throttle` (shipped in 1.5.2) |
| A Cloudflare challenge is a timed cooldown | `wait_out_cloudflare_cooldown` (shipped in 1.5.2) |
| Flat `<Slug>.zip`, nested archives expanded not nested | `compress_non_json_assets` + `expand_zip_into_payload` (recursive, depth-capped) |
| STORED for plain files, DEFLATED for expanded `.zip` members | `ZIP_COMPRESS_LEVEL` two-pass packing in `compress_non_json_assets` |
| Member names are sanitised inside the archive too | `sanitize_filename` applied per member during expansion |
| Reserved characters are deleted, not underscored | `sanitize_filename` / `sanitize_folder_name`, and both `4_rename_folders_from_json.*` |
| Stage, then move | `prepare_model_staging_dir` / `finalize_model_staging_dir`, staging under `.mmf_staging/` |
| Clean up on interrupt | `cleanup_on_interrupt`, installed as a `trap ... INT TERM` |
| `is_bought` is not an ownership test | No longer gates anything; reported as metadata only |
| Zero-file listings are ordinary | Counted separately from download failures |
| Partial folders masquerade as done | Completion decided by a valid archive, never by directory contents |
| Descriptions vanish when unauthenticated | `write_compact_model_json` keeps the previous description when the incoming one is empty |

### Corrections to section 5

One anti-pattern in the earlier notes needs narrowing. The `glob`/`[...]` character-class
trap is **real in Python and in PowerShell**, but not in these Bash scripts:

- **PowerShell**: `-Path` genuinely expands wildcards regardless of quoting, so a library
  path containing `[PHASES]` matches nothing and the script reports success. Fixed by using
  `-LiteralPath` throughout `3_extract_all_zips.ps1` and `4_rename_folders_from_json.ps1`.
- **Bash**: the existing globs interpolate their variable *inside double quotes*
  (`"${dir}/${base}"*.zip`), and a quoted portion of a word is literal — the brackets are
  not a character class. Verified empirically; no change was needed.

The lesson generalises as "know which layer does the globbing", not "escape every path".

### Still not implemented

- **Library enumeration via `/api/library/nodes`.** It still needs a browser-driven fetch
  (the page sends an extra auth header a script does not have), so the catalog side is
  unchanged. Treat a successful download, not the library listing, as the real inventory —
  219 gifted models downloaded perfectly while the library showed nothing added that day.
- **A post-run verification sweep** (entry set, byte totals, CRC across the whole library).
  Section 6's harness is still the right idea and still does not exist in this repo. Note
  that any byte-total check must skip files whose `size` is `null` — 12 of 233 models had
  them — rather than failing on the conversion.
- **Queue ordering** (smallest first, bundles last). The script honours the order it is
  given and deliberately does not re-sort a caller-supplied ID list.
