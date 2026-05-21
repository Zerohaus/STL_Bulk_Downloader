(() => {
    if (window.__MMF_APP_BOOTSTRAPPED__) {
        console.warn("app.js was loaded more than once. Duplicate initialization was skipped.");
        return;
    }

    window.__MMF_APP_BOOTSTRAPPED__ = true;

const elements = {
    phpSessidInput: document.getElementById("phpSessidInput"),
    cfClearanceInput: document.getElementById("cfClearanceInput"),
    jwtInput: document.getElementById("jwtInput"),
    publishableKeyInput: document.getElementById("publishableKeyInput"),
    modelIdList: document.getElementById("modelIdList"),
    modelListPagination: document.getElementById("modelListPagination"),
    modelListPrevBtn: document.getElementById("modelListPrevBtn"),
    modelListNextBtn: document.getElementById("modelListNextBtn"),
    modelListPageInfo: document.getElementById("modelListPageInfo"),
    modelListTotalInfo: document.getElementById("modelListTotalInfo"),
    modelSearchInput: document.getElementById("modelSearchInput"),
    modelSearchClearBtn: document.getElementById("modelSearchClearBtn"),
    batchSizeSelect: document.getElementById("batchSizeSelect"),
    batchStatus: document.getElementById("batchStatus"),
    openMmfLoginBtn: document.getElementById("openMmfLoginBtn"),
    captureMmfSessionBtn: document.getElementById("captureMmfSessionBtn"),
    checkSessionBtn: document.getElementById("checkSessionBtn"),
    sessionStatus: document.getElementById("sessionStatus"),
    creatorFilterGroup: document.getElementById("creatorFilterGroup"),
    creatorIdFilterInput: document.getElementById("creatorIdFilterInput"),
    categorySelectionList: document.getElementById("categorySelectionList"),
    categorySelectionSummary: document.getElementById("categorySelectionSummary"),
    categorySelectionPreview: document.getElementById("categorySelectionPreview"),
    idsInput: document.getElementById("idsInput"),
    downloadRootInput: document.getElementById("downloadRootInput"),
    browseDownloadRootBtn: document.getElementById("browseDownloadRootBtn"),
    openDownloadRootBtn: document.getElementById("openDownloadRootBtn"),
    downloadHistoryList: document.getElementById("downloadHistoryList"),
    testModeCheck: document.getElementById("testModeCheck"),
    autoLoadMyIdsBtn: document.getElementById("autoLoadMyIdsBtn"),
    resetBatchProgressBtn: document.getElementById("resetBatchProgressBtn"),
    clearCatalogBtn: document.getElementById("clearCatalogBtn"),
    clearSessionBtn: document.getElementById("clearSessionBtn"),
    validateBtn: document.getElementById("validateBtn"),
    downloadIdsBtn: document.getElementById("downloadIdsBtn"),
    copyCommandsBtn: document.getElementById("copyCommandsBtn"),
    generatePsBtn: document.getElementById("generatePsBtn"),
    copyPsBtn: document.getElementById("copyPsBtn"),
    statusMessage: document.getElementById("statusMessage"),
    requirementsList: document.getElementById("requirementsList"),
    readinessBar: document.getElementById("readinessBar"),
    readinessText: document.getElementById("readinessText"),
    idsPreview: document.getElementById("idsPreview"),
    validIdCount: document.getElementById("validIdCount"),
    invalidLineCount: document.getElementById("invalidLineCount"),
    requiredPassCount: document.getElementById("requiredPassCount"),
    readinessPct: document.getElementById("readinessPct"),
    connectionBadge: document.getElementById("connectionBadge"),
    basePathInput: document.getElementById("basePathInput"),
    browseBasePathBtn: document.getElementById("browseBasePathBtn"),
    extractModeSelect: document.getElementById("extractModeSelect"),
    jsonPathInput: document.getElementById("jsonPathInput"),
    browseJsonPathBtn: document.getElementById("browseJsonPathBtn"),
    foldersPathInput: document.getElementById("foldersPathInput"),
    browseFoldersPathBtn: document.getElementById("browseFoldersPathBtn"),
    namingFormatSelect: document.getElementById("namingFormatSelect"),
    maxLengthInput: document.getElementById("maxLengthInput"),
    useRecommendedPathsBtn: document.getElementById("useRecommendedPathsBtn"),
    runPostProcessBtn: document.getElementById("runPostProcessBtn"),
    pathHelperHint: document.getElementById("pathHelperHint"),
    psSnippet: document.getElementById("psSnippet"),
    desktopGate: document.getElementById("desktopGate"),
    depSummary: document.getElementById("depSummary"),
    depList: document.getElementById("depList"),
    depLog: document.getElementById("depLog"),
    depRefreshBtn: document.getElementById("depRefreshBtn"),
    depInstallBtn: document.getElementById("depInstallBtn"),
    depSkipBtn: document.getElementById("depSkipBtn"),
    runtimePath: document.getElementById("runtimePath"),
    runExecuteBtn: document.getElementById("runExecuteBtn"),
    runNextBatchBtn: document.getElementById("runNextBatchBtn"),
    runStep1Btn: document.getElementById("runStep1Btn"),
    runStep2TestBtn: document.getElementById("runStep2TestBtn"),
    runStep2FullBtn: document.getElementById("runStep2FullBtn"),
    runStep3Btn: document.getElementById("runStep3Btn"),
    runStep4Btn: document.getElementById("runStep4Btn"),
    stopRunBtn: document.getElementById("stopRunBtn"),
    clearLogBtn: document.getElementById("clearLogBtn"),
    openFilesFolderBtn: document.getElementById("openFilesFolderBtn"),
    runStatus: document.getElementById("runStatus"),
    pipelineProgressPanel: document.getElementById("pipelineProgressPanel"),
    pipelineProgressLabel: document.getElementById("pipelineProgressLabel"),
    pipelineProgressPercent: document.getElementById("pipelineProgressPercent"),
    pipelineProgressBar: document.getElementById("pipelineProgressBar"),
    pipelineProgressDetail: document.getElementById("pipelineProgressDetail"),
    runLog: document.getElementById("runLog"),
    jsonFileSelect: document.getElementById("jsonFileSelect"),
    refreshJsonListBtn: document.getElementById("refreshJsonListBtn"),
    openJsonFolderBtn: document.getElementById("openJsonFolderBtn"),
    jsonViewer: document.getElementById("jsonViewer")
};

const mmfDesktopApi = window.desktopApi || null;

async function showConfirmDialog(message) {
    if (mmfDesktopApi && mmfDesktopApi.showConfirmDialog) {
        return mmfDesktopApi.showConfirmDialog(message);
    }
    return window.confirm(message);
}

async function showAlertDialog(message) {
    if (mmfDesktopApi && mmfDesktopApi.showAlertDialog) {
        return mmfDesktopApi.showAlertDialog(message);
    }
    window.alert(message);
}

let lastDependencySummary = null;
let activeRunId = null;
let latestRunId = null;
let runtimePlatform = "unknown";
let settingsSaveTimer = null;
let settingsApplyInProgress = false;
let pipelineRunning = false;
let runtimeInfoCache = null;
let modelIdEntries = [];
let categoryTaxonomyItems = [];
let categorySelectionMap = new Map();
const MODEL_LIST_UI_PAGE_SIZE = 10;
const CATALOG_LOAD_MODES = ["listing", "library", "creator"];
const BATCH_SIZE_OPTIONS = ["10", "25", "50", "100", "all"];
const BATCH_STATUS_OPTIONS = ["idle", "running", "completed", "failed", "interrupted"];
const DOWNLOAD_HISTORY_LIMIT = 20;
let modelListUiPage = 1;
let modelSearchQuery = "";
let downloadRootHistory = [];
let lastStableDownloadRoot = "";
let batchProgressState = createDefaultBatchProgressState();
let activeBatchPlan = null;
const sessionPipelineCompletedIds = new Set();
let pipelineProgressState = createDefaultPipelineProgressState();

function createDefaultPipelineProgressState() {
    return {
        visible: false,
        phase: "idle",
        percent: 0,
        label: "",
        detail: "",
        metadataTotal: 0,
        metadataDone: 0,
        batchTotal: 0,
        batchModelsDone: 0,
        step2CurrentModelId: ""
    };
}

function createDefaultBatchProgressState() {
    return {
        completedIds: [],
        inProgress: false,
        inProgressIds: [],
        startedAt: "",
        lastCompletedAt: "",
        lastStatus: "idle",
        lastError: "",
        lastRunDownloadRoot: ""
    };
}

function sanitizeBatchSizeSelectionValue(value) {
    const normalized = typeof value === "string" ? value.trim().toLowerCase() : "";
    return BATCH_SIZE_OPTIONS.includes(normalized) ? normalized : "25";
}

function sanitizeNumericIdList(rawIds) {
    if (!Array.isArray(rawIds)) {
        return [];
    }

    const seen = new Set();
    const sanitized = [];

    rawIds.forEach((value) => {
        const id = String(value || "").trim();
        if (!/^\d+$/.test(id) || seen.has(id)) {
            return;
        }

        seen.add(id);
        sanitized.push(id);
    });

    return sanitized;
}

function sanitizeDownloadRootHistory(rawHistory) {
    if (!Array.isArray(rawHistory)) {
        return [];
    }

    const seen = new Set();
    const sanitized = [];

    rawHistory.forEach((entry) => {
        const value = String(entry || "").trim();
        if (!value) {
            return;
        }

        const isLikelyWindowsPath = /^[a-z]:\\/i.test(value) || value.includes("\\");
        const key = (runtimePlatform === "win32" || isLikelyWindowsPath)
            ? value.toLowerCase()
            : value;
        if (seen.has(key)) {
            return;
        }

        seen.add(key);
        sanitized.push(value);
    });

    return sanitized.slice(0, DOWNLOAD_HISTORY_LIMIT);
}

function sanitizeBatchProgressState(raw) {
    const source = raw && typeof raw === "object" ? raw : {};
    const status = typeof source.lastStatus === "string"
        ? source.lastStatus.trim().toLowerCase()
        : "";

    return {
        completedIds: sanitizeNumericIdList(source.completedIds),
        inProgress: typeof source.inProgress === "boolean" ? source.inProgress : false,
        inProgressIds: sanitizeNumericIdList(source.inProgressIds),
        startedAt: typeof source.startedAt === "string" ? source.startedAt.trim() : "",
        lastCompletedAt: typeof source.lastCompletedAt === "string" ? source.lastCompletedAt.trim() : "",
        lastStatus: BATCH_STATUS_OPTIONS.includes(status) ? status : "idle",
        lastError: typeof source.lastError === "string" ? source.lastError.trim() : "",
        lastRunDownloadRoot: typeof source.lastRunDownloadRoot === "string"
            ? source.lastRunDownloadRoot.trim()
            : ""
    };
}

function getBatchSizeSelection() {
    return sanitizeBatchSizeSelectionValue(elements.batchSizeSelect ? elements.batchSizeSelect.value : "25");
}

function setBatchSizeSelection(value) {
    if (!elements.batchSizeSelect) {
        return;
    }

    elements.batchSizeSelect.value = sanitizeBatchSizeSelectionValue(value);
}

function getBatchProgressSnapshot() {
    return sanitizeBatchProgressState(batchProgressState);
}

function getDownloadRootHistorySnapshot() {
    return sanitizeDownloadRootHistory(downloadRootHistory);
}

function getCatalogLoadModeInputs() {
    return Array.from(document.querySelectorAll('input[name="catalogLoadMode"]'));
}

function getCatalogLoadMode() {
    const selected = getCatalogLoadModeInputs().find((input) => input.checked);
    const value = selected ? selected.value : "library";
    return normalizeCatalogLoadModeValue(value);
}

function normalizeCatalogLoadModeValue(mode) {
    const legacyMap = {
        owned: "listing",
        library_all: "library"
    };
    const normalized = typeof mode === "string" ? mode.trim() : "";
    if (legacyMap[normalized]) {
        return legacyMap[normalized];
    }

    return CATALOG_LOAD_MODES.includes(normalized) ? normalized : "library";
}

function setCatalogLoadMode(mode) {
    const normalized = normalizeCatalogLoadModeValue(mode);
    getCatalogLoadModeInputs().forEach((input) => {
        input.checked = input.value === normalized;
    });
    updateCreatorFilterVisibility();
}

function getCatalogLoadModeLabel(mode) {
    const labels = {
        listing: "listing (models you created)",
        library: "library (all your models)",
        creator: "creator filter"
    };

    return labels[normalizeCatalogLoadModeValue(mode)] || mode;
}

function normalizeCreatorIdFilterValue(value) {
    if (value === undefined || value === null) {
        return "";
    }

    return String(value).trim();
}

function getCreatorIdFilter() {
    return normalizeCreatorIdFilterValue(elements.creatorIdFilterInput ? elements.creatorIdFilterInput.value : "");
}

function setCreatorIdFilter(value) {
    if (!elements.creatorIdFilterInput) {
        return;
    }

    elements.creatorIdFilterInput.value = normalizeCreatorIdFilterValue(value);
}

function updateCreatorFilterVisibility() {
    if (!elements.creatorFilterGroup) {
        return;
    }

    const showCreatorFilter = getCatalogLoadMode() === "creator";
    elements.creatorFilterGroup.classList.toggle("hidden", !showCreatorFilter);
}

function normalizeCategoryTaxonomy(rawItems) {
    if (!Array.isArray(rawItems)) {
        return [];
    }

    const seen = new Set();
    const normalizedItems = [];

    rawItems.forEach((entry) => {
        if (!entry || typeof entry !== "object") {
            return;
        }

        const id = String(entry.id || "").trim();
        if (!id || seen.has(id)) {
            return;
        }

        seen.add(id);
        normalizedItems.push({
            id,
            name: typeof entry.name === "string" ? entry.name.trim() : "",
            parent_id: entry.parent_id === null || entry.parent_id === undefined
                ? null
                : String(entry.parent_id).trim() || null,
            is_active: entry.is_active !== false
        });
    });

    return normalizedItems;
}

function buildCategoryTree(items) {
    const byId = new Map();
    const roots = [];

    items.forEach((item) => {
        byId.set(item.id, {
            ...item,
            subcategories: []
        });
    });

    byId.forEach((item) => {
        if (!item.parent_id) {
            roots.push(item);
            return;
        }

        const parent = byId.get(item.parent_id);
        if (parent) {
            parent.subcategories.push(item);
        }
    });

    roots.forEach((root) => {
        root.subcategories.sort((a, b) => a.name.localeCompare(b.name));
    });

    roots.sort((a, b) => a.name.localeCompare(b.name));
    return roots;
}

function normalizeCategorySelection(rawSelection) {
    if (!Array.isArray(rawSelection)) {
        return [];
    }

    const merged = new Map();

    rawSelection.forEach((entry) => {
        if (!entry || typeof entry !== "object") {
            return;
        }

        const categoryId = String(entry.id || "").trim();
        if (!categoryId) {
            return;
        }

        const rawSubcategories = Array.isArray(entry.subcategoryIds)
            ? entry.subcategoryIds
            : Array.isArray(entry.subcategories)
                ? entry.subcategories
                : [];

        const normalizedSubs = rawSubcategories
            .map((subcategoryId) => String(subcategoryId || "").trim())
            .filter(Boolean);

        const existing = merged.get(categoryId) || new Set();
        normalizedSubs.forEach((subcategoryId) => existing.add(subcategoryId));
        merged.set(categoryId, existing);
    });

    return [...merged.entries()]
        .map(([id, subcategorySet]) => ({
            id,
            subcategoryIds: [...subcategorySet]
        }))
        .sort((a, b) => a.id.localeCompare(b.id));
}

function setCategorySelectionMapFromArray(rawSelection) {
    const normalized = normalizeCategorySelection(rawSelection);
    const tree = buildCategoryTree(categoryTaxonomyItems);
    const validCategories = new Map(tree.map((category) => [
        category.id,
        new Set(category.subcategories.map((subcategory) => subcategory.id))
    ]));

    categorySelectionMap = new Map();

    normalized.forEach((entry) => {
        const allowedSubcategories = validCategories.get(entry.id);
        if (!allowedSubcategories) {
            return;
        }

        const subcategorySet = new Set(
            entry.subcategoryIds.filter((subcategoryId) => allowedSubcategories.has(subcategoryId))
        );

        categorySelectionMap.set(entry.id, subcategorySet);
    });
}

function getCategorySelectionSnapshot() {
    return [...categorySelectionMap.entries()]
        .map(([id, subcategories]) => ({
            id,
            subcategoryIds: [...subcategories]
        }))
        .sort((a, b) => a.id.localeCompare(b.id));
}

function getCategorySelectionValidation() {
    const tree = buildCategoryTree(categoryTaxonomyItems);
    const categoryMap = new Map(tree.map((category) => [category.id, category]));

    const selectedCategories = [...categorySelectionMap.keys()].filter((categoryId) => categoryMap.has(categoryId));
    const categoriesWithoutSubcategories = selectedCategories.filter((categoryId) => {
        const subcategories = categorySelectionMap.get(categoryId);
        return !subcategories || subcategories.size === 0;
    });

    let selectedSubcategoryCount = 0;
    selectedCategories.forEach((categoryId) => {
        const subcategories = categorySelectionMap.get(categoryId);
        selectedSubcategoryCount += subcategories ? subcategories.size : 0;
    });

    return {
        selectedCategoryCount: selectedCategories.length,
        selectedSubcategoryCount,
        categoriesWithoutSubcategories,
        isValid: categoriesWithoutSubcategories.length === 0,
        hasSelection: selectedCategories.length > 0
    };
}

function updateCategorySelectionSummary() {
    updateCategorySelectionPreview();

    if (!elements.categorySelectionSummary) {
        return;
    }

    const validation = getCategorySelectionValidation();

    if (!validation.hasSelection) {
        elements.categorySelectionSummary.textContent = "No categories selected.";
        return;
    }

    if (!validation.isValid) {
        elements.categorySelectionSummary.textContent = `${validation.categoriesWithoutSubcategories.length} selected category(ies) need at least one subcategory.`;
        return;
    }

    elements.categorySelectionSummary.textContent = `${validation.selectedCategoryCount} categories and ${validation.selectedSubcategoryCount} subcategories selected.`;
}

function buildCategorySelectionPreviewText() {
    const snapshot = getCategorySelectionSnapshot();
    if (snapshot.length === 0) {
        return "No categories selected.";
    }

    const tree = buildCategoryTree(categoryTaxonomyItems);
    const categoryMap = new Map();
    const subcategoryMapByCategory = new Map();

    tree.forEach((category) => {
        categoryMap.set(category.id, category);

        const subcategoryMap = new Map();
        category.subcategories.forEach((subcategory) => {
            subcategoryMap.set(subcategory.id, subcategory);
        });
        subcategoryMapByCategory.set(category.id, subcategoryMap);
    });

    let totalSubcategories = 0;
    const lines = [];

    snapshot.forEach((entry) => {
        const category = categoryMap.get(entry.id);
        const categoryName = category && category.name ? category.name : entry.id;
        const subcategoryIds = Array.isArray(entry.subcategoryIds) ? entry.subcategoryIds : [];

        totalSubcategories += subcategoryIds.length;
        lines.push(`- ${categoryName} [${entry.id}]`);

        if (subcategoryIds.length === 0) {
            lines.push("  Subcategories: none selected");
            return;
        }

        const subcategoryMap = subcategoryMapByCategory.get(entry.id) || new Map();
        const namedSubcategories = subcategoryIds.map((subcategoryId) => {
            const subcategory = subcategoryMap.get(subcategoryId);
            const subcategoryName = subcategory && subcategory.name ? subcategory.name : subcategoryId;
            return `${subcategoryName} [${subcategoryId}]`;
        });

        lines.push(`  Subcategories (${subcategoryIds.length}): ${namedSubcategories.join(", ")}`);
    });

    return `Categories: ${snapshot.length}\nSubcategories: ${totalSubcategories}\n\n${lines.join("\n")}`;
}

function updateCategorySelectionPreview() {
    if (!elements.categorySelectionPreview) {
        return;
    }

    elements.categorySelectionPreview.textContent = buildCategorySelectionPreviewText();
}

function renderCategorySelection() {
    if (!elements.categorySelectionList) {
        return;
    }

    const tree = buildCategoryTree(categoryTaxonomyItems);
    elements.categorySelectionList.innerHTML = "";

    if (tree.length === 0) {
        const empty = document.createElement("p");
        empty.className = "category-selection-empty";
        empty.textContent = "Category taxonomy is not available.";
        elements.categorySelectionList.appendChild(empty);
        updateCategorySelectionSummary();
        return;
    }

    tree.forEach((category) => {
        const categoryItem = document.createElement("article");
        categoryItem.className = "category-item";

        const header = document.createElement("label");
        header.className = "category-item-header";

        const categoryCheck = document.createElement("input");
        categoryCheck.type = "checkbox";
        categoryCheck.dataset.categoryId = category.id;
        categoryCheck.checked = categorySelectionMap.has(category.id);

        const categoryText = document.createElement("span");
        categoryText.textContent = category.name;

        header.appendChild(categoryCheck);
        header.appendChild(categoryText);
        categoryItem.appendChild(header);

        const subcategoryList = document.createElement("div");
        subcategoryList.className = "subcategory-list";

        category.subcategories.forEach((subcategory) => {
            const subLabel = document.createElement("label");
            subLabel.className = "subcategory-item";

            const subCheck = document.createElement("input");
            subCheck.type = "checkbox";
            subCheck.dataset.categoryId = category.id;
            subCheck.dataset.subcategoryId = subcategory.id;

            const selectedSubcategories = categorySelectionMap.get(category.id) || new Set();
            subCheck.checked = selectedSubcategories.has(subcategory.id);

            const subText = document.createElement("span");
            subText.textContent = subcategory.name;

            subLabel.appendChild(subCheck);
            subLabel.appendChild(subText);
            subcategoryList.appendChild(subLabel);
        });

        categoryItem.appendChild(subcategoryList);
        elements.categorySelectionList.appendChild(categoryItem);
    });

    updateCategorySelectionSummary();
}

async function loadCategoryTaxonomyFromDesktop() {
    if (!mmfDesktopApi || !mmfDesktopApi.getCategoryTaxonomy) {
        categoryTaxonomyItems = [];
        renderCategorySelection();
        return;
    }

    try {
        const response = await mmfDesktopApi.getCategoryTaxonomy();
        if (!response || !response.ok || !Array.isArray(response.items)) {
            categoryTaxonomyItems = [];
            renderCategorySelection();
            return;
        }

        categoryTaxonomyItems = normalizeCategoryTaxonomy(response.items).filter((item) => item.is_active !== false);
        setCategorySelectionMapFromArray(getCategorySelectionSnapshot());
        renderCategorySelection();
    } catch (_error) {
        categoryTaxonomyItems = [];
        renderCategorySelection();
    }
}

function normalizeModelEntry(entry) {
    if (typeof entry === "string") {
        const id = entry.trim();
        return id
            ? {
                id,
                name: "",
                creatorId: "",
                creatorName: "",
                creatorUsername: ""
            }
            : null;
    }

    if (!entry || typeof entry !== "object") {
        return null;
    }

    const id = String(entry.id || "").trim();
    if (!id) {
        return null;
    }

    return {
        id,
        name: typeof entry.name === "string" ? entry.name.trim() : "",
        creatorId: entry.creatorId !== undefined && entry.creatorId !== null
            ? String(entry.creatorId).trim()
            : "",
        creatorName: typeof entry.creatorName === "string" ? entry.creatorName.trim() : "",
        creatorUsername: typeof entry.creatorUsername === "string" ? entry.creatorUsername.trim() : ""
    };
}

function mergeModelEntries(existingEntries, incomingEntries) {
    const merged = new Map();

    existingEntries.forEach((entry) => {
        const normalized = normalizeModelEntry(entry);
        if (normalized) {
            merged.set(normalized.id, normalized);
        }
    });

    incomingEntries.forEach((entry) => {
        const normalized = normalizeModelEntry(entry);
        if (!normalized) {
            return;
        }

        const current = merged.get(normalized.id);
        if (!current) {
            merged.set(normalized.id, normalized);
            return;
        }

        if (!current.name && normalized.name) {
            current.name = normalized.name;
        }

        if (!current.creatorId && normalized.creatorId) {
            current.creatorId = normalized.creatorId;
        }

        if (!current.creatorName && normalized.creatorName) {
            current.creatorName = normalized.creatorName;
        }

        if (!current.creatorUsername && normalized.creatorUsername) {
            current.creatorUsername = normalized.creatorUsername;
        }
    });

    return [...merged.values()];
}

const pendingRunResolvers = new Map();

function parseModelIds(inputText) {
    const lines = inputText.split(/\r?\n/);
    const validIds = [];
    const invalidLines = [];
    const duplicateIds = [];
    const seen = new Set();

    lines.forEach((line, idx) => {
        const value = line.trim();
        if (!value) {
            return;
        }

        if (!/^\d+$/.test(value)) {
            invalidLines.push({ line: idx + 1, value });
            return;
        }

        if (seen.has(value)) {
            duplicateIds.push(value);
            return;
        }

        seen.add(value);
        validIds.push(value);
    });

    return {
        validIds,
        invalidLines,
        duplicateIds: [...new Set(duplicateIds)]
    };
}

function parseModelIdTokens(inputText) {
    return String(inputText || "")
        .split(/[\s,;]+/)
        .map((token) => token.trim())
        .filter((token) => token.length > 0);
}

function getOrderedValidModelIds() {
    const sourceText = elements.idsInput ? elements.idsInput.value : "";
    return parseModelIds(sourceText).validIds;
}

function getCompletedModelIdSet() {
    return new Set(sanitizeNumericIdList(batchProgressState.completedIds));
}

function getPendingModelIds() {
    const orderedIds = getOrderedValidModelIds();
    const completed = getCompletedModelIdSet();
    return orderedIds.filter((id) => !completed.has(id));
}

function getCurrentBatchLimit() {
    const mode = getBatchSizeSelection();
    if (mode === "all") {
        return Number.POSITIVE_INFINITY;
    }

    const parsed = Number.parseInt(mode, 10);
    return Number.isNaN(parsed) || parsed <= 0 ? 25 : parsed;
}

function getNextBatchPlan() {
    const pendingIds = getPendingModelIds();
    const limit = getCurrentBatchLimit();
    const ids = Number.isFinite(limit)
        ? pendingIds.slice(0, limit)
        : pendingIds;

    return {
        ids,
        totalCount: getOrderedValidModelIds().length,
        pendingCount: pendingIds.length,
        completedCount: getCompletedModelIdSet().size,
        batchMode: getBatchSizeSelection()
    };
}

function reconcileBatchProgressWithCurrentIds() {
    const allowedIds = new Set(getOrderedValidModelIds());
    const nextCompleted = sanitizeNumericIdList(batchProgressState.completedIds)
        .filter((id) => allowedIds.has(id));
    const nextInProgressIds = sanitizeNumericIdList(batchProgressState.inProgressIds)
        .filter((id) => allowedIds.has(id));

    batchProgressState.completedIds = nextCompleted;
    batchProgressState.inProgressIds = nextInProgressIds;

    if (batchProgressState.inProgress && nextInProgressIds.length === 0) {
        batchProgressState.inProgress = false;
    }

    updateBatchStatusUi();
    renderModelIdList();
    renderDownloadRootHistory();
}

function updateBatchStatusUi() {
    if (!elements.batchStatus) {
        return;
    }

    const ordered = getOrderedValidModelIds();
    const totalCount = ordered.length;
    const completedCount = getCompletedModelIdSet().size;
    const pendingCount = Math.max(totalCount - completedCount, 0);
    const mode = getBatchSizeSelection();

    if (totalCount === 0) {
        elements.batchStatus.textContent = "Load model IDs to initialize batch progress.";
        return;
    }

    if (batchProgressState.inProgress) {
        const inProgressCount = sanitizeNumericIdList(batchProgressState.inProgressIds).length;
        elements.batchStatus.textContent = `Batch running (${inProgressCount} model(s) in progress). Completed ${completedCount}/${totalCount}, pending ${pendingCount}.`;
        return;
    }

    const nextBatchPlan = getNextBatchPlan();
    const modeLabel = mode === "all" ? "all pending" : mode;

    if (pendingCount === 0) {
        elements.batchStatus.textContent = `All selected models are already completed (${completedCount}/${totalCount}).`;
        return;
    }

    const lastErrorSuffix = batchProgressState.lastStatus === "failed" || batchProgressState.lastStatus === "interrupted"
        ? ` Last issue: ${batchProgressState.lastError || "pipeline did not finish."}`
        : "";

    elements.batchStatus.textContent = `Batch mode ${modeLabel}. Completed ${completedCount}/${totalCount}, pending ${pendingCount}. Next run downloads ${nextBatchPlan.ids.length} model(s).${lastErrorSuffix}`;
}

function renderDownloadRootHistory() {
    if (!elements.downloadHistoryList) {
        return;
    }

    elements.downloadHistoryList.innerHTML = "";
    const history = sanitizeDownloadRootHistory(downloadRootHistory);

    if (history.length === 0) {
        const emptyItem = document.createElement("li");
        emptyItem.className = "download-history-item download-history-empty";
        emptyItem.textContent = "No saved folders yet.";
        elements.downloadHistoryList.appendChild(emptyItem);
        return;
    }

    history.forEach((folderPath) => {
        const item = document.createElement("li");
        item.className = "download-history-item";

        const pathLabel = document.createElement("span");
        pathLabel.className = "download-history-path";
        pathLabel.textContent = folderPath;
        pathLabel.title = folderPath;

        const openBtn = document.createElement("button");
        openBtn.type = "button";
        openBtn.className = "btn btn-secondary btn-inline";
        openBtn.dataset.path = folderPath;
        openBtn.textContent = "Open";

        item.appendChild(pathLabel);
        item.appendChild(openBtn);
        elements.downloadHistoryList.appendChild(item);
    });
}

function rememberDownloadRoot(pathValue, options = {}) {
    const normalizedPath = String(pathValue || "").trim();
    if (!normalizedPath) {
        return;
    }

    const isLikelyWindowsPath = /^[a-z]:\\/i.test(normalizedPath) || normalizedPath.includes("\\");
    const caseSensitive = !(runtimePlatform === "win32" || isLikelyWindowsPath);
    const existing = sanitizeDownloadRootHistory(downloadRootHistory)
        .filter((entry) => {
            if (caseSensitive) {
                return entry !== normalizedPath;
            }

            return entry.toLowerCase() !== normalizedPath.toLowerCase();
        });

    downloadRootHistory = [normalizedPath, ...existing].slice(0, DOWNLOAD_HISTORY_LIMIT);
    renderDownloadRootHistory();

    if (options.save !== false) {
        scheduleSettingsSave();
    }
}

function removeDownloadRootFromHistory(pathValue, options = {}) {
    const normalizedPath = String(pathValue || "").trim();
    if (!normalizedPath) {
        return false;
    }

    const isLikelyWindowsPath = /^[a-z]:\\/i.test(normalizedPath) || normalizedPath.includes("\\");
    const caseSensitive = !(runtimePlatform === "win32" || isLikelyWindowsPath);
    const beforeCount = sanitizeDownloadRootHistory(downloadRootHistory).length;

    downloadRootHistory = sanitizeDownloadRootHistory(downloadRootHistory)
        .filter((entry) => {
            if (caseSensitive) {
                return entry !== normalizedPath;
            }

            return entry.toLowerCase() !== normalizedPath.toLowerCase();
        });

    const removed = beforeCount !== downloadRootHistory.length;
    if (removed) {
        renderDownloadRootHistory();
        if (options.save !== false) {
            scheduleSettingsSave();
        }
    }

    return removed;
}

function isDownloadRootLocked() {
    return Boolean(activeRunId) || pipelineRunning || batchProgressState.inProgress;
}

function isModelListMutationLocked() {
    return isDownloadRootLocked();
}

function getModelEntryLabelById(modelId) {
    const entry = modelIdEntries.find((item) => item && item.id === modelId);
    if (!entry) {
        return modelId;
    }

    return entry.name ? `${entry.name} (${modelId})` : modelId;
}

function getPipelineBatchIdSet() {
    if (activeBatchPlan && Array.isArray(activeBatchPlan.ids)) {
        return new Set(sanitizeNumericIdList(activeBatchPlan.ids));
    }

    if (batchProgressState.inProgress) {
        return new Set(sanitizeNumericIdList(batchProgressState.inProgressIds));
    }

    return new Set();
}

function isModelRowCompletedForDisplay(modelId) {
    return getCompletedModelIdSet().has(modelId) || sessionPipelineCompletedIds.has(modelId);
}

function stripAnsiFromLogLine(text) {
    return String(text || "").replace(/\x1b\[[0-9;]*m/g, "");
}

function resetPipelineProgressUi() {
    pipelineProgressState = createDefaultPipelineProgressState();
    sessionPipelineCompletedIds.clear();
    renderPipelineProgressUi();
}

function beginPipelineProgressUi(batchPlan, options = {}) {
    const batchIds = sanitizeNumericIdList(batchPlan && batchPlan.ids ? batchPlan.ids : []);
    sessionPipelineCompletedIds.clear();
    pipelineProgressState = {
        visible: true,
        phase: options.phase || "starting",
        percent: 0,
        label: "Preparing pipeline…",
        detail: batchIds.length > 0
            ? `Batch of ${batchIds.length} model(s). Metadata download starts next.`
            : "Waiting for workflow output…",
        metadataTotal: batchIds.length,
        metadataDone: 0,
        batchTotal: batchIds.length,
        batchModelsDone: 0,
        step2CurrentModelId: ""
    };
    renderPipelineProgressUi();
}

function setPipelineProgressPhase(phase, label, detail) {
    pipelineProgressState.visible = true;
    pipelineProgressState.phase = phase;
    if (label) {
        pipelineProgressState.label = label;
    }
    if (detail) {
        pipelineProgressState.detail = detail;
    }
    renderPipelineProgressUi();
}

function computePipelineProgressPercent() {
    const { phase, metadataTotal, metadataDone, batchTotal, batchModelsDone } = pipelineProgressState;

    if (phase === "metadata") {
        if (metadataTotal > 0) {
            return Math.min(100, Math.round((metadataDone / metadataTotal) * 28));
        }

        return 4;
    }

    if (phase === "step2-test") {
        return 32;
    }

    if (phase === "step2-full") {
        if (batchTotal > 0) {
            return Math.min(100, 30 + Math.round((batchModelsDone / batchTotal) * 68));
        }

        return 40;
    }

    if (phase === "done") {
        return 100;
    }

    if (phase === "failed" || phase === "interrupted") {
        return pipelineProgressState.percent;
    }

    return pipelineProgressState.percent;
}

function renderPipelineProgressUi() {
    if (!elements.pipelineProgressPanel) {
        return;
    }

    if (!pipelineProgressState.visible) {
        elements.pipelineProgressPanel.classList.add("hidden");
        return;
    }

    elements.pipelineProgressPanel.classList.remove("hidden");
    pipelineProgressState.percent = computePipelineProgressPercent();

    if (elements.pipelineProgressLabel) {
        elements.pipelineProgressLabel.textContent = pipelineProgressState.label || "Pipeline progress";
    }

    if (elements.pipelineProgressPercent) {
        elements.pipelineProgressPercent.textContent = `${pipelineProgressState.percent}%`;
    }

    if (elements.pipelineProgressBar) {
        elements.pipelineProgressBar.style.width = `${pipelineProgressState.percent}%`;
    }

    if (elements.pipelineProgressDetail) {
        elements.pipelineProgressDetail.textContent = pipelineProgressState.detail || "";
    }
}

function markPipelineBatchModelDone(modelId) {
    const normalizedId = String(modelId || "").trim();
    const batchIds = getPipelineBatchIdSet();
    if (!/^\d+$/.test(normalizedId) || (batchIds.size > 0 && !batchIds.has(normalizedId))) {
        return;
    }

    if (sessionPipelineCompletedIds.has(normalizedId)) {
        return;
    }

    sessionPipelineCompletedIds.add(normalizedId);
    pipelineProgressState.batchModelsDone = sessionPipelineCompletedIds.size;
    pipelineProgressState.label = "Downloading and packaging models";
    pipelineProgressState.detail = batchIds.size > 0
        ? `Model ${sessionPipelineCompletedIds.size}/${batchIds.size} finished (ZIP ready): ${getModelEntryLabelById(normalizedId)}`
        : `Model finished (ZIP ready): ${getModelEntryLabelById(normalizedId)}`;
    renderPipelineProgressUi();
    renderModelIdList();
}

function feedPipelineProgressFromLog(text) {
    if (!pipelineProgressState.visible || !text) {
        return;
    }

    const lines = String(text).split(/\r?\n/);
    lines.forEach((rawLine) => {
        const line = stripAnsiFromLogLine(rawLine).trim();
        if (!line) {
            return;
        }

        const metadataTotalMatch = line.match(/Starting download of (\d+) model metadata/i);
        if (metadataTotalMatch) {
            pipelineProgressState.metadataTotal = Number.parseInt(metadataTotalMatch[1], 10) || pipelineProgressState.metadataTotal;
            pipelineProgressState.phase = "metadata";
            pipelineProgressState.label = "Downloading JSON metadata";
            pipelineProgressState.detail = `Preparing ${pipelineProgressState.metadataTotal} metadata file(s)…`;
            renderPipelineProgressUi();
            return;
        }

        const metadataProgressMatch = line.match(/\[(\d+)\/(\d+)\].*model\s+(\d+)/i);
        if (metadataProgressMatch) {
            const current = Number.parseInt(metadataProgressMatch[1], 10);
            const total = Number.parseInt(metadataProgressMatch[2], 10);
            const modelId = metadataProgressMatch[3];
            const isSkip = /Skipping model/i.test(line);
            pipelineProgressState.phase = "metadata";
            pipelineProgressState.metadataTotal = total || pipelineProgressState.metadataTotal;
            pipelineProgressState.metadataDone = Number.isNaN(current) ? pipelineProgressState.metadataDone : current;
            pipelineProgressState.label = "Downloading JSON metadata";
            pipelineProgressState.detail = isSkip
                ? `Metadata ${pipelineProgressState.metadataDone}/${pipelineProgressState.metadataTotal} — skipped (already exists): ${getModelEntryLabelById(modelId)}`
                : `Metadata ${pipelineProgressState.metadataDone}/${pipelineProgressState.metadataTotal} — model ${getModelEntryLabelById(modelId)}`;
            renderPipelineProgressUi();
            return;
        }

        const metadataSavedMatch = line.match(/Successfully downloaded metadata for model\s+(\d+)/i);
        if (metadataSavedMatch) {
            const modelId = metadataSavedMatch[1];
            const total = pipelineProgressState.metadataTotal || pipelineProgressState.batchTotal;
            pipelineProgressState.metadataDone = Math.min(
                total || pipelineProgressState.metadataDone + 1,
                (pipelineProgressState.metadataDone || 0) + 1
            );
            pipelineProgressState.phase = "metadata";
            pipelineProgressState.label = "Downloading JSON metadata";
            pipelineProgressState.detail = `Saved metadata for ${getModelEntryLabelById(modelId)} (${pipelineProgressState.metadataDone}/${total || "?"})`;
            renderPipelineProgressUi();
            return;
        }

        const jsonCountMatch = line.match(/Found (\d+) JSON files to process/i);
        if (jsonCountMatch) {
            pipelineProgressState.phase = "step2-full";
            pipelineProgressState.label = "Downloading models (STL/ZIP)";
            pipelineProgressState.detail = `Scanning ${jsonCountMatch[1]} metadata file(s) in the download folder.`;
            renderPipelineProgressUi();
            return;
        }

        const processingMatch = line.match(/\[(\d+)\/(\d+)\]\s+Processing model\s+(\d+)/i);
        if (processingMatch) {
            const modelId = processingMatch[3];
            if (pipelineProgressState.step2CurrentModelId
                && pipelineProgressState.step2CurrentModelId !== modelId) {
                markPipelineBatchModelDone(pipelineProgressState.step2CurrentModelId);
            }

            pipelineProgressState.phase = "step2-full";
            pipelineProgressState.step2CurrentModelId = modelId;
            pipelineProgressState.label = "Downloading and packaging models";
            const batchIds = getPipelineBatchIdSet();
            const inBatch = batchIds.size === 0 || batchIds.has(modelId);
            const batchPosition = inBatch && batchIds.size > 0
                ? `${sessionPipelineCompletedIds.size + 1}/${batchIds.size}`
                : `${processingMatch[1]}/${processingMatch[2]}`;
            pipelineProgressState.detail = inBatch
                ? `Working on batch model ${batchPosition}: ${getModelEntryLabelById(modelId)} (files + ZIP)`
                : `Processing ${processingMatch[1]}/${processingMatch[2]}: ${getModelEntryLabelById(modelId)}`;
            renderPipelineProgressUi();
            return;
        }

        if (/\[OK\]\s+Created .+\.zip/i.test(line) || /\[SKIP\]\s+Model assets already archived/i.test(line)) {
            if (pipelineProgressState.step2CurrentModelId) {
                markPipelineBatchModelDone(pipelineProgressState.step2CurrentModelId);
            }
            return;
        }

        if (/Download Complete!/i.test(line)) {
            if (pipelineProgressState.step2CurrentModelId) {
                markPipelineBatchModelDone(pipelineProgressState.step2CurrentModelId);
                pipelineProgressState.step2CurrentModelId = "";
            }

            pipelineProgressState.phase = "step2-full";
            pipelineProgressState.label = "Step 2 finished";
            pipelineProgressState.detail = "All model folders processed for this run.";
            renderPipelineProgressUi();
        }
    });
}

function unlockModelSearchControls() {
    if (elements.modelSearchInput) {
        elements.modelSearchInput.disabled = false;
        elements.modelSearchInput.readOnly = false;
    }

    if (elements.modelSearchClearBtn) {
        elements.modelSearchClearBtn.disabled = false;
    }
}

function syncIdsTextareaFromEntries() {
    if (!elements.idsInput) {
        return;
    }

    elements.idsInput.value = modelIdEntries.map((entry) => entry.id).join("\n");
}

function getModelIdCatalogSnapshot() {
    return modelIdEntries
        .filter((entry) => entry && /^\d+$/.test(entry.id))
        .map((entry) => ({
            id: entry.id,
            name: entry.name || "",
            creatorId: entry.creatorId || "",
            creatorName: entry.creatorName || "",
            creatorUsername: entry.creatorUsername || ""
        }));
}

function normalizeSearchQueryValue(value) {
    return String(value || "")
        .toLowerCase()
        .trim();
}

function getFilteredModelEntryRows() {
    const query = normalizeSearchQueryValue(modelSearchQuery);
    const rows = modelIdEntries.map((entry, index) => ({ entry, index }));

    if (!query) {
        return rows;
    }

    return rows.filter(({ entry }) => {
        const creatorUsername = entry.creatorUsername
            ? entry.creatorUsername.replace(/^@+/, "")
            : "";

        const searchable = [
            entry.id,
            entry.name,
            entry.creatorId,
            entry.creatorName,
            creatorUsername
        ]
            .join(" ")
            .toLowerCase();

        return searchable.includes(query);
    });
}

function getModelListPageCount() {
    const filteredTotal = getFilteredModelEntryRows().length;
    if (filteredTotal === 0) {
        return 1;
    }

    return Math.ceil(filteredTotal / MODEL_LIST_UI_PAGE_SIZE);
}

function clampModelListUiPage() {
    const pageCount = getModelListPageCount();
    if (modelListUiPage < 1) {
        modelListUiPage = 1;
    }
    if (modelListUiPage > pageCount) {
        modelListUiPage = pageCount;
    }
}

function updateModelListPaginationUi() {
    if (!elements.modelListPagination) {
        return;
    }

    const total = getFilteredModelEntryRows().length;
    const pageCount = getModelListPageCount();
    const showPagination = total > MODEL_LIST_UI_PAGE_SIZE;

    elements.modelListPagination.classList.toggle("hidden", !showPagination);

    if (elements.modelListPageInfo) {
        elements.modelListPageInfo.textContent = `Page ${modelListUiPage} of ${pageCount}`;
    }

    if (elements.modelListTotalInfo) {
        const start = total === 0 ? 0 : (modelListUiPage - 1) * MODEL_LIST_UI_PAGE_SIZE + 1;
        const end = Math.min(modelListUiPage * MODEL_LIST_UI_PAGE_SIZE, total);
        elements.modelListTotalInfo.textContent = total === 0
            ? ""
            : `Showing ${start}–${end} of ${total}`;
    }

    if (elements.modelListPrevBtn) {
        elements.modelListPrevBtn.disabled = !showPagination || modelListUiPage <= 1;
    }

    if (elements.modelListNextBtn) {
        elements.modelListNextBtn.disabled = !showPagination || modelListUiPage >= pageCount;
    }
}

function renderModelIdList() {
    if (!elements.modelIdList) {
        return;
    }

    elements.modelIdList.innerHTML = "";
    clampModelListUiPage();

    const filteredRows = getFilteredModelEntryRows();

    const countById = new Map();
    modelIdEntries.forEach((entry) => {
        countById.set(entry.id, (countById.get(entry.id) || 0) + 1);
    });

    if (modelIdEntries.length === 0) {
        const emptyItem = document.createElement("li");
        emptyItem.className = "model-id-row model-id-row-empty";
        emptyItem.textContent = "No models loaded yet. Capture session, then click Auto load my IDs.";
        elements.modelIdList.appendChild(emptyItem);
        updateModelListPaginationUi();
        return;
    }

    if (filteredRows.length === 0) {
        const emptyItem = document.createElement("li");
        emptyItem.className = "model-id-row model-id-row-empty";
        emptyItem.textContent = "No rows match the current search. Try creator name, creator username, creator ID, model name, or model ID.";
        elements.modelIdList.appendChild(emptyItem);
        updateModelListPaginationUi();
        return;
    }

    const listLocked = isModelListMutationLocked();

    const pageStart = (modelListUiPage - 1) * MODEL_LIST_UI_PAGE_SIZE;
    const pageEntries = filteredRows.slice(pageStart, pageStart + MODEL_LIST_UI_PAGE_SIZE);

    pageEntries.forEach(({ entry, index }) => {
        const row = document.createElement("li");
        row.classList.add("model-id-row");

        const isNumeric = /^\d+$/.test(entry.id);
        const isDuplicate = (countById.get(entry.id) || 0) > 1;
        const isCompleted = isModelRowCompletedForDisplay(entry.id);

        if (!isNumeric) {
            row.classList.add("model-id-row-invalid");
        } else if (isDuplicate) {
            row.classList.add("model-id-row-duplicate");
        }
        if (isCompleted) {
            row.classList.add("model-id-row-completed");
        }

        const idCell = document.createElement("span");
        idCell.className = "model-id-row-id";
        idCell.textContent = entry.id;

        const nameCell = document.createElement("div");
        nameCell.className = "model-id-row-name-group";

        const modelName = document.createElement("span");
        modelName.className = "model-id-row-name";
        modelName.textContent = entry.name || "—";

        const creatorMeta = document.createElement("div");
        creatorMeta.className = "model-id-row-creator";
        const creatorLabel = entry.creatorName || "Unknown creator";
        const creatorIdLabel = entry.creatorId || "—";
        const creatorUsername = entry.creatorUsername
            ? ` @${entry.creatorUsername.replace(/^@+/, "")}`
            : "";

        const creatorIdChip = document.createElement("span");
        creatorIdChip.className = "model-id-row-creator-id";
        creatorIdChip.textContent = `ID ${creatorIdLabel}`;

        const creatorDetails = document.createElement("span");
        creatorDetails.className = "model-id-row-creator-details";
        creatorDetails.textContent = `${creatorLabel}${creatorUsername}`;

        creatorMeta.appendChild(creatorIdChip);
        creatorMeta.appendChild(creatorDetails);

        nameCell.appendChild(modelName);
        nameCell.appendChild(creatorMeta);

        const removeBtn = document.createElement("button");
        removeBtn.type = "button";
        removeBtn.className = "model-id-row-remove";
        removeBtn.textContent = "Remove";
        removeBtn.dataset.rowIndex = String(index);
        removeBtn.setAttribute("aria-label", `Remove model ${entry.name || entry.id}`);
        removeBtn.disabled = listLocked;
        if (listLocked) {
            removeBtn.title = "Cannot remove models while a pipeline is running.";
        }

        row.appendChild(idCell);
        row.appendChild(nameCell);
        row.appendChild(removeBtn);
        elements.modelIdList.appendChild(row);
    });

    updateModelListPaginationUi();
}

function setModelIdEntriesFromText(inputText, catalog = []) {
    const tokens = parseModelIdTokens(inputText);
    const catalogMap = new Map();

    (Array.isArray(catalog) ? catalog : []).forEach((entry) => {
        const normalized = normalizeModelEntry(entry);
        if (normalized) {
            catalogMap.set(normalized.id, normalized);
        }
    });

    modelIdEntries = tokens.map((id) => {
        const catalogEntry = catalogMap.get(id);
        return {
            id,
            name: catalogEntry ? catalogEntry.name || "" : "",
            creatorId: catalogEntry ? catalogEntry.creatorId || "" : "",
            creatorName: catalogEntry ? catalogEntry.creatorName || "" : "",
            creatorUsername: catalogEntry ? catalogEntry.creatorUsername || "" : ""
        };
    });

    modelListUiPage = 1;
    syncIdsTextareaFromEntries();
    reconcileBatchProgressWithCurrentIds();
    renderModelIdList();
}

function setModelIdEntriesFromCatalog(items) {
    const normalizedItems = (Array.isArray(items) ? items : [])
        .map((entry) => normalizeModelEntry(entry))
        .filter(Boolean);

    modelIdEntries = mergeModelEntries([], normalizedItems);
    modelListUiPage = 1;
    syncIdsTextareaFromEntries();
    reconcileBatchProgressWithCurrentIds();
    renderModelIdList();
}

function setupModelIdList() {
    if (!elements.modelIdList || !elements.idsInput) {
        return;
    }

    if (elements.modelSearchInput) {
        elements.modelSearchInput.addEventListener("input", () => {
            modelSearchQuery = elements.modelSearchInput.value;
            modelListUiPage = 1;
            renderModelIdList();
        });
    }

    if (elements.modelSearchClearBtn) {
        elements.modelSearchClearBtn.addEventListener("click", () => {
            modelSearchQuery = "";
            if (elements.modelSearchInput) {
                elements.modelSearchInput.value = "";
            }
            modelListUiPage = 1;
            renderModelIdList();
        });
    }

    if (elements.modelListPrevBtn) {
        elements.modelListPrevBtn.addEventListener("click", () => {
            if (modelListUiPage > 1) {
                modelListUiPage -= 1;
                renderModelIdList();
            }
        });
    }

    if (elements.modelListNextBtn) {
        elements.modelListNextBtn.addEventListener("click", () => {
            if (modelListUiPage < getModelListPageCount()) {
                modelListUiPage += 1;
                renderModelIdList();
            }
        });
    }

    elements.modelIdList.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) {
            return;
        }

        const removeBtn = target.closest(".model-id-row-remove");
        if (!removeBtn) {
            return;
        }

        if (isModelListMutationLocked()) {
            setStatus("Cannot remove models while a pipeline is running.", "warn");
            return;
        }

        const index = Number.parseInt(removeBtn.dataset.rowIndex || "", 10);
        if (Number.isNaN(index) || index < 0 || index >= modelIdEntries.length) {
            return;
        }

        modelIdEntries.splice(index, 1);
        clampModelListUiPage();
        syncIdsTextareaFromEntries();
        reconcileBatchProgressWithCurrentIds();
        renderModelIdList();
        refreshDashboard();
        scheduleSettingsSave();
    });
}

