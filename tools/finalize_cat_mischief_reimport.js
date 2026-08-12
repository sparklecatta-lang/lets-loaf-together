const crypto = require("crypto");
const fs = require("fs");
const path = require("path");


function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) continue;
    result[key.slice(2)] = argv[i + 1];
    i += 1;
  }
  return result;
}


function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}


function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}


function isMischiefBinding(entry) {
  const metadata = entry?.metadata || entry || {};
  return metadata.profileId === "yellow_cat" && metadata.animation === "yellow_cat/mischief";
}


function clearFrameOverrides(tuning) {
  const removed = {};
  for (const section of ["frame_visual_overrides", "frame_playback_overrides", "frame_box_overrides"]) {
    const values = tuning[section] && typeof tuning[section] === "object" ? tuning[section] : {};
    const keys = Object.keys(values).filter((key) => key.startsWith("yellow_cat/mischief:"));
    keys.forEach((key) => delete values[key]);
    tuning[section] = values;
    removed[section] = keys.length;
  }
  return removed;
}


function rebuildAttachments(attachments, frameCount) {
  const old = attachments.filter(isMischiefBinding);
  if (!old.length) throw new Error("No yellow_cat/mischief attachment template found");
  const signatures = new Set(
    old.map((entry) => JSON.stringify({
      name: entry.name,
      path: entry.path,
      assetHash: entry.assetHash,
      type: entry.type,
      width: entry.width,
      height: entry.height,
      layer: entry.layer,
      layerOrder: entry.layerOrder,
      transform: entry.transform,
    }))
  );
  if (signatures.size !== 1) throw new Error(`Expected one attachment signature, found ${signatures.size}`);

  const template = old[0];
  const keyPrefix = String(template.key).replace(/:\d+$/, "");
  const rebuilt = [];
  for (let frame = 0; frame < frameCount; frame += 1) {
    const key = `${keyPrefix}:${frame}`;
    const id = `layer_${crypto.createHash("md5").update(key).digest("hex")}`;
    rebuilt.push({
      ...template,
      id,
      key,
      frameKey: key,
      metadata: {
        ...template.metadata,
        frame,
        displayFrame: frame,
      },
    });
  }
  return {
    value: attachments.filter((entry) => !isMischiefBinding(entry)).concat(rebuilt),
    oldCount: old.length,
    newCount: rebuilt.length,
  };
}


function main() {
  const args = parseArgs(process.argv.slice(2));
  const tunerRoot = path.resolve(args["tuner-root"] || "");
  const projectRoot = path.resolve(args["project-root"] || "");
  const frameCount = Number(args["frame-count"] || 0);
  const preserveAudio = String(args["preserve-audio"] || "").toLowerCase() === "true";
  if (!fs.existsSync(path.join(tunerRoot, "tools", "godot_sync.js"))) {
    throw new Error(`Invalid tuner root: ${tunerRoot}`);
  }
  if (!fs.existsSync(path.join(projectRoot, "project.godot"))) {
    throw new Error(`Invalid Godot project root: ${projectRoot}`);
  }
  if (!Number.isInteger(frameCount) || frameCount <= 0) throw new Error("Invalid --frame-count");

  const projectId = "Watercolor_Desk_Companion";
  const dataDir = path.join(tunerRoot, "data", "projects", projectId);
  const tuningPath = path.join(dataDir, "animation_tuning.json");
  const audioPath = path.join(dataDir, "frame_audio_bindings.json");
  const attachmentsPath = path.join(dataDir, "frame_image_attachments.json");

  const tuning = readJson(tuningPath);
  const removedOverrides = clearFrameOverrides(tuning);
  writeJson(tuningPath, tuning);

  const audio = readJson(audioPath);
  const matchingAudio = audio.filter(isMischiefBinding);
  const removedAudio = preserveAudio ? [] : matchingAudio;
  if (!preserveAudio) {
    writeJson(audioPath, audio.filter((entry) => !isMischiefBinding(entry)));
  }

  const attachments = readJson(attachmentsPath);
  const rebuiltAttachments = rebuildAttachments(attachments, frameCount);
  writeJson(attachmentsPath, rebuiltAttachments.value);

  const { createProjectStore } = require(path.join(tunerRoot, "tools", "project_store.js"));
  const { syncGodotProject } = require(path.join(tunerRoot, "tools", "godot_sync.js"));
  const projectStore = createProjectStore(tunerRoot);
  const project = projectStore.readRegistry().projects.find((entry) => entry.id === projectId);
  if (!project || path.resolve(project.projectRoot) !== projectRoot) {
    throw new Error(`Project binding mismatch for ${projectId}`);
  }
  const sync = syncGodotProject(tunerRoot, projectStore, project);
  if (!sync.ok) throw new Error(sync.reason || "Godot sync failed");

  console.log(JSON.stringify({
    removedOverrides,
    preservedAudioBindings: preserveAudio ? matchingAudio.length : 0,
    removedAudioBindings: removedAudio.length,
    removedAudioNames: removedAudio.map((entry) => entry.name),
    attachmentsBefore: rebuiltAttachments.oldCount,
    attachmentsAfter: rebuiltAttachments.newCount,
    sync,
  }, null, 2));
}


main();
