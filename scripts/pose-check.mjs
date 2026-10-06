// M2 check for the "bent legs after sitting" bug: after any task pose (sit, lie, cook, scrub) and the
// blend back to standing, every leg joint must equal the idle pose. Plain node (Node 22+, type stripping):
//   node scripts/pose-check.mjs        Exits 1 on any failure.
import { register } from 'node:module';

register(
  'data:text/javascript,' +
    encodeURIComponent(`
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && !/\\.[cm]?[jt]sx?$/.test(spec)) {
    try { return await next(spec + '.ts', ctx); } catch {}
  }
  return next(spec, ctx);
}`),
  import.meta.url,
);

const body = await import('../src/art/avatar3d/engine/body.ts');
const anim = await import('../src/art/avatar3d/engine/anim.ts');
const poses = await import('../src/art/home3d/engine/poses.ts');

let fails = 0;
const ok = (cond, msg) => {
  if (cond) console.log('  ok  ' + msg);
  else {
    fails++;
    console.log('  FAIL ' + msg);
  }
};

/** A bare rig with the Character fields the poses use (no meshes, no textures). */
function rigChar(gender, build, stride = 1) {
  const dims = body.makeDims(gender, build);
  const rig = body.makeRig(dims);
  return { root: rig.root, rig, dims, stride, longHair: false };
}

const TASKS = {
  sit: (c, t) => poses.poseSit(c, t, 0.3),
  lie: (c, t) => poses.poseLie(c, t),
  cook: (c, t) => poses.poseCook(c, t, 0.3),
  scrub: (c, t) => poses.poseScrub(c, t, 0.3),
};
const BLEND_S = 0.42;
const legs = (c) => anim.LEG_BONES.map((n) => c.rig[n].rotation.toArray().slice(0, 3).map((v) => +v.toFixed(3)).join(',')).join(' | ');

for (const [gender, build, stride] of [['male', 'average', 1], ['female', 'curvy', 0.38], ['male', 'slim', 0.75]]) {
  console.log(`${gender} ${build} stride ${stride}`);
  for (const [name, pose] of Object.entries(TASKS)) {
    const c = rigChar(gender, build, stride);
    const life = { tired: 0.4, happy: 0, idleFor: 0 };
    // 1. the HomeScene sequence: task pose frames, then the stand-up blend (prev pose -> idle), then idle
    let t = 10;
    const prev = new Float32Array(anim.POSE_SIZE);
    const cur = new Float32Array(anim.POSE_SIZE);
    for (let i = 0; i < 30; i++, t += 1 / 30) {
      anim.resetRig(c);
      pose(c, t);
      anim.capturePose(c, prev);
    }
    const from = prev.slice();
    let u = 0;
    for (; u < 1; t += 1 / 30) {
      u = Math.min(1, (u * BLEND_S + 1 / 30) / BLEND_S);
      anim.poseLife(c, t, 0.3, life);
      anim.capturePose(c, cur);
      const e = u * u * (3 - 2 * u);
      anim.applyPose(c, anim.mixPose(cur, from, cur, e));
    }
    anim.poseLife(c, t, 0.3, life);
    const after = anim.capturePose(c);
    const fresh = rigChar(gender, build, stride);
    anim.poseLife(fresh, t, 0.3, life);
    const idle = anim.capturePose(fresh);
    const d1 = anim.legRotationDiff(after, idle);
    ok(d1 < 1e-6, `${name}: legs back to idle after the blend (max diff ${d1.toExponential(1)} rad)`);
    // 2. the root cause: a task pose followed by a plain restPose-based pose (the turntable idle, the
    //    pre-M1 home idle) must not keep the knees bent
    pose(c, t);
    anim.poseIdle(c, t, 0.3);
    const legacy = anim.capturePose(c);
    const freshIdle = rigChar(gender, build, stride);
    anim.poseIdle(freshIdle, t, 0.3);
    const d2 = anim.legRotationDiff(legacy, anim.capturePose(freshIdle));
    ok(d2 < 1e-6, `${name}: poseIdle straight after the task pose (max diff ${d2.toExponential(1)} rad) ${d2 >= 1e-6 ? legs(c) : ''}`);
    // 3. walking off after the task: the gait is the same as from a fresh rig
    anim.poseGait(c, 0.37, 1, { strideScale: 1.2 });
    const g1 = anim.capturePose(c);
    anim.poseGait(fresh, 0.37, 1, { strideScale: 1.2 });
    const d3 = anim.legRotationDiff(g1, anim.capturePose(fresh));
    ok(d3 < 1e-6, `${name}: walk cycle unaffected (max diff ${d3.toExponential(1)} rad)`);
  }
}

// M2 walk speed: stride and cadence scale with speed; robes slower but quicker steps
console.log('walk tuning');
{
  const trousers = rigChar('male', 'average', 1);
  const robe = rigChar('male', 'average', 0.38);
  const g = anim.gaitFor(trousers, { speed: 1.9, robeMult: 0.7 });
  const r = anim.gaitFor(robe, { speed: 1.9, robeMult: 0.7 });
  const cad = (c, gt) => gt.cruise / anim.stepLength(c, 1, gt.strideScale);
  ok(Math.abs(g.cruise - 1.9) < 1e-9, `trousers cruise ${g.cruise} m/s`);
  ok(Math.abs(r.cruise - 1.33) < 1e-6, `robe cruise ${r.cruise.toFixed(2)} m/s (was 0.72 in M1)`);
  ok(g.strideScale > 1 && cad(trousers, g) > 2 && cad(trousers, g) < 2.6, `trousers: stride x${g.strideScale.toFixed(2)}, ${cad(trousers, g).toFixed(2)} steps/s`);
  ok(cad(robe, r) > cad(trousers, g), `robe: short quick steps (${cad(robe, r).toFixed(2)} steps/s, stride x${r.strideScale.toFixed(2)})`);
  const slow = anim.gaitFor(trousers, { speed: 1.15, robeMult: 0.7 });
  ok(anim.stepLength(trousers, 1, slow.strideScale) < anim.stepLength(trousers, 1, g.strideScale), 'faster walk = longer stride');
}

if (fails) {
  console.log(`\n${fails} failed`);
  process.exit(1);
}
console.log('\nall pose checks passed');