function updateSessionStatusBadge(result) {
    if (!elements.sessionStatus) {
        return;
    }

    elements.sessionStatus.classList.remove(
        "session-status-ok",
        "session-status-warn",
        "session-status-bad",
        "session-status-unknown"
    );

    if (!result) {
        elements.sessionStatus.classList.add("session-status-unknown");
        elements.sessionStatus.textContent = "Session: not checked";
        return;
    }

    if (result.valid && !result.partial) {
        elements.sessionStatus.classList.add("session-status-ok");
        const captured = result.sessionCapturedAt
            ? ` (saved ${new Date(result.sessionCapturedAt).toLocaleString()})`
            : "";
        elements.sessionStatus.textContent = `Session: valid${captured}`;
        return;
    }

    if (result.valid && result.partial) {
        elements.sessionStatus.classList.add("session-status-warn");
        elements.sessionStatus.textContent = `Session: partial — ${result.message || "needs JWT or publishable key"}`;
        return;
    }

    elements.sessionStatus.classList.add("session-status-bad");
    elements.sessionStatus.textContent = `Session: invalid — ${result.message || "sign in again"}`;
}

async function checkMmfSessionFromUi(silent = false) {
    if (!mmfDesktopApi || !mmfDesktopApi.validateMmfSession) {
        if (!silent) {
            setStatus("Session check is available only in desktop mode.", "warn");
        }
        return null;
    }

    try {
        const result = await mmfDesktopApi.validateMmfSession();
        updateSessionStatusBadge(result);

        if (!silent) {
            if (result && result.valid) {
                setStatus(result.message || "Session looks valid.", result.partial ? "warn" : "ok");
            } else if (result && result.expired) {
                clearSessionFieldsInForm();
                setStatus(result.message || "Session expired. Sign in and capture again.", "bad");
                refreshDashboard();
                scheduleSettingsSave();
            } else {
                setStatus(result && result.message ? result.message : "Session is not ready.", "warn");
            }
        } else if (result && result.expired) {
            clearSessionFieldsInForm();
            refreshDashboard();
            scheduleSettingsSave();
        }

        return result;
    } catch (err) {
        if (!silent) {
            setStatus(`Session check failed: ${String(err?.message || err)}`, "bad");
        }
        return null;
    }
}

