import { useMemo, useState } from "react";

const DEFAULT_REPO = "C:\\dev\\contract-registry";
const DEFAULT_WORKSPACE = "C:\\dev\\contract-registry\\workbench\\workspace";

function extractValue(label, text) {
  const line = text
    .split(/\r?\n/)
    .find((x) => x.startsWith(label));
  if (!line) return "";
  return line.slice(label.length).trim();
}

export default function App() {
  const [repoRoot, setRepoRoot] = useState(DEFAULT_REPO);
  const [workspace, setWorkspace] = useState(DEFAULT_WORKSPACE);
  const [running, setRunning] = useState(false);
  const [stdout, setStdout] = useState("");
  const [stderr, setStderr] = useState("");
  const [exitCode, setExitCode] = useState(null);
  const [error, setError] = useState("");

  const summary = useMemo(() => {
    return {
      latestRelease: extractValue("LATEST_RELEASE:", stdout),
      exportDir: extractValue("EVIDENCE_EXPORT_DIR:", stdout),
      exportReceipt: extractValue("EVIDENCE_EXPORT_RECEIPT:", stdout),
      exportReceiptHash: extractValue("EVIDENCE_EXPORT_RECEIPT_SHA256:", stdout),
      isGreen: stdout.includes("WORKBENCH_FULL_PIPELINE_GREEN")
    };
  }, [stdout]);

  async function runPipeline() {
    setRunning(true);
    setStdout("");
    setStderr("");
    setExitCode(null);
    setError("");

    try {
      const response = await fetch("http://localhost:5175/api/run-pipeline", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ repoRoot, workspace })
      });

      const data = await response.json();
      setStdout(data.stdout || "");
      setStderr(data.stderr || "");
      setExitCode(data.exitCode ?? null);

      if (!data.ok) {
        setError("PIPELINE_FAILED");
      }
    } catch (err) {
      setError(`REQUEST_FAILED: ${err.message}`);
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

          <button className="run-btn" onClick={runPipeline} disabled={running}>
            {running ? "Running..." : "Run Full Pipeline"}
          </button>
        </header>

        <section className="panel grid-two">
          <div className="card">
            <h2>Inputs</h2>

            <label className="field">
              <span>Repo Root</span>
              <input
                value={repoRoot}
                onChange={(e) => setRepoRoot(e.target.value)}
                disabled={running}
              />
            </label>

            <label className="field">
              <span>Workspace</span>
              <input
                value={workspace}
                onChange={(e) => setWorkspace(e.target.value)}
                disabled={running}
              />
            </label>
          </div>

          <div className="card">
            <h2>Status</h2>
            <div className="status-row">
              <span>State</span>
              <strong className={summary.isGreen ? "ok" : running ? "warn" : "muted"}>
                {summary.isGreen ? "GREEN" : running ? "RUNNING" : "IDLE"}
              </strong>
            </div>
            <div className="status-row">
              <span>Exit Code</span>
              <strong>{exitCode ?? "-"}</strong>
            </div>
            <div className="status-row">
              <span>Error</span>
              <strong>{error || "-"}</strong>
            </div>
          </div>
        </section>

        <section className="panel grid-two">
          <div className="card">
            <h2>Latest Release</h2>
            <div className="mono-block">{summary.latestRelease || "-"}</div>

            <h2>Export Directory</h2>
            <div className="mono-block">{summary.exportDir || "-"}</div>
          </div>

          <div className="card">
            <h2>Export Receipt</h2>
            <div className="mono-block">{summary.exportReceipt || "-"}</div>

            <h2>Export Receipt SHA256</h2>
            <div className="mono-block">{summary.exportReceiptHash || "-"}</div>
          </div>
        </section>

        <section className="panel grid-two">
          <div className="card">
            <h2>Stdout</h2>
            <pre className="console">{stdout || "No output yet."}</pre>
          </div>

          <div className="card">
            <h2>Stderr</h2>
            <pre className="console">{stderr || "No stderr."}</pre>
          </div>
        </section>
      </main>
    </div>
  );
}
