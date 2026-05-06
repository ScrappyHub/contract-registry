import { useEffect, useMemo, useRef, useState } from "react";

const STORAGE_KEY = "contract_registry_workbench_simple_v1";
const tabs = ["Build", "Files", "Evidence", "Settings"];

function valueAfter(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function stepStatus(log, step) {
  if (log.includes(`STEP_OK: ${step}`)) return "done";
  if (log.includes(`STEP_START: ${step}`)) return "running";
  return "idle";
}

function loadSavedState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function explainError(error) {
  if (!error) return "-";

  if (error.includes("IMPORT_FAIL_REPO_BUNDLE_NOT_FOUND")) {
    return "No Contract Registry bundle was found in that repo.";
  }

  if (error.includes("IMPORT_FAIL_SOURCE_EQUALS_DESTINATION")) {
    return "That folder is already the active workspace input. Choose a separate source folder.";
  }

  if (error.includes("IMPORT_FAIL_SOURCE_NOT_FOUND")) {
    return "That folder does not exist.";
  }

  if (error.includes("IMPORT_FAIL_MISSING_FILE")) {
    return "The selected source is missing manifest.json, contract.json, or version.json.";
  }

  if (error.includes("IMPORT_FAIL_INVALID_JSON")) {
    return "One of the bundle JSON files is invalid.";
  }

  if (error.includes("EPERM")) {
    return "Windows blocked access to that folder. Close Explorer or apps using it, then try again.";
  }

  if (error.includes("OPEN_PATH_NOT_FOUND")) {
    return "That folder does not exist yet.";
  }

  return error;
}

export default function App() {
  const saved = useMemo(() => loadSavedState(), []);

  const [activeTab, setActiveTab] = useState(saved.activeTab || "Build");

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
  const [uploadBundle, setUploadBundle] = useState(saved.uploadBundle || null);
  const [uploadError, setUploadError] = useState("");

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
      bundleSummary,
      uploadBundle
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
    bundleSummary,
    uploadBundle
  ]);

  const pipelineState = useMemo(() => {
    if (running) return "Running";
    if (log.includes("WORKBENCH_FULL_PIPELINE_GREEN")) return "Package ready";
    if (log.includes("PROCESS_EXIT_CODE:0")) return "Finished";
    if (log.includes("ERR:") || /PROCESS_EXIT_CODE:(?!0)\d+/.test(log)) return "Failed";
    return "Ready";
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

  const hasImportedBundle = importToken === "WORKBENCH_IMPORT_OK" && !!bundleSummary;
  const hasPackage = log.includes("WORKBENCH_FULL_PIPELINE_GREEN") && !!artifacts.exportDir;

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
    setImportError("");
    setUploadBundle(null);
    setUploadError("");
    setLog(label + "\nWORKBENCH_IMPORT_OK\n");
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

      setImportOk(data, "Imported zip bundle.");
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

      setImportOk(data, "Imported folder bundle.");
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

      setImportOk(data, "Imported bundle from repo.");
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

  async function createUploadBundle() {
    if (!artifacts.exportDir) return;

    setUploadError("");
    setUploadBundle(null);

    try {
      const response = await fetch("http://localhost:5175/api/export-upload-bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ exportDir: artifacts.exportDir })
      });

      const data = await response.json();

      if (!data.ok) {
        setUploadError(data.error || "EXPORT_UPLOAD_BUNDLE_FAILED");
        return;
      }

      setUploadBundle(data);
    } catch (err) {
      setUploadError("EXPORT_UPLOAD_REQUEST_FAILED: " + err.message);
    }
  }

  async function runPipeline() {
    setLog("");
    setRunning(true);
    setOpenStatus("");
    setUploadBundle(null);
    setUploadError("");

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

  function WorkflowStep({ number, title, text, done }) {
    return (
      <div className={`workflow-step ${done ? "done" : ""}`}>
        <div className="workflow-number">{number}</div>
        <div>
          <div className="workflow-title">{title}</div>
          <div className="workflow-text">{text}</div>
        </div>
      </div>
    );
  }

  function StepTracker() {
    return (
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
    );
  }

  function SourceCard() {
    return (
      <div className="card">
        <h2>Choose source</h2>
        <p className="plain-text">
          Import a Contract Registry bundle. Repos only work when they contain a bundle folder.
        </p>

        <div className="button-row">
          <label className="run-btn">
            {importing ? "Importing..." : "Import Zip"}
            <input
              ref={fileRef}
              type="file"
              accept=".zip"
              style={{ display: "none" }}
              disabled={importing || running}
              onChange={(e) => importBundle(e.target.files?.[0] || null)}
            />
          </label>

          <button className="run-btn secondary" onClick={importFolder} disabled={running || importing}>
            Import Folder
          </button>

          <button className="run-btn secondary" onClick={importRepo} disabled={running || importing}>
            Import Bundle from Repo
          </button>
        </div>

        {importError ? <div className="notice bad-notice">{explainError(importError)}</div> : null}

        {hasImportedBundle ? (
          <div className="notice ok-notice">
            Source ready: {bundleSummary?.manifest?.contract_key || "Contract bundle"} / {bundleSummary?.manifest?.version_label || bundleSummary?.version?.version_label || "version"}
          </div>
        ) : (
          <div className="notice muted-notice">No source imported yet.</div>
        )}
      </div>
    );
  }

  function BuildCard() {
    return (
      <div className="card hero-card">
        <h2>Build package</h2>
        <p className="plain-text">
          Run the local deterministic engine to inspect, build, verify, and export the contract package.
        </p>

        <button className="big-action" onClick={runPipeline} disabled={running || importing}>
          {running ? "Building..." : "Build Contract Package"}
        </button>

        <div className={`package-state ${hasPackage ? "ready" : running ? "running" : ""}`}>
          {pipelineState}
        </div>

        <StepTracker />
      </div>
    );
  }

  function ResultCard() {
    return (
      <div className="card">
        <h2>Review result</h2>

        {hasPackage ? (
          <>
            <div className="result-success">Package created successfully.</div>

            <div className="simple-artifact">
              <span>Export folder</span>
              <strong>{artifacts.exportDir}</strong>
            </div>

            <div className="simple-artifact">
              <span>Receipt hash</span>
              <strong>{artifacts.receiptHash}</strong>
            </div>

            <div className="button-row">
              <button className="run-btn secondary" onClick={() => openPath(artifacts.exportDir)}>
                Open Export Folder
              </button>

              <button className="run-btn secondary" onClick={createUploadBundle}>
                Create Upload Bundle
              </button>
            </div>

            {uploadBundle ? (
              <div className="notice ok-notice">
                Upload bundle ready: {uploadBundle.zipPath}
              </div>
            ) : null}

            {uploadError ? (
              <div className="notice bad-notice">{explainError(uploadError)}</div>
            ) : null}
          </>
        ) : (
          <div className="notice muted-notice">
            Build a package to see the export folder and upload bundle here.
          </div>
        )}
      </div>
    );
  }

  function BuildTab() {
    return (
      <>
        <section className="panel workflow-grid">
          <WorkflowStep
            number="1"
            title="Choose source"
            text={hasImportedBundle ? "Source imported" : "Import a zip, folder, or bundle-ready repo"}
            done={hasImportedBundle}
          />
          <WorkflowStep
            number="2"
            title="Build package"
            text={hasPackage ? "Build completed" : "Run the local engine"}
            done={hasPackage}
          />
          <WorkflowStep
            number="3"
            title="Review result"
            text={uploadBundle ? "Upload bundle ready" : "Create export/upload package"}
            done={!!uploadBundle}
          />
        </section>

        <section className="panel grid-three">
          <SourceCard />
          <BuildCard />
          <ResultCard />
        </section>
      </>
    );
  }

  function FilesTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Source paths</h2>

            <label className="field">
              <span>Folder bundle path</span>
              <input value={folderPath} onChange={(e) => setFolderPath(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Repo path</span>
              <input value={repoImportPath} onChange={(e) => setRepoImportPath(e.target.value)} disabled={running || importing} />
            </label>

            <div className="button-row">
              <button className="run-btn secondary" onClick={() => openPath(folderPath)}>Open Folder Source</button>
              <button className="run-btn secondary" onClick={() => openPath(repoImportPath)}>Open Repo Source</button>
            </div>
          </div>

          <div className="card">
            <h2>Workspace</h2>
            <div className="simple-artifact"><span>Input</span><strong>{importedRoot}</strong></div>
            <div className="simple-artifact"><span>Output</span><strong>{outputRoot}</strong></div>
            <div className="button-row">
              <button className="run-btn secondary" onClick={() => openPath(importedRoot)}>Open Input</button>
              <button className="run-btn secondary" onClick={() => openPath(outputRoot)}>Open Output</button>
            </div>
          </div>
        </section>

        <section className="panel grid-two">
          <div className="card">
            <h2>Latest release</h2>
            <div className="mono-block">{artifacts.release || "-"}</div>
            <button className="small-btn" onClick={() => openPath(artifacts.release)} disabled={!artifacts.release}>Open Release Folder</button>
          </div>

          <div className="card">
            <h2>Latest export</h2>
            <div className="mono-block">{artifacts.exportDir || "-"}</div>
            <button className="small-btn" onClick={() => openPath(artifacts.exportDir)} disabled={!artifacts.exportDir}>Open Export Folder</button>
          </div>
        </section>
      </>
    );
  }

  function EvidenceTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Human summary</h2>
            <div className="mono-block">
              {[
                "state: " + pipelineState,
                "contract: " + (bundleSummary?.manifest?.contract_key || "-"),
                "version: " + (bundleSummary?.manifest?.version_label || bundleSummary?.version?.version_label || "-"),
                "export_ready: " + String(hasPackage),
                "upload_bundle_ready: " + String(!!uploadBundle)
              ].join("\n")}
            </div>
          </div>

          <div className="card">
            <h2>Receipt</h2>
            <div className="mono-block">
              {[
                "receipt_path: " + (artifacts.receipt || "-"),
                "receipt_sha256: " + (artifacts.receiptHash || "-"),
                "sha256sums_path: " + (artifacts.shaPath || "-"),
                "sha256sums_sha256: " + (artifacts.shaHash || "-"),
                "upload_bundle: " + (uploadBundle?.zipPath || "-"),
                "upload_bundle_sha256: " + (uploadBundle?.zipSha256 || "-")
              ].join("\n")}
            </div>
          </div>
        </section>

        <section className="panel">
          <div className="card">
            <h2>Technical log</h2>
            <pre className="console">{log || "No output yet."}</pre>
          </div>
        </section>
      </>
    );
  }

  function SettingsTab() {
    return (
      <>
        <section className="panel grid-two">
          <div className="card">
            <h2>Local paths</h2>

            <label className="field">
              <span>Repo root</span>
              <input value={repoRoot} onChange={(e) => setRepoRoot(e.target.value)} disabled={running || importing} />
            </label>

            <label className="field">
              <span>Workspace</span>
              <input value={workspace} onChange={(e) => setWorkspace(e.target.value)} disabled={running || importing} />
            </label>
          </div>

          <div className="card">
            <h2>Runtime</h2>
            <div className="mono-block">
              {[
                "mode: local",
                "public_hosting: disabled",
                "ui_dev_port: 5174",
                "local_bridge_port: 5175",
                "open_path_status: " + (openStatus || "-")
              ].join("\n")}
            </div>

            <button className="run-btn danger" onClick={() => {
              localStorage.removeItem(STORAGE_KEY);
              setLog("");
              setImportError("");
              setImportToken("");
              setBundleSummary(null);
              setOpenStatus("");
              setUploadBundle(null);
              setUploadError("");
              setActiveTab("Build");
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
          <div className="brand-subtitle">Workbench Local</div>
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
              {activeTab === "Build" && "Import a source, build a package, and prepare it for upload."}
              {activeTab === "Files" && "Open source, workspace, release, and export folders."}
              {activeTab === "Evidence" && "Review receipts, hashes, and the technical log."}
              {activeTab === "Settings" && "Local-only paths and runtime settings."}
            </p>
          </div>
        </header>

        {activeTab === "Build" && <BuildTab />}
        {activeTab === "Files" && <FilesTab />}
        {activeTab === "Evidence" && <EvidenceTab />}
        {activeTab === "Settings" && <SettingsTab />}
      </main>
    </div>
  );
}