function clearSessionFieldsInForm() {
    elements.phpSessidInput.value = "";
    elements.cfClearanceInput.value = "";
    elements.jwtInput.value = "";
    elements.publishableKeyInput.value = "";
}

function normalizeCookieFieldValue(value, cookieName) {
    let normalized = typeof value === "string" ? value.trim() : "";
    normalized = normalized.replace(/^cookie\s*:\s*/i, "");

    if (cookieName) {
        const prefix = new RegExp(`^${cookieName}\\s*=\\s*`, "i");
        normalized = normalized.replace(prefix, "").trim();
    }

    return normalized;
}

function parseLegacyCookie(cookieHeader) {
    const normalized = typeof cookieHeader === "string"
        ? cookieHeader.trim().replace(/^cookie\s*:\s*/i, "")
        : "";

    const phpMatch = normalized.match(/(?:^|;\s*)PHPSESSID=([^;]+)/i);
    const cfMatch = normalized.match(/(?:^|;\s*)cf_clearance=([^;]+)/i);

    return {
        phpSessid: phpMatch ? phpMatch[1].trim() : "",
        cfClearance: cfMatch ? cfMatch[1].trim() : ""
    };
}

function buildCookieFromInputs() {
    const phpSessid = normalizeCookieFieldValue(elements.phpSessidInput.value, "PHPSESSID");
    const cfClearance = normalizeCookieFieldValue(elements.cfClearanceInput.value, "cf_clearance");

    const parts = [];
    if (phpSessid) {
        parts.push(`PHPSESSID=${phpSessid}`);
    }
    if (cfClearance) {
        parts.push(`cf_clearance=${cfClearance}`);
    }

    return parts.join("; ");
}

