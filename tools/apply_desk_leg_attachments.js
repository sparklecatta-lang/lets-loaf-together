const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");


function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const value = argv[index + 1];
    if (value && !value.startsWith("--")) {
      result[key] = value;
      index += 1;
    } else {
      result[key] = true;
    }
  }
  return result;
}


function normalize(value) {
  return String(value || "").replaceAll("\\", "/");
}


function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}


function frameIdentity(entry) {
  const metadata = entry?.metadata || {};
  return `${metadata.animation || ""}:${Number(metadata.frame)}`;
}


function deterministicLayerId(frameKey, assetHash) {
  const digest = crypto.createHash("sha256").update(`${assetHash}|${frameKey}`).digest("hex").slice(0, 32);
  return `layer_${digest}`;
}


function standaloneFrameKey(projectId, profile, animation, frameIndex, template) {
  const metadata = template.metadata || {};
  const tuningTarget = String(metadata.tuningTarget || "player");
  const groupType = String(animation.type || profile.kind || "actor");
  const qualifiedAnimation = `${profile.id}/${animation.id}`;
  return [
    projectId,
    tuningTarget,
    profile.id,
    groupType,
    qualifiedAnimation,
    normalize(animation.source),
    frameIndex,
  ].join(":");
}


function isDeskAnimation(profileId, animationId) {
  return profileId === "desk_girl" || (profileId === "yellow_cat" && animationId === "mischief");
}


const args = parseArgs(process.argv.slice(2));
const tunerRoot = path.resolve(String(args["tuner-root"] || ""));
const projectId = String(args.project || "Watercolor_Desk_Companion");
const expectedProjectRoot = path.resolve(String(args["project-root"] || ""));

if (!tunerRoot || !fs.existsSync(tunerRoot)) throw new Error(`Tuner root not found: ${tunerRoot}`);
if (!expectedProjectRoot || !fs.existsSync(expectedProjectRoot)) {
  throw new Error(`Project root not found: ${expectedProjectRoot}`);
}

const { createProjectStore } = require(path.join(tunerRoot, "tools", "project_store.js"));
const { syncGodotProject } = require(path.join(tunerRoot, "tools", "godot_sync.js"));
const projectStore = createProjectStore(tunerRoot);
const project = projectStore.activeProject(projectId);

if (!project || project.id !== projectId) throw new Error(`Project not found: ${projectId}`);
if (!samePath(project.projectRoot, expectedProjectRoot)) {
  throw new Error(`Project root mismatch: registry=${project.projectRoot} expected=${expectedProjectRoot}`);
}

const projectPaths = projectStore.projectPaths(project);
const manifest = projectStore.readJson(projectPaths.manifest, { schemaVersion: 1, profiles: [] });
const existingAttachments = projectStore.readJson(projectPaths.frameImageAttachments, []);
if (!Array.isArray(existingAttachments)) throw new Error("frame_image_attachments.json must be an array");

const templateCandidates = existingAttachments.filter((entry) => {
  const metadata = entry?.metadata || {};
  return metadata.animation === "desk_girl/leave"
    && Number(metadata.frame) === 27
    && entry.layer === "below";
});
if (templateCandidates.length !== 1) {
  throw new Error(`Expected exactly one below-layer attachment on desk_girl/leave frame 27, found ${templateCandidates.length}`);
}

const template = templateCandidates[0];
const assetHash = String(template.assetHash || "");
if (!assetHash) throw new Error("Desk-leg template has no assetHash");
const sourceImage = path.resolve(tunerRoot, String(template.path || ""));
if (!fs.existsSync(sourceImage)) throw new Error(`Desk-leg image not found: ${sourceImage}`);

const existingLegByFrame = new Map();
for (const entry of existingAttachments) {
  if (String(entry?.assetHash || "") !== assetHash) continue;
  const identity = frameIdentity(entry);
  if (!existingLegByFrame.has(identity)) existingLegByFrame.set(identity, entry);
}

const deskFrames = [];
for (const profile of manifest.profiles || []) {
  for (const animation of profile.animations || []) {
    if (!isDeskAnimation(profile.id, animation.id)) continue;
    const qualifiedAnimation = `${profile.id}/${animation.id}`;
    const frames = Array.isArray(animation.frames) ? animation.frames : [];
    for (let frameIndex = 0; frameIndex < frames.length; frameIndex += 1) {
      deskFrames.push({ profile, animation, qualifiedAnimation, frameIndex });
    }
  }
}

const preservedAttachments = existingAttachments.filter((entry) => String(entry?.assetHash || "") !== assetHash);
const legAttachments = deskFrames.map(({ profile, animation, qualifiedAnimation, frameIndex }) => {
  const identity = `${qualifiedAnimation}:${frameIndex}`;
  const existing = existingLegByFrame.get(identity);
  const frameKey = standaloneFrameKey(projectId, profile, animation, frameIndex, template);
  const metadata = {
    ...(template.metadata || {}),
    projectId,
    profileId: profile.id,
    groupType: String(animation.type || profile.kind || "actor"),
    animation: qualifiedAnimation,
    source: normalize(animation.source),
    frame: frameIndex,
    displayFrame: frameIndex,
  };
  return {
    ...template,
    id: existing?.id || deterministicLayerId(frameKey, assetHash),
    key: frameKey,
    frameKey,
    metadata,
    transform: JSON.parse(JSON.stringify(template.transform || {})),
  };
});

const nextAttachments = [...preservedAttachments, ...legAttachments];
const timestamp = new Date().toISOString().replaceAll(":", "-").replaceAll(".", "-");
const backupPath = `${projectPaths.frameImageAttachments}.before-desk-leg-${timestamp}.json`;
fs.copyFileSync(projectPaths.frameImageAttachments, backupPath);
projectStore.writeJson(projectPaths.frameImageAttachments, nextAttachments);

const syncResult = syncGodotProject(tunerRoot, projectStore, project, {
  manifest,
  frameImageAttachments: nextAttachments,
});
if (!syncResult.ok) throw new Error(syncResult.reason || "Godot sync failed");

const report = {
  ok: true,
  project: projectId,
  projectRoot: project.projectRoot,
  template: {
    identity: frameIdentity(template),
    assetHash,
    width: template.width,
    height: template.height,
    layer: template.layer,
    layerOrder: template.layerOrder,
    transform: template.transform,
  },
  deskFrameCount: deskFrames.length,
  preservedUnrelatedAttachmentCount: preservedAttachments.length,
  totalAttachmentCount: nextAttachments.length,
  standaloneAttachmentFile: projectPaths.frameImageAttachments,
  gameAttachmentFile: path.join(project.projectRoot, "xsxb_frame_tuner", "data", "projects", projectId, "frame_image_attachments.json"),
  backupPath,
  sync: syncResult,
};
console.log(JSON.stringify(report, null, 2));
