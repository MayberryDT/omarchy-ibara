import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The fleet's build and the words for a computer on another one. Written before the code, the ways
// it could fail:
//  1. With no computers, or none that has answered with a version, there is a fleet build, or
//     something is flagged.
//  2. Every computer on one version and no build anywhere: something is flagged, or a build shows.
//  3. One computer on another version is not flagged, or the rest are.
//  4. One on the same version but another build is not flagged, or is told another version.
//  5. A computer with no version yet counts toward the fleet build, or is flagged.
//  6. A tie depends on the order the computers come in, instead of taking the newest version.
//  7. A computer that sends no build beside ones that do, on the same version, is not flagged.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(path.join(root, 'StatusModel.js'), 'utf8').replace('.pragma library', '');
const context = {};
vm.createContext(context);
vm.runInContext(source + '\nthis.StatusModel = { fleetBuild, driftWords };', context);
const M = context.StatusModel;
const plain = value => JSON.parse(JSON.stringify(value));
const pc = (version, build) => ({ computer_id: 'c-' + Math.random().toString(36).slice(2), version, build });

test('no computers, or none with a version yet, have no fleet build and flag nothing', () => {
  assert.equal(M.fleetBuild([]), null);
  assert.equal(M.fleetBuild(null), null);
  const waiting = [pc(''), pc(undefined)];
  assert.equal(M.fleetBuild(waiting), null);
  for (const c of waiting) assert.equal(M.driftWords(c, M.fleetBuild(waiting)), '');
});

test('one version and no build anywhere flags nothing and names no build', () => {
  const fleet = [pc('0.3.6-1'), pc('0.3.6-1'), pc('0.3.6-1')];
  assert.deepEqual(plain(M.fleetBuild(fleet)), { version: '0.3.6-1', build: '' });
  for (const c of fleet) assert.equal(M.driftWords(c, M.fleetBuild(fleet)), '');
});

test('a computer on another version is flagged with the version the others run', () => {
  const odd = pc('0.3.4-1'), fleet = [pc('0.3.6-1'), odd, pc('0.3.6-1')];
  const ref = M.fleetBuild(fleet);
  assert.equal(M.driftWords(odd, ref), 'Others run ibara 0.3.6-1');
  assert.deepEqual(fleet.filter(c => c !== odd).map(c => M.driftWords(c, ref)), ['', '']);
});

test('the same version on another build is flagged as another build, not another version', () => {
  const odd = pc('0.3.6-1', '9f8e7d6'), fleet = [pc('0.3.6-1', '1a2b3c4'), pc('0.3.6-1', '1a2b3c4'), odd];
  const ref = M.fleetBuild(fleet);
  assert.deepEqual(plain(ref), { version: '0.3.6-1', build: '1a2b3c4' });
  assert.equal(M.driftWords(odd, ref), 'Others run another build of 0.3.6-1');
  assert.equal(M.driftWords(fleet[0], ref), '');
});

test('a computer with no version yet neither counts nor is flagged', () => {
  const quiet = pc(''), fleet = [quiet, pc('0.3.4-1'), pc('0.3.4-1'), pc('0.3.6-1')];
  assert.equal(M.fleetBuild(fleet).version, '0.3.4-1');
  assert.equal(M.driftWords(quiet, M.fleetBuild(fleet)), '');
});

test('a tie takes the newest version, whatever order the computers come in', () => {
  const a = [pc('0.3.4-1'), pc('0.3.6-1'), pc('0.3.6'), pc('0.3.4-1'), pc('0.3.6-1'), pc('0.3.6')];
  for (const fleet of [a, a.slice().reverse()]) assert.equal(M.fleetBuild(fleet).version, '0.3.6-1');
  const builds = [pc('0.3.6-1', 'bbbbbbb'), pc('0.3.6-1', 'aaaaaaa')];
  assert.deepEqual(plain(M.fleetBuild(builds)), plain(M.fleetBuild(builds.slice().reverse())));
});

test('no build beside computers that send one, on the same version, is another build', () => {
  const old = pc('0.3.6-1'), fleet = [pc('0.3.6-1', '1a2b3c4'), pc('0.3.6-1', '1a2b3c4'), old];
  assert.equal(M.driftWords(old, M.fleetBuild(fleet)), 'Others run another build of 0.3.6-1');
});