function analyzeCookie() {
    const phpSessid = normalizeCookieFieldValue(elements.phpSessidInput.value, "PHPSESSID");
    const cfClearance = normalizeCookieFieldValue(elements.cfClearanceInput.value, "cf_clearance");
    const normalized = buildCookieFromInputs();

    return {
        normalized,
        hasCookie: normalized.length > 0,
        hasPhpSession: Boolean(phpSessid),
        hasCfClearance: Boolean(cfClearance)
    };
}

function normalizeJwtValue(value) {
    return typeof value === "string"
        ? value.trim().replace(/^bearer\s+/i, "")
        : "";
}

function normalizePublishableKeyValue(value) {
    return typeof value === "string"
        ? value.trim().replace(/^x-publishable-api-key\s*:\s*/i, "")
        : "";
}

function analyzeMedusaAuth() {
    const medusaJwt = normalizeJwtValue(elements.jwtInput.value);
    const medusaPublishableKey = normalizePublishableKeyValue(elements.publishableKeyInput.value);

    return {
        medusaJwt,
        medusaPublishableKey,
        hasMedusaJwt: Boolean(medusaJwt),
        hasMedusaPublishableKey: Boolean(medusaPublishableKey)
    };
}

function buildRequirementState() {
    const idState = parseModelIds(elements.idsInput.value);
    const cookieState = analyzeCookie();
    const medusaAuthState = analyzeMedusaAuth();
    const categoryState = getCategorySelectionValidation();

    const requirements = [
        {
            label: "Cookie parts are provided",
            pass: cookieState.hasCookie,
            required: true,
            help: "Fill PHPSESSID and cf_clearance from a download request Cookie header."
        },
        {
            label: "Cookie includes PHPSESSID",
            pass: cookieState.hasPhpSession,
            required: true,
            help: "Needed for authenticated API and download requests."
        },
        {
            label: "Cookie includes cf_clearance",
            pass: cookieState.hasCfClearance,
            required: true,
            help: "Required to avoid Cloudflare HTML error pages."
        },
        {
            label: "Medusa JWT is provided",
            pass: medusaAuthState.hasMedusaJwt,
            required: false,
            help: "Needed for automatic own-catalog lookup (medusa_auth_token from Local Storage)."
        },
        {
            label: "x-publishable-api-key is provided",
            pass: medusaAuthState.hasMedusaPublishableKey,
            required: false,
            help: "Needed with JWT to call /store/customers/me and resolve your mmf_id automatically."
        },
        {
            label: "At least one model ID is present",
            pass: idState.validIds.length > 0,
            required: true,
            help: "Add at least one numeric model ID chip."
        },
        {
            label: "All non-empty lines are numeric model IDs",
            pass: idState.invalidLines.length === 0,
            required: true,
            help: "Remove invalid values from the ID chips."
        },
        {
            label: "No duplicate model IDs",
            pass: idState.duplicateIds.length === 0,
            required: false,
            help: "Duplicates are allowed but not recommended."
        },
        {
            label: "Category selection is valid",
            pass: categoryState.isValid,
            required: true,
            help: categoryState.hasSelection
                ? "Each selected category must include at least one subcategory."
                : "No category selected (optional)."
        },
        {
            label: "Enhanced Step 2 test mode is acknowledged",
            pass: elements.testModeCheck.checked,
            required: false,
            help: "Run --test first so one file validates before full download."
        }
    ];

    const requiredTotal = requirements.filter((item) => item.required).length;
    const requiredPassed = requirements.filter((item) => item.required && item.pass).length;
    const readiness = Math.round((requiredPassed / requiredTotal) * 100);

    return {
        idState,
        cookieState,
        medusaAuthState,
        categoryState,
        requirements,
        requiredTotal,
        requiredPassed,
        readiness
    };
}

function makeRequirementItem({ label, help, pass, required }) {
    const li = document.createElement("li");
    const dot = document.createElement("span");
    dot.classList.add("dot");

    if (pass) {
        dot.classList.add("dot-pass");
    } else if (required) {
        dot.classList.add("dot-fail");
    } else {
        dot.classList.add("dot-warn");
    }

    const copy = document.createElement("div");
    copy.className = "req-copy";

    const title = document.createElement("strong");
    title.textContent = label;

    const details = document.createElement("span");
    details.textContent = help;

    copy.appendChild(title);
    copy.appendChild(document.createElement("br"));
    copy.appendChild(details);

    li.appendChild(dot);
    li.appendChild(copy);

    return li;
}

function renderRequirements(requirementState) {
    elements.requirementsList.innerHTML = "";
    requirementState.requirements.forEach((item) => {
        elements.requirementsList.appendChild(makeRequirementItem(item));
    });
}

function updateStats(requirementState) {
    const { idState, readiness, requiredPassed, requiredTotal } = requirementState;

    elements.validIdCount.textContent = String(idState.validIds.length);
    elements.invalidLineCount.textContent = String(idState.invalidLines.length);
    elements.requiredPassCount.textContent = `${requiredPassed} / ${requiredTotal}`;
    elements.readinessPct.textContent = `${readiness}%`;
    elements.readinessBar.style.width = `${readiness}%`;

    const previewLines = idState.validIds.slice(0, 40);
    elements.idsPreview.textContent = previewLines.length
        ? `${previewLines.join("\n")}${idState.validIds.length > 40 ? "\n..." : ""}`
        : "No valid IDs yet.";

    if (idState.invalidLines.length === 0) {
        elements.readinessText.textContent = "No syntax issues detected in the IDs list.";
    } else {
        const invalidList = idState.invalidLines.slice(0, 3)
            .map((item) => `line ${item.line}: ${item.value}`)
            .join(" | ");
        elements.readinessText.textContent = `Invalid entries detected (${idState.invalidLines.length}): ${invalidList}`;
    }

    if (readiness === 100) {
        elements.connectionBadge.textContent = "Ready";
        elements.connectionBadge.classList.remove("badge-offline");
        elements.connectionBadge.classList.add("badge-ready");
    } else {
        elements.connectionBadge.textContent = "Not ready";
        elements.connectionBadge.classList.remove("badge-ready");
        elements.connectionBadge.classList.add("badge-offline");
    }
}

function setStatus(message, kind) {
    elements.statusMessage.textContent = message;
    elements.statusMessage.className = "status";

    if (kind === "ok") {
        elements.statusMessage.classList.add("status-ok");
        return;
    }

    if (kind === "warn") {
        elements.statusMessage.classList.add("status-warn");
        return;
    }

    if (kind === "bad") {
        elements.statusMessage.classList.add("status-bad");
        return;
    }

    elements.statusMessage.classList.add("status-neutral");
}

function setRunStatus(message, kind) {
    elements.runStatus.textContent = message;
    elements.runStatus.className = "status";

    if (kind === "ok") {
        elements.runStatus.classList.add("status-ok");
        return;
    }

    if (kind === "warn") {
        elements.runStatus.classList.add("status-warn");
        return;
    }

    if (kind === "bad") {
        elements.runStatus.classList.add("status-bad");
        return;
    }

    elements.runStatus.classList.add("status-neutral");
}

function refreshDashboard() {
    const state = buildRequirementState();
    renderRequirements(state);
    updateStats(state);
    updateBatchStatusUi();
    unlockModelSearchControls();
    setRunButtonsState();
    return state;
}

function getSettingsSnapshot() {
    return {
        cookie: buildCookieFromInputs(),
        medusaJwt: normalizeJwtValue(elements.jwtInput.value),
        medusaPublishableKey: normalizePublishableKeyValue(elements.publishableKeyInput.value),
        modelIdsText: elements.idsInput.value,
        modelIdCatalog: getModelIdCatalogSnapshot(),
        downloadRoot: elements.downloadRootInput.value,
        downloadRootHistory: getDownloadRootHistorySnapshot(),
        batchSizeSelection: getBatchSizeSelection(),
        batchProgress: getBatchProgressSnapshot(),
        testModeCheck: elements.testModeCheck.checked,
        basePath: elements.basePathInput.value,
        extractInPlace: elements.extractModeSelect.value === "true",
        jsonPath: elements.jsonPathInput.value,
        foldersPath: elements.foldersPathInput.value,
        namingFormat: elements.namingFormatSelect.value,
        maxNameLength: elements.maxLengthInput.value,
        catalogLoadMode: getCatalogLoadMode(),
        catalogCreatorIdFilter: getCreatorIdFilter(),
        categorySelection: getCategorySelectionSnapshot()
    };
}

