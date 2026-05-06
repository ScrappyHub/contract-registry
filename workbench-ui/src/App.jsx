import { useEffect, useMemo, useRef, useState } from "react";

function valueAfter(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function stepStatus(log, step) {
  if (log.includes(`STEP_OK: ${step}`)) return "done";
  if (log.includes(`STEP_START: ${step}`)) return "running";
  return "idle";
}

const tabs = ["Pipeline", "Workspace", "Evidence", "Settings"];
const STORAGE_KEY = "contract_registry_workbench_v012_state";

function loadSavedState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export default function App() {
  const saved = useMemo(() => loadSavedState(), []);

  const [activeTab, setActiveTab] = useState(saved.activeTab || "Pipeline");

  const [repoRoot, setRepoRoot] = useState(saved.repoRoot || "C:\\dev\\contract-registry");
  const [workspace, setWorkspace] = useState(saved.workspace || "C:\\dev\\contract-registry\\workbench\\workspace");
  const [folderPath, setFolderPath] = useState(saved.folderPath || "C:\\dev\\contract-registry\\workbench\\workspace\\contract_bundle_unzipped");
  const [repoImportPath, setRepoImportPath] = useState(saved.repoImportPath || "C:\\dev\\contract-registry");

  const [log, setLog] = useState(saved.log || "");
  const [running, setRunning] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState(saved.importError || "");
  const [importToken, setImportToken] = useState(saved.importToken || "");
  const [bundleSummary, setBundleSummary] = useState(saved.bundleSummary || null);
  const [openStatus, setOpenStatus] = useState("");

  const fileRef = useRef(null);

  useEffect(() => {
    const snapshot = {
      activeTab,
      repoRoot,
      workspace,
      folderPath,
      repoImportPath,
      log,
      importError,
      importToken,
      bundleSummary
    };

    localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
  }, [
    activeTab,
    repoRoot,
    workspace,
    folderPath,
    repoImportPath,
    log,
    importError,
    importToken,
    bundleSummary
  ]);

  const status = useMemo(() => {
    if (running) return "RUNNING";
    if (log.includes("WORKBENCH_FULL_PIPELINE_GREEN")) return "GREEN";
    if (log.includes("PROCESS_EXIT_CODE:0")) return "DONE";
    if (log.includes("ERR:") || /PROCESS_EXIT_CODE:(?!0)\d+/.test(log)) return "FAILED";
    return "IDLE";
  }, [running, log]);

  const artifacts = useMemo(() => {
    return {
      release: valueAfter("LATEST_RELEASE:", log),
      exportDir: valueAfter("EVIDENCE_EXPORT_DIR:", log),
      receipt: valueAfter("EVIDENCE_EXPORT_RECEIPT:", log),
      receiptHash: valueAfter("EVIDENCE_EXPORT_RECEIPT_SHA256:", log),
      shaPath: valueAfter("SHA256SUMS:", log),
      shaHash: valueAfter("SHA256SUMS_HASH:", log)
    };
  }, [log]);

  const steps = [
    { key: "inspect", title: "Inspect" },
    { key: "build", title: "Build" },
    { key: "verify", title: "Verify" },
    { key: "export", title: "Export" }
  ];

  const importedRoot = workspace + "\\input\\contract";
  const outputRoot = workspace + "\\output";
  const releasesRoot = outputRoot + "\\releases";
  const exportsRoot = outputRoot + "\\exports";

  function setImportOk(data, label) {
    setImportToken(data.token || "WORKBENCH_IMPORT_OK");
    setBundleSummary(data.summary || null);
    setLog((prev) => prev + label + "\nWORKBENCH_IMPORT_OK\n");
  }

  async function importBundle(file) {
    if (!file) return;
    setImporting(true);
    setImportError("");
    setImportToken("");
    setBundleSummary(null);

    try {
      const form = new FormData();
      form.append("bundle", file);
      form.append("workspace", workspace);

      const response = await fetch("http://localhost:5175/api/import-bundle", {
        method: "POST",
        body: form
      });

      const data = await response.json();

      if (!data.ok) {
        setImportError(data.error || "IMPORT_FAILED");
        return;
      }

      setImportOk(data, "IMPORT_MODE: zip");
    } catch (err) {
      setImportError("IMPORT_REQUEST_FAILED: " + err.message);
    } finally {
      setImporting(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  async function importFolder() {
    setImporting(true);
    setImportError("");
    setImportToken("");
    setBundleSummary(null);

    try {
      const response = await fetch("http://localhost:5175/api/import-folder", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ folderPath, workspace })
      });

      const data = await response.json();

      if (!data.ok) {
        setImportError(data.error || "IMPORT_FOLDER_FAILED");
        return;
      }

      setImportOk(data, "IMPORT_MODE: folder");
    } catch (err) {
      setImportError("IMPORT_FOLDER_REQUEST_FAILED: " + err.message);
    } finally {
      setImporting(false);
    }
  }

  async function importRepo() {
    setImporting(true);
    setImportError("");
    setImportToken("");
    setBundleSummary(null);

    try {
      const response = await fetch("http://localhost:5175/api/import-repo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoPath: repoImportPath, workspace })
      });

      const data = await response.json();

      if (!data.ok) {
        setImportError(data.error || "IMPORT_REPO_FAILED");
        return;
      }

      setImportOk(data, "IMPORT_MODE: repo");
    } catch (err) {
      setImportError("IMPORT_REPO_REQUEST_FAILED: " + err.message);
    } finally {
      setImporting(false);
    }
  }

  async function openPath(targetPath) {
    if (!targetPath) return;

    setOpenStatus("");

    try {
      const response = await fetch("http://localhost:5175/api/open-path", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetPath })
      });

      const data = await response.json();

      if (!data.ok) {
        setOpenStatus(data.error || "OPEN_PATH_FAIL");
        return;
      }

      setOpenStatus("OPEN_PATH_OK");
    } catch (err) {
      setOpenStatus("OPEN_PATH_REQUEST_FAILED: " + err.message);
    }
  }

  async function runPipeline() {
    setLog("");
    setRunning(true);
    setOpenStatus("");

    try {
      const response = await fetch("http://localhost:5175/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoRoot, workspace })
      });

      if (!response.body) {
        setLog("ERR: RESPONSE_BODY_MISSING\n");
        setRunning(false);
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        setLog((prev) => prev + decoder.decode(value, { stream: true }));
      }
    } catch (err) {
      setLog((prev) => prev + "ERR: REQUEST_FAILED: " + err.message + "\n");
    } finally {
      setRunning(false);
    }
  }

  function StatusCard() {
    return (
      <div className="card">
        <h2>Status</h2>
        <div className="status-row">
          <span>Pipeline State</span>
          <strong className={status === "GREEN" ? "ok" : status === "RUNNING" ? "warn" : status === "FAILED" ? "bad" : "muted"}>{status}</strong>
        </div>
        <div className="status-row">
          <span>Import Token</span>
          <strong className={importToken ? "ok" : "muted"}>{importToken || "-"}</strong>
        </div>
        <div className="status-row">
          <span>Import Error</span>
          <strong className={importError ? "bad" : "muted"}>{importError || "-"}</strong>
        </div>
        <div className="status-row">
          <span>Open Path</span>
          <strong className={openStatus === "OPEN_PATH_OK" ? "ok" : openStatus ? "bad" : "muted"}>{openStatus || "-"}</strong>
        </div>
      </div>
    );
  }

  function StepTracker() {
    return (
      <div className="card">
        <h2>Step Tracker</h2>
        <div className="step-grid">
          {steps.map((step) => {
            const s = stepStatus(log, step.key);
            return (
              <div className={`step-card ${s}`} key={step.key}>
                <div className="step-title">{step.title}</div>
                <div className="step-state">{s.toUpperCase()}</div>
              </div>
            );
          })}
        </div>
      </div>
    );
  }

  function ImportedSummaryCards() {
    return (
      <section className="panel grid-two">
        <div className="card">
          <h2>Imported Contract Summary</h2>
          <div className="mono-block">
            {!bundleSummary ? "-" : [
              "contract_key: " + (bundleSummary?.manifest?.contract_key || "-"),
              "version_label: " + (bundleSummary?.manifest?.version_label || bundleSummary?.version?.version_label || "-"),
              "policy_overlay_count: " + String(bundleSummary?.counts?.policyOverlays ?? 0),
              "schema_overlay_count: " + String(bundleSummary?.counts?.schemaOverlays ?? 0),
              "manifest_sha256: " + (bundleSummary?.hashes?.manifest || "-"),
              "contract_sha256: " + (bundleSummary?.hashes?.contract || "-"),
              "version_sha256: " + (bundleSummary?.hashes?.version || "-")
            ].join("\n")}
          </div>
        </div>

        <div className="card">
          <h2>Imported Overlay Files</h2>
          <div className="mono-block">
            {!bundleSummary ? "-" : [
              "# policy",
              ...(bundleSummary?.files?.policy?.length ? bundleSummary.files.policy : ["-"]),
              "# schema",
              ...(bundleSummary?.files?.schema?.length ? bundleSummary.files.schema : ["-"])
            ].join("\n")}
          </div>
        </div>
      </section>
    );
  }

  function ArtifactCards() {
    return (
      <section className="panel grid-two">
        <div className="card">
          <h2>Latest Release</h2>
          <div className="mono-block">{artifacts.release || "-"}</div>
          <button className="small-btn" onClick={() => openPath(artifacts.release)} disabled={!artifacts.release}>Open Release Folder</button>

          <h2 style={{ marginTop: "16px" }}>SHA256SUMS</h2>
          <div className="mono-block">{artifacts.shaPath || "-"}</div>
          <div className="mono-block">{artifacts.shaHash || "-"}</div>
        </div>

        <div className="card">
          <h2>Latest Export</h2>
          <div className="mono-block">{artifacts.exportDir || "-"}</div>
          <button className="small-btn" onClick={() => openPath(artifacts.exportDir)} disabled={!artifacts.exportDir}>Open Export Folder</button>

          <h2 style={{ marginTop: "16px" }}>Export Receipt</h2>
          <div className="mono-block">{artifacts.receipt || "-"}</div>
          <div className="mono-block">{artifacts.receiptHash || "-"}</div>
        </div>
      </section>
    );
  }

  function PipelineTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Inputs</h2>

            <label className="field">
              <span>Repo Root</span>
              <input value={repoRoot} onChange={(e) => setRepoRoot(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Workspace</span>
              <input value={workspace} onChange={(e) => setWorkspace(e.target.value)} disabled={running || importing} />
            </label>
          </div>

          <StatusCard />
        </section>

        <section className="panel">
          <StepTracker />
        </section>

        <section className="panel grid-two">
          <div className="card">
            <h2>Import Zip Bundle</h2>
            <label className="run-btn" style={{ display: "inline-flex", alignItems: "center" }}>
              {importing ? "Importing..." : "Import Bundle Zip"}
              <input ref={fileRef} type="file" accept=".zip" style={{ display: "none" }} disabled={importing || running} onChange={(e) => importBundle(e.target.files?.[0] || null)} />
            </label>
          </div>

          <div className="card">
            <h2>Import Folder / Repo</h2>

            <label className="field">
              <span>Folder Bundle Path</span>
              <input value={folderPath} onChange={(e) => setFolderPath(e.target.value)} disabled={running || importing} />
            </label>
            <button className="run-btn" onClick={importFolder} disabled={running || importing}>Import Folder</button>

            <label className="field" style={{ marginTop: "14px" }}>
              <span>Repo Path</span>
              <input value={repoImportPath} onChange={(e) => setRepoImportPath(e.target.value)} disabled={running || importing} />
            </label>
            <button className="run-btn" onClick={importRepo} disabled={running || importing}>Import Repo</button>
          </div>
        </section>

        <ImportedSummaryCards />
        <ArtifactCards />

        <section className="panel">
          <div className="card">
            <h2>Live Output</h2>
            <pre className="console">{log || "No output yet."}</pre>
          </div>
        </section>
      </>
    );
  }

  function WorkspaceTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Workspace Paths</h2>
            <div className="mono-block">repo_root: {repoRoot}</div>
            <button className="small-btn" onClick={() => openPath(repoRoot)}>Open Repo Root</button>

            <div className="mono-block" style={{ marginTop: "12px" }}>workspace: {workspace}</div>
            <button className="small-btn" onClick={() => openPath(workspace)}>Open Workspace</button>

            <div className="mono-block" style={{ marginTop: "12px" }}>input_contract: {importedRoot}</div>
            <button className="small-btn" onClick={() => openPath(importedRoot)}>Open Input Contract</button>
          </div>

          <StatusCard />
        </section>

        <ImportedSummaryCards />

        <section className="panel grid-two">
          <div className="card">
            <h2>Workspace Output Roots</h2>
            <div className="mono-block">output: {outputRoot}</div>
            <button className="small-btn" onClick={() => openPath(outputRoot)}>Open Output Root</button>

            <div className="mono-block" style={{ marginTop: "12px" }}>releases: {releasesRoot}</div>
            <button className="small-btn" onClick={() => openPath(releasesRoot)}>Open Releases Root</button>

            <div className="mono-block" style={{ marginTop: "12px" }}>exports: {exportsRoot}</div>
            <button className="small-btn" onClick={() => openPath(exportsRoot)}>Open Exports Root</button>
          </div>

          <div className="card">
            <h2>Current Import Sources</h2>
            <div className="mono-block">folder_bundle_path: {folderPath}</div>
            <div className="mono-block" style={{ marginTop: "12px" }}>repo_import_path: {repoImportPath}</div>
          </div>
        </section>
      </>
    );
  }

  function EvidenceTab() {
    return (
      <>
        <ArtifactCards />

        <section className="panel grid-two">
          <div className="card">
            <h2>Verification Evidence</h2>
            <div className="mono-block">
              {[
                "pipeline_state: " + status,
                "inspect: " + stepStatus(log, "inspect").toUpperCase(),
                "build: " + stepStatus(log, "build").toUpperCase(),
                "verify: " + stepStatus(log, "verify").toUpperCase(),
                "export: " + stepStatus(log, "export").toUpperCase(),
                "full_green: " + String(log.includes("WORKBENCH_FULL_PIPELINE_GREEN"))
              ].join("\n")}
            </div>
          </div>

          <div className="card">
            <h2>Receipt Summary</h2>
            <div className="mono-block">
              {[
                "receipt_path: " + (artifacts.receipt || "-"),
                "receipt_sha256: " + (artifacts.receiptHash || "-"),
                "sha256sums_path: " + (artifacts.shaPath || "-"),
                "sha256sums_sha256: " + (artifacts.shaHash || "-")
              ].join("\n")}
            </div>
          </div>
        </section>

        <section className="panel">
          <StepTracker />
        </section>
      </>
    );
  }

  function SettingsTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Local Settings</h2>

            <label className="field">
              <span>Repo Root</span>
              <input value={repoRoot} onChange={(e) => setRepoRoot(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Workspace</span>
              <input value={workspace} onChange={(e) => setWorkspace(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Folder Bundle Path</span>
              <input value={folderPath} onChange={(e) => setFolderPath(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Repo Import Path</span>
              <input value={repoImportPath} onChange={(e) => setRepoImportPath(e.target.value)} disabled={running || importing} />
            </label>
          </div>

          <div className="card">
            <h2>Runtime Ports</h2>
            <div className="mono-block">
              {[
                "ui_dev_port: 5174",
                "local_bridge_port: 5175",
                "public_hosting: disabled",
                "desktop_ready: true"
              ].join("\n")}
            </div>

            <h2 style={{ marginTop: "16px" }}>Reset Local UI State</h2>
            <button className="run-btn" onClick={() => {
              localStorage.removeItem(STORAGE_KEY);
              setLog("");
              setImportError("");
              setImportToken("");
              setBundleSummary(null);
              setOpenStatus("");
              setActiveTab("Pipeline");
            }}>
              Reset UI State
            </button>
          </div>
        </section>
      </>
    );
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-title">Contract Registry</div>
          <div className="brand-subtitle">Workbench v0.1.2 Local</div>
        </div>
        <nav className="nav">
          {tabs.map((tab) => (
            <button
              key={tab}
              className={`nav-item nav-button ${activeTab === tab ? "active" : ""}`}
              onClick={() => setActiveTab(tab)}
            >
              {tab}
            </button>
          ))}
        </nav>
      </aside>

      <main className="main">
        <header className="header">
          <div>
            <h1>{activeTab}</h1>
            <p>
              {activeTab === "Pipeline" && "Local operator dashboard over the deterministic engine."}
              {activeTab === "Workspace" && "Workspace paths, import state, and local artifact roots."}
              {activeTab === "Evidence" && "Release, export, receipt, and verification evidence."}
              {activeTab === "Settings" && "Local-only settings for paths, ports, and UI state."}
            </p>
          </div>

          {activeTab === "Pipeline" && (
            <button className="run-btn" onClick={runPipeline} disabled={running || importing}>
              {running ? "Running..." : "Run Pipeline"}
            </button>
          )}
        </header>

        {activeTab === "Pipeline" && <PipelineTab />}
        {activeTab === "Workspace" && <WorkspaceTab />}
        {activeTab === "Evidence" && <EvidenceTab />}
        {activeTab === "Settings" && <SettingsTab />}
      </main>
    </div>
  );
}
