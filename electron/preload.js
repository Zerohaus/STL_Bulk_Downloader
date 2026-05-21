const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("desktopApi", {
    checkDependencies: () => ipcRenderer.invoke("desktop:check-dependencies"),
    installMissingDependencies: () => ipcRenderer.invoke("desktop:install-missing-dependencies"),
    getRuntimeInfo: (payload) => ipcRenderer.invoke("desktop:get-runtime-info", payload),
    pickDirectory: (payload) => ipcRenderer.invoke("desktop:pick-directory", payload),
    openPath: (payload) => ipcRenderer.invoke("desktop:open-path", payload),
    listModelJsonFiles: (payload) => ipcRenderer.invoke("desktop:list-model-json-files", payload),
    readModelJsonFile: (payload) => ipcRenderer.invoke("desktop:read-model-json-file", payload),
    getCategoryTaxonomy: () => ipcRenderer.invoke("desktop:get-category-taxonomy"),
    loadSettings: () => ipcRenderer.invoke("desktop:load-settings"),
    saveSettings: (payload) => ipcRenderer.invoke("desktop:save-settings", payload),
    resolveOwnModelIds: (payload) => ipcRenderer.invoke("desktop:resolve-own-model-ids", payload),
    showConfirmDialog: (payload) => ipcRenderer.invoke("desktop:show-confirm-dialog", payload),
    showAlertDialog: (payload) => ipcRenderer.invoke("desktop:show-alert-dialog", payload),
    openMmfLogin: () => ipcRenderer.invoke("desktop:open-mmf-login"),
    captureMmfSession: () => ipcRenderer.invoke("desktop:capture-mmf-session"),
    validateMmfSession: () => ipcRenderer.invoke("desktop:validate-mmf-session"),
    closeMmfLogin: () => ipcRenderer.invoke("desktop:close-mmf-login"),
    clearMmfBrowserSession: () => ipcRenderer.invoke("desktop:clear-mmf-browser-session"),
    startWorkflowStep: (payload) => ipcRenderer.invoke("desktop:start-workflow-step", payload),
    stopWorkflowStep: () => ipcRenderer.invoke("desktop:stop-workflow-step"),
    onWorkflowLog: (handler) => {
        const listener = (_event, payload) => handler(payload);
        ipcRenderer.on("workflow:log", listener);
        return () => ipcRenderer.removeListener("workflow:log", listener);
    },
    onWorkflowState: (handler) => {
        const listener = (_event, payload) => handler(payload);
        ipcRenderer.on("workflow:state", listener);
        return () => ipcRenderer.removeListener("workflow:state", listener);
    },
    onCatalogProgress: (handler) => {
        const listener = (_event, payload) => handler(payload);
        ipcRenderer.on("catalog:progress", listener);
        return () => ipcRenderer.removeListener("catalog:progress", listener);
    }
});