function applySettingsToForm(settings) {
    if (!settings || typeof settings !== "object") {
        return;
    }

    settingsApplyInProgress = true;

    if (typeof settings.cookie === "string" && settings.cookie.trim()) {
        const parts = parseLegacyCookie(settings.cookie);
        elements.phpSessidInput.value = parts.phpSessid;
        elements.cfClearanceInput.value = parts.cfClearance;
    }
    if (typeof settings.medusaJwt === "string") {
        elements.jwtInput.value = normalizeJwtValue(settings.medusaJwt);
    }
    if (typeof settings.medusaPublishableKey === "string") {
        elements.publishableKeyInput.value = normalizePublishableKeyValue(settings.medusaPublishableKey);
    }

    batchProgressState = sanitizeBatchProgressState(settings.batchProgress);
    setBatchSizeSelection(settings.batchSizeSelection);

    const modelIdsText = typeof settings.modelIdsText === "string"
        ? settings.modelIdsText
        : elements.idsInput.value;
    const catalog = Array.isArray(settings.modelIdCatalog) ? settings.modelIdCatalog : [];
    setModelIdEntriesFromText(modelIdsText, catalog);

    const historyFromSettings = sanitizeDownloadRootHistory(settings.downloadRootHistory);
    downloadRootHistory = historyFromSettings;

    elements.downloadRootInput.value = typeof settings.downloadRoot === "string" ? settings.downloadRoot : elements.downloadRootInput.value;
    lastStableDownloadRoot = elements.downloadRootInput.value.trim();

    if (lastStableDownloadRoot) {
        rememberDownloadRoot(lastStableDownloadRoot, { save: false });
    } else {
        renderDownloadRootHistory();
    }

    elements.testModeCheck.checked = typeof settings.testModeCheck === "boolean"
        ? settings.testModeCheck
        : elements.testModeCheck.checked;

    if (typeof settings.basePath === "string" && settings.basePath) {
        elements.basePathInput.value = settings.basePath;
    }
    if (typeof settings.extractInPlace === "boolean") {
        elements.extractModeSelect.value = settings.extractInPlace ? "true" : "false";
    }
    if (typeof settings.jsonPath === "string" && settings.jsonPath) {
        elements.jsonPathInput.value = settings.jsonPath;
    }
    if (typeof settings.foldersPath === "string" && settings.foldersPath) {
        elements.foldersPathInput.value = settings.foldersPath;
    }
    if (settings.namingFormat === "NAME_ONLY" || settings.namingFormat === "ID_NAME") {
        elements.namingFormatSelect.value = settings.namingFormat;
    }
    if (settings.maxNameLength !== undefined && settings.maxNameLength !== null) {
        elements.maxLengthInput.value = String(settings.maxNameLength);
    }
    if (typeof settings.catalogLoadMode === "string") {
        setCatalogLoadMode(settings.catalogLoadMode);
    }
    if (typeof settings.catalogCreatorIdFilter === "string") {
        setCreatorIdFilter(settings.catalogCreatorIdFilter);
    } else if (typeof settings.creatorIdFilter === "string") {
        setCreatorIdFilter(settings.creatorIdFilter);
    }

    setCategorySelectionMapFromArray(Array.isArray(settings.categorySelection) ? settings.categorySelection : []);
    renderCategorySelection();
    updateCreatorFilterVisibility();
    reconcileBatchProgressWithCurrentIds();

    settingsApplyInProgress = false;
    refreshDashboard();
}

async function saveSettingsNow() {
    if (!mmfDesktopApi || !mmfDesktopApi.saveSettings || settingsApplyInProgress) {
        return;
    }

    try {
        await mmfDesktopApi.saveSettings(getSettingsSnapshot());
    } catch (_error) {
        // Ignore transient persistence errors; the UI should remain usable.
    }
}

function scheduleSettingsSave() {
    if (!mmfDesktopApi || !mmfDesktopApi.saveSettings || settingsApplyInProgress) {
        return;
    }

    if (settingsSaveTimer) {
        clearTimeout(settingsSaveTimer);
    }

    settingsSaveTimer = setTimeout(() => {
        settingsSaveTimer = null;
        saveSettingsNow();
    }, 400);
}

async function loadSavedSettings() {
    if (!mmfDesktopApi || !mmfDesktopApi.loadSettings) {
        return;
    }

    try {
        const settings = await mmfDesktopApi.loadSettings();
        applySettingsToForm(settings);
    } catch (_error) {
        // Ignore settings load errors; defaults and manual input still work.
    }
}

function setRunButtonsState() {
    const running = Boolean(activeRunId) || pipelineRunning || batchProgressState.inProgress;

    const readinessState = buildRequirementState();
    const readinessReady = readinessState.readiness === 100;
    const readinessHint = "Complete required checks first (5/5) to unlock this action.";
    const nextBatchPlan = getNextBatchPlan();
    const hasPendingBatch = nextBatchPlan.ids.length > 0;
    const pendingHint = "All selected models are already completed. Use Reset batch progress to run them again.";

    [elements.runExecuteBtn, elements.runNextBatchBtn].forEach((button) => {
        if (!button) {
            return;
        }

        button.disabled = running || !readinessReady || !hasPendingBatch;

        if (!readinessReady) {
            button.title = readinessHint;
            return;
        }

        if (!hasPendingBatch) {
            button.title = pendingHint;
            return;
        }

        button.title = "";
    });

    [elements.runStep1Btn].forEach((button) => {
        if (!button) {
            return;
        }

        button.disabled = running || !readinessReady;
        button.title = !readinessReady ? readinessHint : "";
    });

    [
        elements.runStep2TestBtn,
        elements.runStep2FullBtn,
        elements.runStep3Btn,
        elements.runStep4Btn,
        elements.runPostProcessBtn
    ].forEach((button) => {
        if (!button) {
            return;
        }

        button.disabled = running;
        button.title = "";
    });

    if (elements.batchSizeSelect) {
        elements.batchSizeSelect.disabled = running;
    }

    if (elements.resetBatchProgressBtn) {
        elements.resetBatchProgressBtn.disabled = running;
    }

    if (elements.downloadRootInput) {
        elements.downloadRootInput.disabled = running;
        elements.downloadRootInput.title = running
            ? "Download folder cannot be changed while a pipeline is active."
            : "";
    }

    if (elements.browseDownloadRootBtn) {
        elements.browseDownloadRootBtn.disabled = running;
        elements.browseDownloadRootBtn.title = running
            ? "Download folder cannot be changed while a pipeline is active."
            : "";
    }

    unlockModelSearchControls();
    renderModelIdList();

    elements.stopRunBtn.disabled = !running;
}

function appendRunLog(text, stream = "stdout") {
    if (!text) {
        return;
    }

    feedPipelineProgressFromLog(text);

    const existing = elements.runLog.textContent === "Run log will appear here." ? "" : elements.runLog.textContent;
    const prefix = stream === "stderr" ? "[stderr] " : "";
    const incoming = text.endsWith("\n") ? text : `${text}\n`;
    const combined = `${existing}${prefix}${incoming}`;
    const trimmed = combined.length > 120000 ? combined.slice(combined.length - 120000) : combined;

    elements.runLog.textContent = trimmed;
    elements.runLog.scrollTop = elements.runLog.scrollHeight;
}

function clearRunLog() {
    elements.runLog.textContent = "Run log will appear here.";
}

function downloadTextFile(filename, content) {
    const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
}

async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return;
    }

    const helper = document.createElement("textarea");
    helper.value = text;
    helper.style.position = "fixed";
    helper.style.left = "-9999px";
    document.body.appendChild(helper);
    helper.focus();
    helper.select();
    document.execCommand("copy");
    helper.remove();
}

function applyCapturedSessionToForm(session) {
    if (!session || !session.ok) {
        return;
    }

    if (typeof session.cookie === "string" && session.cookie.trim()) {
        const parts = parseLegacyCookie(session.cookie);
        elements.phpSessidInput.value = parts.phpSessid;
        elements.cfClearanceInput.value = parts.cfClearance;
    }

    if (typeof session.medusaJwt === "string" && session.medusaJwt.trim()) {
        elements.jwtInput.value = normalizeJwtValue(session.medusaJwt);
    }

    if (typeof session.medusaPublishableKey === "string" && session.medusaPublishableKey.trim()) {
        elements.publishableKeyInput.value = normalizePublishableKeyValue(session.medusaPublishableKey);
    }
}

async function openMmfLoginFromUi() {
    if (!mmfDesktopApi || !mmfDesktopApi.openMmfLogin) {
        setStatus("MMF browser is available only in desktop mode.", "warn");
        return;
    }

    try {
        const result = await mmfDesktopApi.openMmfLogin();
        if (result && result.ok === false) {
            setStatus(result.message || "Failed to open MyMiniFactory window.", "bad");
            return;
        }

        if (result && result.mode === "profile") {
            setStatus("Opened your MMF profile. Click Capture session to sync credentials.", "ok");
            return;
        }

        if (result && result.mode === "home") {
            setStatus("Opened MMF (signed in). Open your profile, then click Capture session.", "neutral");
            return;
        }

        setStatus("MMF sign-in window opened. Log in, then click Capture session.", "neutral");
    } catch (err) {
        setStatus(`Failed to open MMF: ${String(err?.message || err)}`, "bad");
    }
}

async function captureMmfSessionFromUi() {
    if (!mmfDesktopApi || !mmfDesktopApi.captureMmfSession) {
        setStatus("Session capture is available only in desktop mode.", "warn");
        return;
    }

    const button = elements.captureMmfSessionBtn;
    const previousLabel = button ? button.textContent : "";

    if (button) {
        button.disabled = true;
        button.textContent = "Capturing...";
    }

    try {
        const session = await mmfDesktopApi.captureMmfSession();
        if (!session || !session.ok) {
            const cookieHint = Array.isArray(session?.cookieNames) && session.cookieNames.length > 0
                ? ` Cookies seen: ${session.cookieNames.join(", ")}.`
                : "";
            setStatus(
                `${session && session.message ? session.message : "Failed to capture MMF session."}${cookieHint}`,
                session && session.openedLoginWindow ? "warn" : "bad"
            );
            return;
        }

        applyCapturedSessionToForm(session);
        refreshDashboard();
        scheduleSettingsSave();
        await checkMmfSessionFromUi(true);

        const missing = [];
        if (!session.hasMedusaJwt) {
            missing.push("medusa_auth_token");
        }
        if (!session.hasPublishableKey) {
            missing.push("x-publishable-api-key");
        }

        if (missing.length > 0) {
            setStatus(
                `Session captured (cookie OK). Still missing: ${missing.join(", ")}. Open your MMF profile in the sign-in window, then capture again.`,
                "warn"
            );
            return;
        }

        setStatus("MMF session captured and applied.", "ok");

        if (modelIdEntries.length === 0) {
            await autoLoadOwnModelIds({ silent: true });
        }
    } catch (err) {
        setStatus(`Session capture failed: ${String(err?.message || err)}`, "bad");
    } finally {
        if (button) {
            button.disabled = false;
            button.textContent = previousLabel || "Capture session";
        }
    }
}

async function autoLoadOwnModelIds(options = {}) {
    if (!mmfDesktopApi || !mmfDesktopApi.resolveOwnModelIds) {
        setStatus("Auto-load is available only in desktop mode.", "warn");
        return;
    }

    const silent = Boolean(options && options.silent);
    const catalogLoadMode = getCatalogLoadMode();
    const creatorIdFilter = getCreatorIdFilter();

    if (catalogLoadMode === "creator" && !creatorIdFilter) {
        setStatus("Creator filter mode requires a creator ID.", "bad");
        if (elements.creatorIdFilterInput) {
            elements.creatorIdFilterInput.focus();
        }
        return;
    }

    if (!silent && modelIdEntries.length > 0) {
        const confirmed = await showConfirmDialog("Replace current model list with auto-loaded IDs?");
        if (!confirmed) {
            setStatus("Auto-load canceled.", "warn");
            return;
        }
    }

    const button = elements.autoLoadMyIdsBtn;
    const previousLabel = button ? button.textContent : "";

    if (button) {
        button.disabled = true;
        button.textContent = "Loading...";
    }

    setStatus(
        `Loading ${getCatalogLoadModeLabel(catalogLoadMode)}…`,
        "neutral"
    );

    let unsubscribeCatalogProgress = null;
    if (mmfDesktopApi.onCatalogProgress) {
        unsubscribeCatalogProgress = mmfDesktopApi.onCatalogProgress((payload) => {
            if (payload && payload.message) {
                setStatus(payload.message, "neutral");
            }
        });
    }

    try {
        const response = await mmfDesktopApi.resolveOwnModelIds({
            cookie: buildCookieFromInputs(),
            medusaJwt: normalizeJwtValue(elements.jwtInput.value),
            medusaPublishableKey: normalizePublishableKeyValue(elements.publishableKeyInput.value),
            catalogLoadMode,
            creatorIdFilter
        });

        if (!response || !response.ok) {
            setStatus(response && response.message ? response.message : "Failed to auto-load your IDs.", "bad");
            return;
        }

        const catalogItems = Array.isArray(response.items)
            ? response.items
                .map((entry) => normalizeModelEntry(entry))
                .filter(Boolean)
            : [];

        if (catalogItems.length === 0) {
            const sources = Array.isArray(response.sourcesUsed)
                ? response.sourcesUsed.join(", ")
                : "catalog APIs";
            const creatorSuffix = catalogLoadMode === "creator"
                ? ` (creatorId ${creatorIdFilter})`
                : "";
            setStatus(
                `No models found for ${getCatalogLoadModeLabel(catalogLoadMode)}${creatorSuffix} (mmf_id ${response.mmfId || "unknown"}, ${sources}).`,
                "warn"
            );
            return;
        }

        setModelIdEntriesFromCatalog(catalogItems);
        refreshDashboard();
        scheduleSettingsSave();

        const namedCount = catalogItems.filter((entry) => entry.name).length;
        const sourceLabel = Array.isArray(response.sourcesUsed) && response.sourcesUsed.length > 0
            ? response.sourcesUsed.join(" + ")
            : "catalog";
        const rawSuffix = typeof response.libraryRawCount === "number" && response.libraryRawCount > catalogItems.length
            ? ` from ${response.libraryRawCount.toLocaleString()} library entries`
            : "";
        const warningSuffix = Array.isArray(response.warnings) && response.warnings.length > 0
            ? ` Note: ${response.warnings[0]}`
            : "";

        setStatus(
            `Loaded ${catalogItems.length.toLocaleString()} IDs (${getCatalogLoadModeLabel(catalogLoadMode)} via ${sourceLabel}${rawSuffix}; ${namedCount.toLocaleString()} with names).${warningSuffix}`,
            "ok"
        );
    } catch (err) {
        setStatus(`Auto-load failed: ${String(err?.message || err)}`, "bad");
    } finally {
        if (typeof unsubscribeCatalogProgress === "function") {
            unsubscribeCatalogProgress();
        }

        unlockModelSearchControls();

        if (button) {
            button.disabled = false;
            button.textContent = previousLabel || "Auto load my IDs";
        }
    }
}

function buildCommandPlan() {
    const downloadsPath = getActiveDownloadsPath() || "<your-download-folder>";

    return [
        "# Run from repository root",
        "bash 1_mmf_download_metadata.sh",
        "",
        "# Then run Step 2 from selected download folder",
        `cd \"${downloadsPath}\"`,
        "bash ../mmf_download_stl_files_enhanced.sh --test",
        "bash ../mmf_download_stl_files_enhanced.sh",
        "",
        "# Step 2 output per model: model_<id>.json (compact) + <model_name>.zip + images/"
    ].join("\n");
}

