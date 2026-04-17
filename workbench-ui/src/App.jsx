import { useMemo, useRef, useState } from "react";

export default function App() {
  const [repoRoot, setRepoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace, setWorkspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");
  const [log, setLog] = useState("");
  const [running, setRunning] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState("");
  const [importToken, setImportToken] = useState("");
  const [bundleSummary, setBundleSummary] = useState(null);

  const fileRef = useRef(null);

  const status = useMemo(() => {
    if (running) return "RUNNING";
    if (log.includes("WORKBENCH_FULL_PIPELINE_GREEN")) return "GREEN";
    if (log.includes("PROCESS_EXIT_CODE:0")) return "DONE";
    if (log.includes("ERR:") || /PROCESS_EXIT_CODE:(?!0)\d+/.test(log)) return "FAILED";
    return "IDLE";
  }, [running, log]);

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

      setImportToken(data.token || "WORKBENCH_IMPORT_OK");
      setBundleSummary(data.summary || null);
    } catch (err) {
      setImportError("IMPORT_REQUEST_FAILED: " + err.message);
    } finally {
      setImporting(false);
      if (fileRef.current) {
        fileRef.current.value = "";
      }
    }
  }

  async function runPipeline() {
    setLog("");
    setRunning(true);

    try {
      const response = await fetch("http://localhost:5175/run", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
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
        const chunk = decoder.decode(value, { stream: true });
        setLog((prev) => prev + chunk);
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
          <div className="brand-subtitle">Workbench v0.1.0</div>
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
            <p>Thin local wrapper over the deterministic engine.</p>
          </div>

          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <label className="run-btn" style={{ display: "inline-flex", alignItems: "center" }}>
              {importing ? "Importing..." : "Import Bundle"}
              <input
                ref={fileRef}
                type="file"
                accept=".zip"
                style={{ display: "none" }}
                disabled={importing || running}
                onChange={(e) => importBundle(e.target.files?.[0] || null)}
              />
            </label>

            <button className="run-btn" onClick={runPipeline} disabled={running}>
              {running ? "Running..." : "Run Pipeline"}
            </button>
          </div>
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
              <strong className={status === "GREEN" ? "ok" : status === "RUNNING" ? "warn" : status === "FAILED" ? "bad" : "muted"}>
                {status}
              </strong>
            </div>
            <div className="status-row">
              <span>Import Token</span>
              <strong className={importToken ? "ok" : "muted"}>{importToken || "-"}</strong>
            </div>
            <div className="status-row">
              <span>Import Error</span>
              <strong className={importError ? "bad" : "muted"}>{importError || "-"}</strong>
            </div>
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
