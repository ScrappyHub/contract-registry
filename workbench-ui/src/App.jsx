import { useMemo, useState } from "react";

export default function App() {
  const [repoRoot, setRepoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace, setWorkspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");
  const [log, setLog] = useState("");
  const [running, setRunning] = useState(false);

  const status = useMemo(() => {
    if (running) return "RUNNING";
    if (log.includes("WORKBENCH_FULL_PIPELINE_GREEN")) return "GREEN";
    if (log.includes("PROCESS_EXIT_CODE:0")) return "DONE";
    if (log.includes("ERR:") || /PROCESS_EXIT_CODE:(?!0)\d+/.test(log)) return "FAILED";
    return "IDLE";
  }, [running, log]);

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

          <button className="run-btn" onClick={runPipeline} disabled={running}>
            {running ? "Running..." : "Run Pipeline"}
          </button>
        </header>

        <section className="panel grid-two">
          <div className="card">
            <h2>Inputs</h2>

            <label className="field">
              <span>Repo Root</span>
              <input value={repoRoot} onChange={(e) => setRepoRoot(e.target.value)} disabled={running} />
            </label>

            <label className="field">
              <span>Workspace</span>
              <input value={workspace} onChange={(e) => setWorkspace(e.target.value)} disabled={running} />
            </label>
          </div>

          <div className="card">
            <h2>Status</h2>
            <div className="status-row">
              <span>State</span>
              <strong className={status === "GREEN" ? "ok" : status === "RUNNING" ? "warn" : status === "FAILED" ? "bad" : "muted"}>
                {status}
              </strong>
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