function buildPostProcessSnippet() {
    const maxLength = Number.parseInt(elements.maxLengthInput.value, 10);
    const safeLength = Number.isNaN(maxLength) ? 80 : Math.max(10, Math.min(160, maxLength));

    if (runtimePlatform === "win32") {
        return [
            "# 3_extract_all_zips.ps1",
            `$BASE_PATH = \"${elements.basePathInput.value.trim()}\"`,
            `$EXTRACT_IN_PLACE = $${elements.extractModeSelect.value}`,
            "",
            "# 4_rename_folders_from_json.ps1",
            `$JSON_PATH = \"${elements.jsonPathInput.value.trim()}\"`,
            `$FOLDERS_PATH = \"${elements.foldersPathInput.value.trim()}\"`,
            `$NAMING_FORMAT = \"${elements.namingFormatSelect.value}\"`,
            `$MAX_NAME_LENGTH = ${safeLength}`
        ].join("\n");
    }

    return [
        "# 3_extract_all_zips.sh",
        `export MMF_BASE_PATH=\"${elements.basePathInput.value.trim()}\"`,
        `export MMF_EXTRACT_IN_PLACE=\"${elements.extractModeSelect.value}\"`,
        "bash 3_extract_all_zips.sh",
        "",
        "# 4_rename_folders_from_json.sh",
        `export MMF_JSON_PATH=\"${elements.jsonPathInput.value.trim()}\"`,
        `export MMF_FOLDERS_PATH=\"${elements.foldersPathInput.value.trim()}\"`,
        `export MMF_NAMING_FORMAT=\"${elements.namingFormatSelect.value}\"`,
        `export MMF_MAX_NAME_LENGTH=\"${safeLength}\"`,
        "bash 4_rename_folders_from_json.sh"
    ].join("\n");
}

function getActiveDownloadsPath() {
    const fromInput = elements.downloadRootInput && elements.downloadRootInput.value
        ? elements.downloadRootInput.value.trim()
        : "";

    if (fromInput) {
        return fromInput;
    }

    if (runtimeInfoCache && runtimeInfoCache.downloadsPath) {
        return runtimeInfoCache.downloadsPath;
    }

    return "";
}

function getActiveStlFilesPath() {
    const downloadsPath = getActiveDownloadsPath();
    if (downloadsPath) {
        if (downloadsPath.endsWith("\\") || downloadsPath.endsWith("/")) {
            return `${downloadsPath}stl_files`;
        }

        const separator = downloadsPath.includes("\\") && !downloadsPath.includes("/") ? "\\" : "/";
        return `${downloadsPath}${separator}stl_files`;
    }

    if (runtimeInfoCache && runtimeInfoCache.stlFilesPath) {
        return runtimeInfoCache.stlFilesPath;
    }

    return "";
}

async function openPathFromUi(pathValue, label, options = {}) {
    const targetPath = (pathValue || "").trim();
    if (!targetPath) {
        setStatus(`${label} is empty. Select a folder first.`, "warn");
        return;
    }

    if (!mmfDesktopApi || !mmfDesktopApi.openPath) {
        setStatus("Open folder action is available only in desktop mode.", "warn");
        return;
    }

    try {
        const result = await mmfDesktopApi.openPath({
            path: targetPath,
            config: getSettingsSnapshot()
        });
        if (result && result.ok) {
            setStatus(`${label} opened.`, "ok");
            return;
        }

        const message = result && result.message ? result.message : `Failed to open ${label}.`;
        const pathMissing = /^Path does not exist:/i.test(message);
        if (pathMissing && options.removeFromHistoryOnMissing !== false) {
            const removed = removeDownloadRootFromHistory(targetPath);
            if (removed) {
                setStatus(`${message} Removed from saved download folders.`, "warn");
                return;
            }
        }

        const pathOutsideWorkspace = /outside the allowed download workspace/i.test(message);
        if (pathOutsideWorkspace) {
            setStatus(
                `${message} Set that folder as "Download folder" first, or pick it with Browse — saved folders in history should open after a restart.`,
                "warn"
            );
            return;
        }

        setStatus(message, "bad");
    } catch (err) {
        setStatus(`Failed to open ${label}: ${String(err?.message || err)}`, "bad");
    }
}

function setJsonViewerMessage(message) {
    if (!elements.jsonViewer) {
        return;
    }

    elements.jsonViewer.textContent = message;
}

async function loadSelectedModelJson() {
    if (!elements.jsonFileSelect) {
        return;
    }

    const selected = elements.jsonFileSelect.value;
    if (!selected) {
        setJsonViewerMessage("No model JSON selected yet.");
        return;
    }

    if (!mmfDesktopApi || !mmfDesktopApi.readModelJsonFile) {
        setJsonViewerMessage("JSON viewer requires desktop mode.");
        return;
    }

    try {
        const response = await mmfDesktopApi.readModelJsonFile({
            downloadRoot: getActiveDownloadsPath(),
            fileName: selected
        });

        if (!response || !response.ok) {
            const message = response && response.message ? response.message : "Unable to read selected JSON file.";
            setJsonViewerMessage(message);
            return;
        }

        setJsonViewerMessage(response.prettyJson || "Empty JSON file.");
    } catch (err) {
        setJsonViewerMessage(`Unable to read selected JSON file: ${String(err?.message || err)}`);
    }
}

async function refreshModelJsonList() {
    if (!elements.jsonFileSelect) {
        return;
    }

    if (!mmfDesktopApi || !mmfDesktopApi.listModelJsonFiles) {
        elements.jsonFileSelect.innerHTML = "";
        setJsonViewerMessage("JSON viewer requires desktop mode.");
        return;
    }

    const previousSelection = elements.jsonFileSelect.value;

    try {
        const response = await mmfDesktopApi.listModelJsonFiles({
            downloadRoot: getActiveDownloadsPath()
        });

        const files = response && Array.isArray(response.files) ? response.files : [];
        elements.jsonFileSelect.innerHTML = "";

        if (files.length === 0) {
            const emptyOption = document.createElement("option");
            emptyOption.value = "";
            emptyOption.textContent = "No model_*.json files found";
            elements.jsonFileSelect.appendChild(emptyOption);
            setJsonViewerMessage("No model JSON files found in the selected download folder yet.");
            return;
        }

        files.forEach((file) => {
            const option = document.createElement("option");
            option.value = file.name;
            option.textContent = `${file.id} (${file.name})`;
            elements.jsonFileSelect.appendChild(option);
        });

        const hasPreviousSelection = files.some((file) => file.name === previousSelection);
        elements.jsonFileSelect.value = hasPreviousSelection ? previousSelection : files[0].name;

        await loadSelectedModelJson();
    } catch (err) {
        elements.jsonFileSelect.innerHTML = "";
        const fallbackOption = document.createElement("option");
        fallbackOption.value = "";
        fallbackOption.textContent = "Unable to load JSON list";
        elements.jsonFileSelect.appendChild(fallbackOption);
        setJsonViewerMessage(`Unable to load JSON list: ${String(err?.message || err)}`);
    }
}

function updatePathHelperHint() {
    if (!elements.pathHelperHint) {
        return;
    }

    const basePath = elements.basePathInput.value.trim();
    const jsonPath = elements.jsonPathInput.value.trim();
    const foldersPath = elements.foldersPathInput.value.trim();
    const downloadRoot = getActiveDownloadsPath();

    if (downloadRoot) {
        elements.pathHelperHint.textContent = `Selected download folder: ${downloadRoot}`;
        if (basePath && jsonPath && foldersPath) {
            elements.pathHelperHint.textContent += " | BASE_PATH/FOLDERS_PATH should usually be stl_files under this folder.";
        }
        return;
    }

    if (runtimeInfoCache && runtimeInfoCache.downloadsPath && runtimeInfoCache.stlFilesPath) {
        elements.pathHelperHint.textContent = `Recommended now: JSON_PATH = ${runtimeInfoCache.downloadsPath} | BASE_PATH/FOLDERS_PATH = ${runtimeInfoCache.stlFilesPath}`;
        return;
    }

    elements.pathHelperHint.textContent = "Tip: use your downloads and stl_files folders. You can click Browse to pick folders.";
}

function applyRecommendedPaths(force = false) {
    if (!runtimeInfoCache) {
        return false;
    }

    let changed = false;

    if (force || !elements.basePathInput.value.trim()) {
        elements.basePathInput.value = getActiveStlFilesPath() || elements.basePathInput.value;
        changed = true;
    }

    if (force || !elements.jsonPathInput.value.trim()) {
        elements.jsonPathInput.value = getActiveDownloadsPath() || elements.jsonPathInput.value;
        changed = true;
    }

    if (force || !elements.foldersPathInput.value.trim()) {
        elements.foldersPathInput.value = getActiveStlFilesPath() || elements.foldersPathInput.value;
        changed = true;
    }

    updatePathHelperHint();
    return changed;
}

async function pickDirectoryInto(inputElement, title) {
    if (!inputElement) {
        return "";
    }

    if (!mmfDesktopApi || !mmfDesktopApi.pickDirectory) {
        setStatus("Folder picker is available only in desktop mode.", "warn");
        return "";
    }

    try {
        const result = await mmfDesktopApi.pickDirectory({
            title,
            defaultPath: inputElement.value || (runtimeInfoCache && runtimeInfoCache.scriptRoot) || ""
        });

        if (!result || result.canceled || !result.path) {
            return "";
        }

        inputElement.value = result.path;
        updatePathHelperHint();
        scheduleSettingsSave();
        setStatus(`${title} selected.`, "ok");
        return result.path;
    } catch (err) {
        setStatus(`Unable to open folder picker: ${String(err?.message || err)}`, "bad");
        return "";
    }
}

function renderDependencySummary(summary) {
    elements.depList.innerHTML = "";

    summary.dependencies.forEach((dep) => {
        const li = document.createElement("li");

        const dot = document.createElement("span");
        dot.classList.add("dot", dep.installed ? "dot-pass" : dep.required ? "dot-fail" : "dot-warn");

        const copy = document.createElement("div");
        copy.className = "req-copy";

        const title = document.createElement("strong");
        title.textContent = dep.displayName;

        const details = document.createElement("span");
        const status = dep.installed ? "installed" : dep.required ? "missing" : "optional missing";
        const version = dep.version ? ` (version: ${dep.version})` : "";
        details.textContent = `${status}${version}`;

        copy.appendChild(title);
        copy.appendChild(document.createElement("br"));
        copy.appendChild(details);

        li.appendChild(dot);
        li.appendChild(copy);
        elements.depList.appendChild(li);
    });

    if (summary.missingRequired.length === 0) {
        elements.depSummary.textContent = "All required dependencies are installed.";
        elements.depInstallBtn.disabled = true;
        elements.depSkipBtn.textContent = "Continue";
        return;
    }

    const installHint = summary.canInstall
        ? `Auto-install available via ${summary.installMethod}.`
        : "Auto-install tool is not available on this system.";
    elements.depSummary.textContent = `${summary.missingRequired.length} required dependency(ies) are missing. ${installHint}`;
    elements.depInstallBtn.disabled = false;
    elements.depSkipBtn.textContent = "Continue without install";
}

async function runDependencyCheck() {
    if (!mmfDesktopApi) {
        elements.desktopGate.classList.add("hidden");
        setStatus("Browser mode: desktop dependency checks are disabled.", "warn");
        return;
    }

    elements.depSummary.textContent = "Checking dependencies...";
    elements.depLog.textContent = "No installer output yet.";
    elements.depRefreshBtn.disabled = true;
    elements.depInstallBtn.disabled = true;

    try {
        const summary = await mmfDesktopApi.checkDependencies();
        lastDependencySummary = summary;
        renderDependencySummary(summary);

        if (summary.missingRequired.length === 0) {
            setStatus("Desktop dependencies are ready.", "ok");
            elements.desktopGate.classList.add("hidden");
        } else {
            setStatus("Missing desktop dependencies detected. Install or continue manually.", "warn");
            elements.desktopGate.classList.remove("hidden");
        }
    } catch (err) {
        elements.depSummary.textContent = "Dependency check failed.";
        elements.depLog.textContent = String(err?.message || err);
        setStatus("Dependency check failed. Use Refresh check or continue manually.", "bad");
        elements.desktopGate.classList.remove("hidden");
    } finally {
        elements.depRefreshBtn.disabled = false;
        if (lastDependencySummary && lastDependencySummary.missingRequired.length > 0) {
            elements.depInstallBtn.disabled = false;
        }
    }
}

async function installMissingDependencies() {
    if (!mmfDesktopApi) {
        return;
    }

    if (!lastDependencySummary || lastDependencySummary.missingRequired.length === 0) {
        setStatus("No missing required dependencies to install.", "ok");
        return;
    }

    const confirmed = await showConfirmDialog("Install missing dependencies now? This may trigger UAC prompts.");
    if (!confirmed) {
        setStatus("Dependency installation canceled by user.", "warn");
        return;
    }

    elements.depInstallBtn.disabled = true;
    elements.depRefreshBtn.disabled = true;
    elements.depSummary.textContent = "Installing missing dependencies...";
    elements.depLog.textContent = "Running installer commands...";

    try {
        const result = await mmfDesktopApi.installMissingDependencies();
        elements.depLog.textContent = result.log || "Install command finished with no output.";

        if (result.success) {
            setStatus("Dependency installation finished. Revalidating...", "ok");
        } else {
            setStatus("Some dependency installs failed. Review log and retry.", "bad");
        }

        await runDependencyCheck();
    } catch (err) {
        elements.depLog.textContent = String(err?.message || err);
        setStatus("Dependency installation crashed. Review log and retry.", "bad");
    } finally {
        elements.depInstallBtn.disabled = false;
        elements.depRefreshBtn.disabled = false;
    }
}

async function loadRuntimeInfo() {
    if (!mmfDesktopApi || !mmfDesktopApi.getRuntimeInfo) {
        elements.runtimePath.textContent = "Execution root: browser preview mode";
        updatePathHelperHint();
        return;
    }

    try {
        const runtime = await mmfDesktopApi.getRuntimeInfo({
            downloadRoot: getActiveDownloadsPath()
        });
        runtimeInfoCache = runtime;
        runtimePlatform = runtime.platform || "unknown";
        elements.runtimePath.textContent = `Execution root: ${runtime.scriptRoot} (${runtimePlatform}) | download folder: ${runtime.downloadsPath}`;

        applyRecommendedPaths(false);
    } catch (err) {
        elements.runtimePath.textContent = `Execution root: unavailable (${String(err?.message || err)})`;
    } finally {
        updatePathHelperHint();
    }
}

function collectExecutionConfig() {
    return {
        cookie: buildCookieFromInputs(),
        medusaJwt: normalizeJwtValue(elements.jwtInput.value),
        medusaPublishableKey: normalizePublishableKeyValue(elements.publishableKeyInput.value),
        modelIdsText: elements.idsInput.value,
        catalogLoadMode: getCatalogLoadMode(),
        creatorIdFilter: getCreatorIdFilter(),
        categorySelection: getCategorySelectionSnapshot(),
        downloadRoot: elements.downloadRootInput.value,
        basePath: elements.basePathInput.value,
        extractInPlace: elements.extractModeSelect.value === "true",
        jsonPath: elements.jsonPathInput.value,
        foldersPath: elements.foldersPathInput.value,
        namingFormat: elements.namingFormatSelect.value,
        maxNameLength: elements.maxLengthInput.value
    };
}

function validateBeforeRun(stepKey) {
    const state = buildRequirementState();

    if (stepKey === "step1") {
        if (!state.cookieState.hasPhpSession || !state.cookieState.hasCfClearance) {
            return "Step 1 requires both PHPSESSID and cf_clearance.";
        }
        if (!state.idState.validIds.length) {
            return "Step 1 requires at least one model ID.";
        }
        if (state.idState.invalidLines.length > 0) {
            return "Fix invalid ID lines before running Step 1.";
        }
    }

    if (stepKey === "step2-test" || stepKey === "step2-full") {
        if (!state.cookieState.hasPhpSession || !state.cookieState.hasCfClearance) {
            return "Step 2 requires both PHPSESSID and cf_clearance.";
        }

        if (!state.categoryState.isValid) {
            return "Each selected category must include at least one subcategory before Step 2.";
        }
    }

    return "";
}

