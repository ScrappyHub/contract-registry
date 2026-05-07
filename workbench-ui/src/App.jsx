import { useEffect, useRef, useState } from "react";

const API = "http://localhost:5185";

function after(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function done(step, log) {
  return log.includes("STEP_OK: " + step);
}

function friendly(operation, err) {
  const msg = err?.message || String(err || "Unknown error");
  if (msg === "Failed to fetch") {
    return operation + " failed because the local bridge did not respond. Make sure npm run dev is running and the bridge is on port 5185.";
  }
  return operation + " failed: " + msg;
}

export default function App() {
  const [repoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");

  const [bundleFolderPath, setBundleFolderPath] = useState("");
  const [repoScanPath, setRepoScanPath] = useState("");

  const [bridgeOk, setBridgeOk] = useState(false);
  const [source, setSource] = useState(null);
  const [sourcePath, setSourcePath] = useState("");
  const [status, setStatus] = useState("Choose a source");
  const [error, setError] = useState("");
  const [log, setLog] = useState("");
  const [busy, setBusy] = useState(false);
  const [upload, setUpload] = useState(null);
  const [showTech, setShowTech] = useState(false);

  const zipRef = useRef(null);

  const exportDir = after("EVIDENCE_EXPORT_DIR:", log);
  const releaseDir = after("LATEST_RELEASE:", log);
  const receipt = after("EVIDENCE_EXPORT_RECEIPT:", log);
  const receiptHash = after("EVIDENCE_EXPORT_RECEIPT_SHA256:", log);
  const ready = log.includes("WORKBENCH_FULL_PIPELINE_GREEN");

  useEffect(() => {
    checkBridge();
  }, []);

  async function checkBridge() {
    try {
      const res = await fetch(API + "/api/health");
      const data = await res.json();
      setBridgeOk(!!data.ok);
      if (data.ok) setError("");
    } catch (e) {
      setBridgeOk(false);
      setError(friendly("Bridge check", e));
    }
  }

  function clearSource() {
    setSource(null);
    setSourcePath("");
    setUpload(null);
    setLog("");
  }

  function fail(message) {
    clearSource();
    setError(message || "Something went wrong.");
    setStatus("Needs attention");
  }

  function setSourceReady(data, pathText, logText) {
    setSource(data.summary);
    setSourcePath(pathText);
    setLog(logText + "\n");
    setError("");
    setStatus("Source ready");
  }

  async function importZip(file) {
    if (!file) return;

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Importing zip...");

    try {
      const form = new FormData();
      form.append("bundle", file);
      form.append("workspace", workspace);

      const res = await fetch(API + "/api/import-zip", { method: "POST", body: form });
      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, file.name, "Source imported from zip.");
    } catch (e) {
      fail(friendly("Zip import", e));
    } finally {
      setBusy(false);
      if (zipRef.current) zipRef.current.value = "";
    }
  }

  async function importFolder() {
    if (!bundleFolderPath.trim()) {
      fail("Choose Bundle Folder failed: paste a bundle folder path first.");
      return;
    }

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Importing folder...");

    try {
      const res = await fetch(API + "/api/import-folder", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ folderPath: bundleFolderPath.trim(), workspace })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, bundleFolderPath.trim(), "Source imported from folder.");
    } catch (e) {
      fail(friendly("Folder import", e));
    } finally {
      setBusy(false);
    }
  }

  async function scanRepo() {
    if (!repoScanPath.trim()) {
      fail("Scan Repo failed: paste a repo folder path first.");
      return;
    }

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Scanning repo...");

    try {
      const res = await fetch(API + "/api/import-any-repo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoPath: repoScanPath.trim(), workspace })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, repoScanPath.trim(), "Source generated from repo scan.");
    } catch (e) {
      fail(friendly("Repo scan", e));
    } finally {
      setBusy(false);
    }
  }

  async function buildPackage() {
    if (!source) {
      setError("Build Package failed: choose a source first.");
      setStatus("Needs attention");
      return;
    }

    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Building package...");
    setLog("");

    try {
      const res = await fetch(API + "/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoRoot, workspace })
      });

      if (!res.body) throw new Error("Build response stream missing.");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let full = "";

      while (true) {
        const item = await reader.read();
        if (item.done) break;
        const chunk = decoder.decode(item.value, { stream: true });
        full += chunk;
        setLog((prev) => prev + chunk);
      }

      if (full.includes("WORKBENCH_FULL_PIPELINE_GREEN")) {
        setStatus("Package ready");
      } else {
        setStatus("Needs attention");
        setError("Build finished, but the green success token was not found. Open technical details.");
      }
    } catch (e) {
      setStatus("Needs attention");
      setError(friendly("Build package", e));
    } finally {
      setBusy(false);
    }
  }

  async function createUploadBundle() {
    if (!exportDir) {
      setError("Create Upload Bundle failed: build a package first.");
      setStatus("Needs attention");
      return;
    }

    setBusy(true);
    setError("");
    setStatus("Creating upload bundle...");

    try {
      const res = await fetch(API + "/api/create-upload-bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ exportDir })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);

      setUpload(data);
      setStatus("Upload bundle ready");
    } catch (e) {
      setStatus("Needs attention");
      setError(friendly("Create upload bundle", e));
    } finally {
      setBusy(false);
    }
  }

  async function openPath(targetPath) {
    if (!targetPath) return;

    try {
      await fetch(API + "/api/open-path", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetPath })
      });
    } catch (e) {
      setError(friendly("Open folder", e));
      setStatus("Needs attention");
    }
  }

  return (
    <div className="app">
      <aside>
        <h1>Contract Registry</h1>
        <p>Workbench</p>

        <div className="side-status">
          <span>Bridge</span>
          <b className={bridgeOk ? "green" : "red"}>{bridgeOk ? "Connected" : "Offline"}</b>
        </div>

        <div className="side-status">
          <span>Status</span>
          <b>{status}</b>
        </div>
      </aside>

      <main>
        <header>
          <h2>Build Contract Package</h2>
          <p>Import a contract bundle, or scan a local repo into a generated bundle.</p>
        </header>

        {error && <div className="error">{error}</div>}

        <section className="cards">
          <div className="card">
            <div className="num">1</div>
            <h3>Choose source</h3>
            <p>Use a bundle zip, bundle folder, or scan a normal local repo.</p>

            <div className="buttons">
              <label className="button">
                Choose Zip
                <input ref={zipRef} type="file" accept=".zip" onChange={(e) => importZip(e.target.files?.[0])} />
              </label>
            </div>

            <div className="path-import">
              <label>
                <span>Bundle folder path</span>
                <input
                  value={bundleFolderPath}
                  onChange={(e) => setBundleFolderPath(e.target.value)}
                  placeholder="C:\path\to\contract_bundle_v1"
                />
              </label>
              <button onClick={importFolder} disabled={busy || !bridgeOk}>Import Bundle Folder</button>
            </div>

            <div className="path-import">
              <label>
                <span>Repo folder path</span>
                <input
                  value={repoScanPath}
                  onChange={(e) => setRepoScanPath(e.target.value)}
                  placeholder="C:\path\to\repo"
                />
              </label>
              <button onClick={scanRepo} disabled={busy || !bridgeOk}>Scan Repo</button>
            </div>

            <div className={source ? "notice good" : "notice"}>
              {source ? (
                <>
                  <b>Source ready</b>
                  <span>{source.contractKey} / {source.versionLabel}</span>
                  <small>{sourcePath}</small>
                </>
              ) : (
                "No source selected yet."
              )}
            </div>
          </div>

          <div className="card">
            <div className="num">2</div>
            <h3>Build package</h3>
            <p>Runs inspect, build, verify, and export using the local engine.</p>

            <button className="primary" onClick={buildPackage} disabled={busy || !bridgeOk || !source}>
              {busy ? "Working..." : "Build Package"}
            </button>

            <div className="steps">
              <span className={done("inspect", log) ? "done" : ""}>Inspect</span>
              <span className={done("build", log) ? "done" : ""}>Build</span>
              <span className={done("verify", log) ? "done" : ""}>Verify</span>
              <span className={done("export", log) ? "done" : ""}>Export</span>
            </div>
          </div>

          <div className="card">
            <div className="num">3</div>
            <h3>Review result</h3>

            {ready ? (
              <>
                <div className="notice good">
                  <b>Package created</b>
                  <span>Ready for review or upload packaging.</span>
                </div>

                <button onClick={() => openPath(exportDir)}>Open Export Folder</button>
                <button onClick={createUploadBundle} disabled={busy}>Create Upload Bundle</button>

                {upload && (
                  <div className="notice good">
                    <b>Upload bundle ready</b>
                    <small>{upload.zipPath}</small>
                    <small>{upload.zipSha256}</small>
                  </div>
                )}
              </>
            ) : (
              <div className="notice">Build the package to see the result.</div>
            )}
          </div>
        </section>

        <section className="advanced">
          <button onClick={() => setShowTech(!showTech)}>
            {showTech ? "Hide technical details" : "Show technical details"}
          </button>

          {showTech && (
            <div className="details">
              <h3>Evidence</h3>
              <code>Release: {releaseDir || "-"}</code>
              <code>Export: {exportDir || "-"}</code>
              <code>Receipt: {receipt || "-"}</code>
              <code>Receipt SHA-256: {receiptHash || "-"}</code>

              <h3>Log</h3>
              <pre>{log || "No log yet."}</pre>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}