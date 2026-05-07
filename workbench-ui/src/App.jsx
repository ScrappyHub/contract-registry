import { useEffect, useRef, useState } from "react";

const API = "http://localhost:5185";

function friendlyFetchError(operation, err) {
  const message = err?.message || String(err || "Unknown error");

  if (message === "Failed to fetch") {
    return operation + " failed because the local bridge did not respond. Make sure npm run dev is running and the bridge says WORKBENCH_BRIDGE_READY on port 5185.";
  }

  return operation + " failed: " + message;
}

function after(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function done(step, log) {
  return log.includes("STEP_OK: " + step);
}

export default function App() {
  const [repoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");
  const [bundleFolderPath, setBundleFolderPath] = useState("C:\\dev\\contract-registry\\workbench\\workspace\\contract_bundle_unzipped");
  const [repoScanPath, setRepoScanPath] = useState("C:\\dev\\atlas-update");

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
    } catch (e) {
      setBridgeOk(false);
      setError(friendlyFetchError("Bridge check", e));
    }
  }

  function fail(message) {
    setError(message || "Something went wrong.");
    setStatus("Needs attention");
  }

  async function pickFolder() {
    const res = await fetch(API + "/api/pick-folder", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Choose Contract Registry bundle folder" })
    });

    const data = await res.json();
    if (!data.ok) throw new Error(data.error);
    return data.selectedPath;
  }

  async function importZip(file) {
    if (!file) return;

    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Importing zip...");

    try {
      const form = new FormData();
      form.append("bundle", file);
      form.append("workspace", workspace);

      const res = await fetch(API + "/api/import-zip", { method: "POST", body: form });
      const data = await res.json();

      if (!data.ok) throw new Error(data.error);

      setSource(data.summary);
      setSourcePath(file.name);
      setLog("Source imported from zip.\n");
      setStatus("Source ready");
    } catch (e) {
      fail(friendlyFetchError("Zip import", e));
    } finally {
      setBusy(false);
      if (zipRef.current) zipRef.current.value = "";
    }
  }

  async function importFolder() {
    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Importing bundle folder...");

    try {
      const res = await fetch(API + "/api/import-folder", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ folderPath: bundleFolderPath, workspace })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error);

      setSource(data.summary);
      setSourcePath(bundleFolderPath);
      setLog("Source imported from folder.\n");
      setStatus("Source ready");
    } catch (e) {
      fail(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function importAnyRepo() {
    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Scanning repo...");

    try {
      const res = await fetch(API + "/api/import-any-repo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoPath: repoScanPath, workspace })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error);

      setSource(data.summary);
      setSourcePath(repoScanPath);
      setLog("Source generated from repo scan.\n");
      setStatus("Source ready");
    } catch (e) {
      fail(friendlyFetchError("Folder import", e));
    } finally {
      setBusy(false);
    }
  }

  async function buildPackage() {
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

      while (true) {
        const item = await reader.read();
        if (item.done) break;
        setLog((prev) => prev + decoder.decode(item.value, { stream: true }));
      }

      setStatus("Package ready");
    } catch (e) {
      fail(friendlyFetchError("Build package", e));
    } finally {
      setBusy(false);
    }
  }

  async function createUploadBundle() {
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
      fail(friendlyFetchError("Create upload bundle", e));
    } finally {
      setBusy(false);
    }
  }

  async function openPath(targetPath) {
    if (!targetPath) return;

    try {
      const res = await fetch(API + "/api/open-path", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetPath })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error || "Open folder failed.");
    } catch (e) {
      fail(friendlyFetchError("Open folder", e));
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
          <p>Import a contract bundle, build it locally, then create an upload file.</p>
        </header>

        {!bridgeOk && (
          <div className="error">
            Local bridge is offline. Start the Workbench dev server and refresh.
          </div>
        )}

        {error && <div className="error">{error}</div>}

        <section className="cards">
          <div className="card">
            <div className="num">1</div>
            <h3>Choose source</h3>
            <p>Use a bundle zip, a bundle folder, or scan any local repo into a generated bundle.</p>

            <div className="buttons">
              <label className="button">
                Choose Zip
                <input ref={zipRef} type="file" accept=".zip" onChange={(e) => importZip(e.target.files?.[0])} />
              </label>
              <button onClick={importFolder} disabled={busy || !bridgeOk}>Choose Bundle Folder</button>
<button onClick={importAnyRepo} disabled={busy || !bridgeOk}>Scan Repo</button>
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

            <button className="primary" onClick={buildPackage} disabled={busy || !bridgeOk}>
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