async function startWorkflowStep(stepKey, label, options = {}) {
    const silent = options && options.silent === true;
    const configOverride = options && options.configOverride && typeof options.configOverride === "object"
        ? options.configOverride
        : {};

    if (!mmfDesktopApi || !mmfDesktopApi.startWorkflowStep) {
        if (!silent) {
            setRunStatus("Desktop execution is unavailable in browser mode.", "bad");
        }
        return {
            accepted: false,
            message: "Desktop execution is unavailable in browser mode."
        };
    }

    if (activeRunId) {
        if (!silent) {
            setRunStatus("Another workflow step is already running.", "warn");
        }
        return {
            accepted: false,
            message: "Another workflow step is already running."
        };
    }

    const validationError = validateBeforeRun(stepKey);
    if (validationError) {
        if (!silent) {
            setRunStatus(validationError, "bad");
        }
        return {
            accepted: false,
            message: validationError
        };
    }

    const needsLiveSession = stepKey === "step1" || stepKey === "step2-test" || stepKey === "step2-full";
    if (needsLiveSession) {
        const sessionCheck = await checkMmfSessionFromUi(true);
        if (sessionCheck && sessionCheck.expired) {
            const message = sessionCheck.message || "MMF session expired. Capture a fresh session.";
            if (!silent) {
                setRunStatus(message, "bad");
            }
            return {
                accepted: false,
                message
            };
        }
    }

    await saveSettingsNow();

    if (!silent) {
        setRunStatus(`Starting ${label}...`, "neutral");
    }

    try {
        const response = await mmfDesktopApi.startWorkflowStep({
            stepKey,
            config: {
                ...collectExecutionConfig(),
                ...configOverride
            }
        });

        if (!response.accepted) {
            if (!silent) {
                setRunStatus(response.message || "Failed to start workflow step.", "bad");
            }
            return response;
        }

        activeRunId = response.runId;
        latestRunId = response.runId;
        setRunButtonsState();
        appendRunLog(`[start] ${response.label}`);
        appendRunLog(`[command] ${response.commandLine}`);
        appendRunLog(`[cwd] ${response.cwd}`);

        if (Array.isArray(response.warnings) && response.warnings.length > 0) {
            response.warnings.forEach((warning) => {
                appendRunLog(`[warning] ${warning}`, "stderr");
            });
        }

        if (!silent) {
            setRunStatus(`${label} started.`, "ok");
        }

        return response;
    } catch (err) {
        const message = `Failed to start ${label}: ${String(err?.message || err)}`;
        if (!silent) {
            setRunStatus(message, "bad");
        }
        return {
            accepted: false,
            message
        };
    }
}

function waitForRunCompletion(runId) {
    return new Promise((resolve) => {
        pendingRunResolvers.set(runId, resolve);
    });
}

function beginBatchPipeline(plan) {
    activeBatchPlan = {
        ids: sanitizeNumericIdList(plan.ids),
        batchMode: plan.batchMode,
        startedAt: new Date().toISOString(),
        downloadRoot: getActiveDownloadsPath()
    };

    batchProgressState.inProgress = true;
    batchProgressState.inProgressIds = [...activeBatchPlan.ids];
    batchProgressState.startedAt = activeBatchPlan.startedAt;
    batchProgressState.lastStatus = "running";
    batchProgressState.lastError = "";
    batchProgressState.lastRunDownloadRoot = activeBatchPlan.downloadRoot || "";

    updateBatchStatusUi();
    setRunButtonsState();
    beginPipelineProgressUi(plan, { phase: "starting" });
}

function finalizeBatchPipelineSuccess() {
    const completed = new Set(sanitizeNumericIdList(batchProgressState.completedIds));
    const completedNow = activeBatchPlan ? sanitizeNumericIdList(activeBatchPlan.ids) : [];
    completedNow.forEach((id) => completed.add(id));

    batchProgressState.completedIds = [...completed];
    batchProgressState.inProgress = false;
    batchProgressState.inProgressIds = [];
    batchProgressState.lastCompletedAt = new Date().toISOString();
    batchProgressState.lastStatus = "completed";
    batchProgressState.lastError = "";

    const currentDownloadRoot = getActiveDownloadsPath();
    if (currentDownloadRoot) {
        rememberDownloadRoot(currentDownloadRoot, { save: false });
    }

    activeBatchPlan = null;
    sessionPipelineCompletedIds.clear();
    reconcileBatchProgressWithCurrentIds();
    updateBatchStatusUi();
    renderModelIdList();
    pipelineProgressState.phase = "done";
    pipelineProgressState.label = "Batch completed";
    pipelineProgressState.detail = "All pipeline steps finished for this batch.";
    pipelineProgressState.percent = 100;
    renderPipelineProgressUi();
    scheduleSettingsSave();
}

function finalizeBatchPipelineFailure(message, status = "failed") {
    if (!batchProgressState.inProgress && !activeBatchPlan) {
        return;
    }

    batchProgressState.inProgress = false;
    batchProgressState.inProgressIds = [];
    batchProgressState.lastStatus = BATCH_STATUS_OPTIONS.includes(status) ? status : "failed";
    batchProgressState.lastError = String(message || "Pipeline did not complete.");
    activeBatchPlan = null;
    sessionPipelineCompletedIds.clear();
    pipelineProgressState.phase = status === "interrupted" ? "interrupted" : "failed";
    pipelineProgressState.label = status === "interrupted" ? "Pipeline interrupted" : "Pipeline failed";
    pipelineProgressState.detail = String(message || "Pipeline did not complete.");
    renderPipelineProgressUi();
    renderModelIdList();

    updateBatchStatusUi();
    scheduleSettingsSave();
}

function recoverInterruptedBatchState() {
    const inProgressIds = sanitizeNumericIdList(batchProgressState.inProgressIds);
    if (!batchProgressState.inProgress && inProgressIds.length === 0) {
        return;
    }

    const interruptedCount = inProgressIds.length;
    const runRoot = batchProgressState.lastRunDownloadRoot || "the last selected folder";

    batchProgressState.inProgress = false;
    batchProgressState.inProgressIds = [];
    batchProgressState.lastStatus = "interrupted";
    batchProgressState.lastError = interruptedCount > 0
        ? `Application closed before finishing a batch (${interruptedCount} model(s) pending).`
        : "Application closed before pipeline completion.";
    activeBatchPlan = null;

    updateBatchStatusUi();
    appendRunLog(`[batch] ${batchProgressState.lastError}`, "stderr");
    setStatus(`Detected interrupted pipeline from a previous session in ${runRoot}. Run Execute Pipeline again to continue that batch.`, "warn");
    scheduleSettingsSave();
}

async function executePipeline() {
    if (!mmfDesktopApi || !mmfDesktopApi.startWorkflowStep) {
        setRunStatus("Desktop execution is unavailable in browser mode.", "bad");
        return;
    }

    const readinessState = buildRequirementState();
    if (readinessState.readiness !== 100) {
        const failedRequired = readinessState.requirements
            .filter((item) => item.required && !item.pass)
            .map((item) => item.label);
        const details = failedRequired.length > 0
            ? failedRequired.join(" | ")
            : "Complete the required setup checks.";

        setRunStatus(`Pipeline blocked until setup is ready: ${details}`, "bad");
        setStatus(`Setup not ready: ${details}`, "bad");
        await showAlertDialog(`Pipeline blocked. Fix these checks first:\n- ${details.replace(/ \| /g, "\n- ")}`);
        return;
    }

    if (activeRunId || pipelineRunning || batchProgressState.inProgress) {
        setRunStatus("Another workflow step is already running.", "warn");
        return;
    }

    const batchPlan = getNextBatchPlan();
    if (batchPlan.ids.length === 0) {
        setRunStatus("No pending models left in the current selection.", "warn");
        setStatus("All selected models are already completed for this campaign. Use Reset batch progress if you want to start over.", "warn");
        return;
    }

    pipelineRunning = true;
    beginBatchPipeline(batchPlan);
    await saveSettingsNow();

    const runTestStep = elements.testModeCheck.checked;
    const pipelineSteps = [
        { key: "step1", label: "Step 1" },
        ...(runTestStep ? [{ key: "step2-test", label: "Step 2 Test" }] : []),
        { key: "step2-full", label: "Step 2 Full" }
    ];

    appendRunLog(`[pipeline] Starting automatic execution for batch of ${batchPlan.ids.length} model(s).`);
    appendRunLog(`[pipeline] Batch mode: ${batchPlan.batchMode}. Completed: ${batchPlan.completedCount}. Pending before run: ${batchPlan.pendingCount}.`);
    setRunStatus("Pipeline started.", "ok");

    const preSession = await checkMmfSessionFromUi(true);
    if (preSession && preSession.expired) {
        appendRunLog("[pipeline] Session expired before start. Capture a fresh session.", "stderr");
        setRunStatus("Pipeline blocked: MMF session expired.", "bad");
        finalizeBatchPipelineFailure("Session expired before pipeline start.", "failed");
        pipelineRunning = false;
        setRunButtonsState();
        resetPipelineProgressUi();
        return;
    }

    appendRunLog("[pipeline] Existing files are skipped automatically (resume-safe).");

    try {
        for (const step of pipelineSteps) {
            if (step.key === "step1") {
                setPipelineProgressPhase(
                    "metadata",
                    "Downloading JSON metadata",
                    `Fetching metadata for ${batchPlan.ids.length} model(s) in this batch…`
                );
            } else if (step.key === "step2-test") {
                setPipelineProgressPhase(
                    "step2-test",
                    "Step 2 test run",
                    "Validating cookie with a single test download…"
                );
            } else if (step.key === "step2-full") {
                setPipelineProgressPhase(
                    "step2-full",
                    "Downloading and packaging models",
                    `Processing batch models (0/${batchPlan.ids.length} ZIP-ready)…`
                );
            }

            const startResult = await startWorkflowStep(step.key, step.label, {
                silent: true,
                configOverride: step.key === "step1"
                    ? { modelIdsText: batchPlan.ids.join("\n") }
                    : {}
            });
            if (!startResult || !startResult.accepted) {
                const message = startResult && startResult.message
                    ? startResult.message
                    : `Failed to start ${step.label}.`;
                appendRunLog(`[pipeline] ${message}`, "stderr");
                setRunStatus(`Pipeline stopped: ${message}`, "bad");
                finalizeBatchPipelineFailure(message, "failed");
                return;
            }

            appendRunLog(`[pipeline] ${step.label} launched.`);
            const outcome = await waitForRunCompletion(startResult.runId);

            if (!outcome) {
                appendRunLog("[pipeline] Missing run completion event.", "stderr");
                setRunStatus("Pipeline stopped unexpectedly.", "bad");
                finalizeBatchPipelineFailure("Missing run completion event.", "failed");
                return;
            }

            if (outcome.type === "completed" && outcome.success) {
                appendRunLog(`[pipeline] ${step.label} completed successfully.`);

                if (step.key === "step1" || step.key === "step2-test") {
                    const midSession = await checkMmfSessionFromUi(true);
                    if (midSession && midSession.expired) {
                        appendRunLog(
                            "[pipeline] Session expired between steps. Re-capture session, then re-run from the failed step (completed files are kept).",
                            "stderr"
                        );
                        setRunStatus("Pipeline paused: session expired. Capture session and continue.", "warn");
                        finalizeBatchPipelineFailure("Session expired between pipeline steps.", "interrupted");
                        return;
                    }
                }

                continue;
            }

            if (outcome.type === "stopped") {
                appendRunLog(`[pipeline] ${step.label} was stopped by user.`, "stderr");
                setRunStatus("Pipeline stopped by user.", "warn");
                finalizeBatchPipelineFailure("Pipeline stopped by user.", "interrupted");
                return;
            }

            appendRunLog(`[pipeline] ${step.label} failed.`, "stderr");
            setRunStatus(`Pipeline failed at ${step.label}.`, "bad");
            finalizeBatchPipelineFailure(`Pipeline failed at ${step.label}.`, "failed");
            return;
        }

        finalizeBatchPipelineSuccess();
        appendRunLog("[pipeline] All pipeline steps finished successfully.");
        setRunStatus("Pipeline completed successfully.", "ok");
    } finally {
        pipelineRunning = false;
        setRunButtonsState();
        if (!batchProgressState.inProgress && pipelineProgressState.visible && pipelineProgressState.phase !== "done") {
            resetPipelineProgressUi();
        }
    }
}

async function executePostProcessFromHelper() {
    if (!mmfDesktopApi || !mmfDesktopApi.startWorkflowStep) {
        setRunStatus("Desktop execution is unavailable in browser mode.", "bad");
        return;
    }

    if (activeRunId || pipelineRunning) {
        setRunStatus("Another workflow step is already running.", "warn");
        return;
    }

    await saveSettingsNow();

    pipelineRunning = true;
    setRunButtonsState();
    appendRunLog("[post] Starting optional Step 3 + Step 4 execution.");
    setRunStatus("Running optional Step 3 + Step 4...", "ok");

    const postSteps = [
        { key: "step3", label: "Step 3" },
        { key: "step4", label: "Step 4" }
    ];

    try {
        for (const step of postSteps) {
            const startResult = await startWorkflowStep(step.key, step.label, { silent: true });
            if (!startResult || !startResult.accepted) {
                const message = startResult && startResult.message
                    ? startResult.message
                    : `Failed to start ${step.label}.`;
                appendRunLog(`[post] ${message}`, "stderr");
                setRunStatus(`Optional flow stopped: ${message}`, "bad");
                return;
            }

            appendRunLog(`[post] ${step.label} launched.`);
            const outcome = await waitForRunCompletion(startResult.runId);

            if (!outcome) {
                appendRunLog("[post] Missing run completion event.", "stderr");
                setRunStatus("Optional flow stopped unexpectedly.", "bad");
                return;
            }

            if (outcome.type === "completed" && outcome.success) {
                appendRunLog(`[post] ${step.label} completed successfully.`);
                continue;
            }

            if (outcome.type === "stopped") {
                appendRunLog(`[post] ${step.label} was stopped by user.`, "stderr");
                setRunStatus("Optional flow stopped by user.", "warn");
                return;
            }

            appendRunLog(`[post] ${step.label} failed.`, "stderr");
            setRunStatus(`Optional flow failed at ${step.label}.`, "bad");
            return;
        }

        appendRunLog("[post] Optional Step 3 + Step 4 completed successfully.");
        setRunStatus("Optional Step 3 + Step 4 completed successfully.", "ok");
    } finally {
        pipelineRunning = false;
        setRunButtonsState();
    }
}

async function stopWorkflowStep() {
    if (!mmfDesktopApi || !mmfDesktopApi.stopWorkflowStep) {
        setRunStatus("Desktop execution is unavailable in browser mode.", "bad");
        return;
    }

    if (!activeRunId) {
        setRunStatus("No active run to stop.", "warn");
        return;
    }

    try {
        const result = await mmfDesktopApi.stopWorkflowStep();
        if (result.stopped) {
            setRunStatus("Stop requested. Waiting for process to exit...", "warn");
            return;
        }

        setRunStatus(result.message || "Unable to stop run.", "bad");
    } catch (err) {
        setRunStatus(`Stop request failed: ${String(err?.message || err)}`, "bad");
    }
}

function handleWorkflowLog(payload) {
    if (!payload || !payload.runId || !payload.text) {
        return;
    }

    if (latestRunId && payload.runId !== latestRunId) {
        return;
    }

    appendRunLog(payload.text, payload.stream || "stdout");
}

