import { useMemo, useRef, useState } from "react";

function valueAfter(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function stepStatus(log, step) {
  if (log.includes(`STEP_OK: ${step}`)) return "done";
  if (log.includes(`STEP_START: ${step}`)) return "running";
  return "idle";
}

export default function App() {
  const [repoRoot, setRepoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace, setWorkspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");
  const [folderPath, setFolderPath] = useState("C:\\dev\\contract-registry\\workbench\\workspace\\contract_bundle_unzipped");
  const [repoImportPath, setRepoImportPath] = useState("C:\\dev\\contract-registry");
  const [log, setLog] = useState("");
  const [running, setRunning] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState("");
  const [importToken, setImportToken] = useState("");
  const [bundleSummary, setBundleSummary] = useState(null);
  const [openStatus, setOpenStatus] = useState("");

  const fileRef = useRef(null);

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

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-title">Contract Registry</div>
          <div className="brand-subtitle">Workbench v0.1.1 Local</div>
        </div>
        <nav className="nav">
          <div className="nav-item active">Pipeline</div>
          <div className="nav-item">Workspace</div>
          <div className="nav-item">Evidence</div>
          <div className="nav-item">Settings</div>
        </nav>
      </aside>

      <main className="main">
        <header className="header">
          <div>
            <h1>Workbench Pipeline</h1>
            <p>Local operator dashboard over the deterministic engine.</p>
          </div>

          <button className="run-btn" onClick={runPipeline} disabled={running || importing}>
            {running ? "Running..." : "Run Pipeline"}
          </button>
        </header>

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
        </section>

        <section className="panel">
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

        <section className="panel">
          <div className="card">
            <h2>Live Output</h2>
            <pre className="console">{log || "No output yet."}</pre>
          </div>
        </section>
      </main>
    </div>
  );
}
