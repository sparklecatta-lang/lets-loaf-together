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


function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}


function isAnimationKey(key, qualifiedAnimation) {
  const text = String(key || "");
  return text === qualifiedAnimation
    || text.startsWith(`${qualifiedAnimation}:`)
    || text.startsWith(`${qualifiedAnimation}/`);
}


function isAnimationBinding(entry, profileId, qualifiedAnimation) {
  const metadata = entry?.metadata || {};
  const entryProfile = String(entry?.profileId || metadata.profileId || "");
  const entryAnimation = String(entry?.animation || metadata.animation || "");
  return (entryProfile === profileId && entryAnimation === qualifiedAnimation)
    || isAnimationKey(entry?.key, qualifiedAnimation)
    || isAnimationKey(entry?.frameKey, qualifiedAnimation);
}


const args = parseArgs(process.argv.slice(2));
const tunerRoot = path.resolve(String(args["tuner-root"] || ""));
const projectId = String(args.project || "");
const expectedProjectRoot = path.resolve(String(args["project-root"] || ""));
const profileId = String(args.profile || "");
const animationId = String(args.animation || "");

if (!tunerRoot || !fs.existsSync(tunerRoot)) throw new Error(`Tuner root not found: ${tunerRoot}`);
if (!expectedProjectRoot || !fs.existsSync(expectedProjectRoot)) {
  throw new Error(`Project root not found: ${expectedProjectRoot}`);
}
if (!projectId || !profileId || !animationId) {
  throw new Error("Required: --project, --profile, and --animation");
}

const { createProjectStore } = require(path.join(tunerRoot, "tools", "project_store.js"));
const { syncGodotProject } = require(path.join(tunerRoot, "tools", "godot_sync.js"));
const projectStore = createProjectStore(tunerRoot);
const project = projectStore.activeProject(projectId);
if (!project || project.id !== projectId) throw new Error(`Project not found: ${projectId}`);
if (!samePath(project.projectRoot, expectedProjectRoot)) {
  throw new Error(`Project root mismatch: registry=${project.projectRoot} expected=${expectedProjectRoot}`);
}

const qualifiedAnimation = `${profileId}/${animationId}`;
const projectPaths = projectStore.projectPaths(project);
const manifest = projectStore.readJson(projectPaths.manifest, { schemaVersion: 1, profiles: [] });
const tuning = projectStore.readJson(projectPaths.tuning, {});
const audioBindings = projectStore.readJson(projectPaths.frameAudio, []);
if (!Array.isArray(audioBindings)) throw new Error("frame_audio_bindings.json must be an array");

const clearedTuning = {};
for (const storeName of ["frame_visual_overrides", "frame_playback_overrides", "frame_box_overrides"]) {
  const store = tuning[storeName] && typeof tuning[storeName] === "object" ? tuning[storeName] : {};
  let removed = 0;
  for (const key of Object.keys(store)) {
    if (!isAnimationKey(key, qualifiedAnimation)) continue;
    delete store[key];
    removed += 1;
  }
  tuning[storeName] = store;
  clearedTuning[storeName] = removed;
}

const nextAudioBindings = audioBindings.filter(
  (entry) => !isAnimationBinding(entry, profileId, qualifiedAnimation)
);
const removedAudioBindings = audioBindings.length - nextAudioBindings.length;

projectStore.writeJson(projectPaths.tuning, tuning);
projectStore.writeJson(projectPaths.frameAudio, nextAudioBindings);
const syncResult = syncGodotProject(tunerRoot, projectStore, project, {
  manifest,
  tuning,
  frameAudioBindings: nextAudioBindings,
});
if (!syncResult.ok) throw new Error(syncResult.reason || "Godot sync failed");

const profile = (manifest.profiles || []).find((entry) => entry.id === profileId);
const animation = (profile?.animations || []).find((entry) => entry.id === animationId);
if (!animation) throw new Error(`Animation not found in manifest: ${qualifiedAnimation}`);
const gameAnimationDir = path.resolve(
  expectedProjectRoot,
  "xsxb_frame_tuner",
  "workspace",
  "projects",
  projectId,
  "assets",
  profileId,
  animationId
);
const expectedGameAnimationDir = path.resolve(
  expectedProjectRoot,
  "xsxb_frame_tuner",
  "workspace",
  "projects",
  projectId,
  "assets",
  profileId,
  animationId
);
if (!samePath(gameAnimationDir, expectedGameAnimationDir) || !fs.existsSync(gameAnimationDir)) {
  throw new Error(`Refusing to prune unexpected animation directory: ${gameAnimationDir}`);
}
const manifestFrameNames = new Set(
  (animation.frames || []).map((frame) => path.basename(String(frame.path || "")))
);
const removedStaleFrameFiles = [];
for (const entry of fs.readdirSync(gameAnimationDir, { withFileTypes: true })) {
  if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".png") continue;
  if (manifestFrameNames.has(entry.name)) continue;
  const target = path.resolve(gameAnimationDir, entry.name);
  if (path.dirname(target).toLowerCase() !== gameAnimationDir.toLowerCase()) {
    throw new Error(`Refusing to delete outside animation directory: ${target}`);
  }
  fs.rmSync(target);
  removedStaleFrameFiles.push(target);
  const sidecar = `${target}.import`;
  if (fs.existsSync(sidecar)) {
    fs.rmSync(sidecar);
    removedStaleFrameFiles.push(sidecar);
  }
}

const audioDir = path.resolve(
  expectedProjectRoot,
  "xsxb_frame_tuner",
  "audio",
  "projects",
  projectId
);
const profileToken = profileId.toLowerCase().replace(/[^a-z0-9]+/g, "_");
const animationToken = animationId.toLowerCase().replace(/[^a-z0-9]+/g, "_");
const removedAudioFiles = [];
if (fs.existsSync(audioDir)) {
  for (const entry of fs.readdirSync(audioDir, { withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const lowerName = entry.name.toLowerCase();
    if (!lowerName.includes(profileToken) || !lowerName.includes(animationToken)) continue;
    const target = path.resolve(audioDir, entry.name);
    if (path.dirname(target).toLowerCase() !== audioDir.toLowerCase()) {
      throw new Error(`Refusing to delete outside animation audio directory: ${target}`);
    }
    fs.rmSync(target);
    removedAudioFiles.push(target);
  }
}

console.log(JSON.stringify({
  ok: true,
  project: projectId,
  projectRoot: project.projectRoot,
  animation: qualifiedAnimation,
  clearedTuning,
  removedAudioBindings,
  removedAudioFiles,
  removedStaleFrameFiles,
  attachmentBindingsChanged: false,
  sync: syncResult,
}, null, 2));