function handleWorkflowState(payload) {
    if (!payload || !payload.type) {
        return;
    }

    if (payload.type === "cookie-expired") {
        finalizeBatchPipelineFailure(
            payload.message || "MMF session expired during download.",
            "interrupted"
        );
        clearSessionFieldsInForm();
        scheduleSettingsSave();
        appendRunLog(`[session] ${payload.message || "MMF session expired and was cleared."}`, "stderr");
        setStatus(payload.message || "MMF session expired. Open MyMiniFactory and capture again.", "warn");
        updateSessionStatusBadge({ valid: false, message: "expired during download" });
        refreshDashboard();
        return;
    }

    if (payload.runId) {
        latestRunId = payload.runId;
    }

    if (payload.type === "started") {
        activeRunId = payload.runId;
        setRunButtonsState();
        setRunStatus(`${payload.label || "Workflow step"} is running...`, "ok");
        return;
    }

    if (payload.type === "stop-requested") {
        setRunStatus("Stop requested. Waiting for process to terminate...", "warn");
        return;
    }

    if (payload.type === "stopped") {
        const waiter = pendingRunResolvers.get(payload.runId);
        if (waiter) {
            pendingRunResolvers.delete(payload.runId);
            waiter(payload);
        }

        if (activeRunId === payload.runId) {
            activeRunId = null;
        }
        setRunButtonsState();
        appendRunLog(`[stopped] Run ${payload.runId} was stopped by user.`);
        setRunStatus("Run stopped by user.", "warn");
        return;
    }

    if (payload.type === "completed") {
        const waiter = pendingRunResolvers.get(payload.runId);
        if (waiter) {
            pendingRunResolvers.delete(payload.runId);
            waiter(payload);
        }

        if (activeRunId === payload.runId) {
            activeRunId = null;
        }
        setRunButtonsState();

        const code = typeof payload.code === "number" ? payload.code : "unknown";
        appendRunLog(`[exit] Run ${payload.runId} finished with code ${code}.`);

        if (payload.success) {
            refreshModelJsonList().catch(() => {
                // Ignore viewer refresh errors after successful run.
            });
            setRunStatus(`Run completed successfully (code ${code}).`, "ok");
        } else {
            setRunStatus(`Run finished with errors (code ${code}).`, "bad");
        }
        return;
    }

    if (payload.type === "error") {
        const waiter = pendingRunResolvers.get(payload.runId);
        if (waiter) {
            pendingRunResolvers.delete(payload.runId);
            waiter(payload);
        }

        if (activeRunId === payload.runId) {
            activeRunId = null;
        }
        setRunButtonsState();
        appendRunLog(`[error] ${payload.message || "Unknown process error."}`, "stderr");
        setRunStatus("Run crashed due to process error.", "bad");
    }
}

if (elements.autoLoadMyIdsBtn) {
    elements.autoLoadMyIdsBtn.addEventListener("click", autoLoadOwnModelIds);
}

if (elements.batchSizeSelect) {
    elements.batchSizeSelect.addEventListener("change", () => {
        setBatchSizeSelection(elements.batchSizeSelect.value);
        updateBatchStatusUi();
        setRunButtonsState();
        scheduleSettingsSave();
    });
}

if (elements.resetBatchProgressBtn) {
    elements.resetBatchProgressBtn.addEventListener("click", async () => {
        if (isDownloadRootLocked()) {
            setStatus("Cannot reset batch progress while a pipeline is active.", "warn");
            return;
        }

        const confirmed = await showConfirmDialog("Reset completed batch progress for the current model selection?");
        if (!confirmed) {
            return;
        }

        batchProgressState = createDefaultBatchProgressState();
        activeBatchPlan = null;
        reconcileBatchProgressWithCurrentIds();
        refreshDashboard();
        scheduleSettingsSave();
        setStatus("Batch progress has been reset.", "ok");
    });
}

if (elements.openMmfLoginBtn) {
    elements.openMmfLoginBtn.addEventListener("click", openMmfLoginFromUi);
}

if (elements.captureMmfSessionBtn) {
    elements.captureMmfSessionBtn.addEventListener("click", captureMmfSessionFromUi);
}

if (elements.clearCatalogBtn) {
    elements.clearCatalogBtn.addEventListener("click", () => {
        setModelIdEntriesFromText("");
        setStatus("Model list cleared.", "neutral");
        refreshDashboard();
        scheduleSettingsSave();
    });
}

if (elements.clearSessionBtn) {
    elements.clearSessionBtn.addEventListener("click", async () => {
        clearSessionFieldsInForm();
        elements.testModeCheck.checked = true;
        try {
            if (mmfDesktopApi && mmfDesktopApi.clearMmfBrowserSession) {
                await mmfDesktopApi.clearMmfBrowserSession();
            }

            if (mmfDesktopApi && mmfDesktopApi.saveSettings) {
                await mmfDesktopApi.saveSettings({
                    ...getSettingsSnapshot(),
                    cookie: "",
                    medusaJwt: "",
                    medusaPublishableKey: "",
                    mmfUsername: "",
                    sessionCapturedAt: ""
                });
            }
        } catch (_error) {
            // Ignore persistence errors; form was still cleared.
        }

        setStatus("MMF session cleared (including browser cookies).", "neutral");
        updateSessionStatusBadge({ valid: false, message: "cleared manually" });
        refreshDashboard();
    });
}

if (elements.checkSessionBtn) {
    elements.checkSessionBtn.addEventListener("click", () => {
        checkMmfSessionFromUi(false);
    });
}

elements.validateBtn.addEventListener("click", async () => {
    const state = refreshDashboard();
    const failedRequired = state.requirements
        .filter((item) => item.required && !item.pass)
        .map((item) => item.label);

    if (state.readiness === 100) {
        const okMessage = "All required checks passed. You can continue with the workflow.";
        setStatus(okMessage, "ok");
        await showAlertDialog(okMessage);
        return;
    }

    const details = failedRequired.length > 0
        ? failedRequired.join(" | ")
        : "Review the checklist on the right.";

    setStatus(`Setup validation failed: ${details}`, "bad");
    await showAlertDialog(`Setup validation failed:\n- ${details.replace(/ \| /g, "\n- ")}`);
});

elements.downloadIdsBtn.addEventListener("click", () => {
    const state = refreshDashboard();

    if (state.idState.validIds.length === 0) {
        setStatus("Cannot export model_ids.txt: add at least one valid numeric model ID.", "bad");
        return;
    }

    if (state.idState.invalidLines.length > 0) {
        setStatus("Cannot export model_ids.txt: remove invalid lines first.", "bad");
        return;
    }

    downloadTextFile("model_ids.txt", `${state.idState.validIds.join("\n")}\n`);
    setStatus("model_ids.txt exported successfully.", "ok");
});

elements.copyCommandsBtn.addEventListener("click", async () => {
    try {
        await copyText(buildCommandPlan());
        setStatus("Command plan copied to clipboard.", "ok");
    } catch (err) {
        setStatus(`Copy failed: ${err.message}`, "bad");
    }
});

elements.generatePsBtn.addEventListener("click", () => {
    elements.psSnippet.textContent = buildPostProcessSnippet();
    setStatus("Post-process snippet generated. Use Run Step 3 + Step 4 to execute automatically.", "ok");
});

if (elements.useRecommendedPathsBtn) {
    elements.useRecommendedPathsBtn.addEventListener("click", () => {
        if (!runtimeInfoCache) {
            setStatus("Runtime paths are not loaded yet. Try again in a second.", "warn");
            return;
        }

        applyRecommendedPaths(true);
        scheduleSettingsSave();
        setStatus("Recommended paths applied.", "ok");
    });
}

if (elements.browseBasePathBtn) {
    elements.browseBasePathBtn.addEventListener("click", () => {
        pickDirectoryInto(elements.basePathInput, "Select BASE_PATH folder");
    });
}

if (elements.browseJsonPathBtn) {
    elements.browseJsonPathBtn.addEventListener("click", () => {
        pickDirectoryInto(elements.jsonPathInput, "Select JSON_PATH folder");
    });
}

if (elements.browseFoldersPathBtn) {
    elements.browseFoldersPathBtn.addEventListener("click", () => {
        pickDirectoryInto(elements.foldersPathInput, "Select FOLDERS_PATH folder");
    });
}

if (elements.browseDownloadRootBtn) {
    elements.browseDownloadRootBtn.addEventListener("click", async () => {
        if (isDownloadRootLocked()) {
            setStatus("Download folder cannot be changed while a pipeline is active.", "warn");
            return;
        }

        const selected = await pickDirectoryInto(elements.downloadRootInput, "Select download folder");
        if (!selected) {
            return;
        }

        lastStableDownloadRoot = selected.trim();
        rememberDownloadRoot(lastStableDownloadRoot, { save: false });
        scheduleSettingsSave();

        await loadRuntimeInfo();
        await refreshModelJsonList();
    });
}

if (elements.downloadHistoryList) {
    elements.downloadHistoryList.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof HTMLElement)) {
            return;
        }

        const openBtn = target.closest("button[data-path]");
        if (!openBtn) {
            return;
        }

        const pathValue = String(openBtn.dataset.path || "").trim();
        if (!pathValue) {
            return;
        }

        openPathFromUi(pathValue, "Saved download folder");
    });
}

if (elements.openDownloadRootBtn) {
    elements.openDownloadRootBtn.addEventListener("click", () => {
        openPathFromUi(getActiveDownloadsPath(), "Download folder");
    });
}

if (elements.openFilesFolderBtn) {
    elements.openFilesFolderBtn.addEventListener("click", () => {
        const preferredPath = getActiveStlFilesPath() || getActiveDownloadsPath();
        openPathFromUi(preferredPath, "Files folder");
    });
}

if (elements.openJsonFolderBtn) {
    elements.openJsonFolderBtn.addEventListener("click", () => {
        openPathFromUi(getActiveDownloadsPath(), "JSON folder");
    });
}

if (elements.refreshJsonListBtn) {
    elements.refreshJsonListBtn.addEventListener("click", () => {
        refreshModelJsonList();
    });
}

if (elements.jsonFileSelect) {
    elements.jsonFileSelect.addEventListener("change", () => {
        loadSelectedModelJson();
    });
}

elements.copyPsBtn.addEventListener("click", async () => {
    const snippet = buildPostProcessSnippet();
    elements.psSnippet.textContent = snippet;

    try {
        await copyText(snippet);
        setStatus("Post-process snippet copied.", "ok");
    } catch (err) {
        setStatus(`Copy failed: ${err.message}`, "bad");
    }
});

elements.depRefreshBtn.addEventListener("click", runDependencyCheck);
elements.depInstallBtn.addEventListener("click", installMissingDependencies);
elements.depSkipBtn.addEventListener("click", () => {
    elements.desktopGate.classList.add("hidden");
    setStatus("Dependency install skipped. You can continue, but scripts may fail until dependencies are installed.", "warn");
});

elements.runExecuteBtn.addEventListener("click", executePipeline);
if (elements.runNextBatchBtn) {
    elements.runNextBatchBtn.addEventListener("click", executePipeline);
}
elements.runStep1Btn.addEventListener("click", () => startWorkflowStep("step1", "Step 1"));
elements.runStep2TestBtn.addEventListener("click", () => startWorkflowStep("step2-test", "Step 2 Test"));
elements.runStep2FullBtn.addEventListener("click", () => startWorkflowStep("step2-full", "Step 2 Full"));
elements.runStep3Btn.addEventListener("click", () => startWorkflowStep("step3", "Step 3"));
elements.runStep4Btn.addEventListener("click", () => startWorkflowStep("step4", "Step 4"));
if (elements.runPostProcessBtn) {
    elements.runPostProcessBtn.addEventListener("click", executePostProcessFromHelper);
}
elements.stopRunBtn.addEventListener("click", stopWorkflowStep);
elements.clearLogBtn.addEventListener("click", clearRunLog);

if (elements.creatorIdFilterInput) {
    ["input", "change"].forEach((eventName) => {
        elements.creatorIdFilterInput.addEventListener(eventName, () => {
            refreshDashboard();
            scheduleSettingsSave();
        });
    });
}

if (elements.categorySelectionList) {
    elements.categorySelectionList.addEventListener("change", (event) => {
        const target = event.target;
        if (!(target instanceof HTMLInputElement) || target.type !== "checkbox") {
            return;
        }

        const categoryId = String(target.dataset.categoryId || "").trim();
        if (!categoryId) {
            return;
        }

        const subcategoryId = String(target.dataset.subcategoryId || "").trim();

        if (!subcategoryId) {
            if (!target.checked) {
                categorySelectionMap.delete(categoryId);
            } else if (!categorySelectionMap.has(categoryId)) {
                categorySelectionMap.set(categoryId, new Set());
            }
        } else {
            const subcategories = categorySelectionMap.get(categoryId) || new Set();
            if (target.checked) {
                subcategories.add(subcategoryId);
            } else {
                subcategories.delete(subcategoryId);
            }
            categorySelectionMap.set(categoryId, subcategories);
        }

        renderCategorySelection();
        refreshDashboard();
        scheduleSettingsSave();
    });
}

[elements.phpSessidInput, elements.cfClearanceInput, elements.jwtInput, elements.publishableKeyInput, elements.testModeCheck].forEach((input) => {
    input.addEventListener("input", () => {
        refreshDashboard();
        scheduleSettingsSave();
    });
    input.addEventListener("change", () => {
        refreshDashboard();
        scheduleSettingsSave();
    });
});

document.querySelectorAll(".secret-toggle").forEach((button) => {
    button.addEventListener("click", () => {
        const targetId = button.getAttribute("data-target");
        const targetInput = targetId ? document.getElementById(targetId) : null;
        if (!targetInput) {
            return;
        }

        const reveal = targetInput.type === "password";
        targetInput.type = reveal ? "text" : "password";
        button.textContent = reveal ? "Hide" : "Show";
        button.setAttribute("aria-label", reveal ? "Hide value" : "Show value");
    });
});

if (elements.downloadRootInput) {
    elements.downloadRootInput.addEventListener("input", () => {
        if (isDownloadRootLocked()) {
            elements.downloadRootInput.value = lastStableDownloadRoot;
            setStatus("Download folder cannot be changed while a pipeline is active.", "warn");
            return;
        }

        updatePathHelperHint();
        scheduleSettingsSave();
    });

    elements.downloadRootInput.addEventListener("change", async () => {
        if (isDownloadRootLocked()) {
            elements.downloadRootInput.value = lastStableDownloadRoot;
            setStatus("Download folder cannot be changed while a pipeline is active.", "warn");
            return;
        }

        lastStableDownloadRoot = elements.downloadRootInput.value.trim();
        if (lastStableDownloadRoot) {
            rememberDownloadRoot(lastStableDownloadRoot, { save: false });
        }

        updatePathHelperHint();
        scheduleSettingsSave();
        await loadRuntimeInfo();
        await refreshModelJsonList();
    });
}

[
    elements.basePathInput,
    elements.extractModeSelect,
    elements.jsonPathInput,
    elements.foldersPathInput,
    elements.namingFormatSelect,
    elements.maxLengthInput
].forEach((input) => {
    input.addEventListener("input", () => {
        updatePathHelperHint();
        scheduleSettingsSave();
    });
    input.addEventListener("change", () => {
        updatePathHelperHint();
        scheduleSettingsSave();
    });
});

if (mmfDesktopApi && mmfDesktopApi.onWorkflowLog) {
    mmfDesktopApi.onWorkflowLog(handleWorkflowLog);
}

if (mmfDesktopApi && mmfDesktopApi.onWorkflowState) {
    mmfDesktopApi.onWorkflowState(handleWorkflowState);
}

getCatalogLoadModeInputs().forEach((input) => {
    input.addEventListener("change", () => {
        updateCreatorFilterVisibility();
        refreshDashboard();
        scheduleSettingsSave();
    });
});

setModelIdEntriesFromText(elements.idsInput.value);
setupModelIdList();
renderCategorySelection();
updateCreatorFilterVisibility();
setRunButtonsState();
refreshDashboard();
updatePathHelperHint();

Promise.resolve()
    .then(() => loadCategoryTaxonomyFromDesktop())
    .then(() => loadSavedSettings())
    .then(() => recoverInterruptedBatchState())
    .then(() => checkMmfSessionFromUi(true))
    .then(() => loadRuntimeInfo())
    .then(() => refreshModelJsonList())
    .then(() => runDependencyCheck());

})();