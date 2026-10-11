// Firestore security-rule tests. Run with: cd firebase && npm test
import { test, before, beforeEach, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, query, where, Timestamp,
} from 'firebase/firestore';

let env;
const FID = 'fam1';
const inFuture = () => Timestamp.fromMillis(Date.now() + 7 * 86_400_000);
const inPast = () => Timestamp.fromMillis(Date.now() - 1000);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-curbside',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env.cleanup());

const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

/** Family with parent "mom", sharing teen "teen1", non-sharing teen "teen2", and invites. */
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `families/${FID}`), { name: 'Fam', createdBy: 'mom' });
    await setDoc(doc(d, `families/${FID}/members/mom`), { role: 'parent', displayName: 'Mom', sharing: true });
    await setDoc(doc(d, `families/${FID}/members/teen1`), {
      role: 'teen', displayName: 'Riley', sharing: true, inviteCode: 'TEENCODE', standing: { score: 700 },
    });
    await setDoc(doc(d, `families/${FID}/members/teen2`), { role: 'teen', displayName: 'Sam', sharing: false, inviteCode: 'TEENCODE' });
    await setDoc(doc(d, `families/${FID}/members/teen1/drives/d1`), { score: 90 });
    await setDoc(doc(d, 'inviteCodes/TEENCODE'), { familyID: FID, role: 'teen', createdBy: 'mom', expiresAt: inFuture() });
    await setDoc(doc(d, 'inviteCodes/OLDCODE1'), { familyID: FID, role: 'teen', createdBy: 'mom', expiresAt: inPast() });
    await setDoc(doc(d, 'inviteCodes/PARENTCD'), { familyID: FID, role: 'parent', createdBy: 'mom', expiresAt: inFuture() });
    await setDoc(doc(d, `families/${FID}/rewards/r1`), {
      teenID: 'teen1', createdBy: 'mom', goal: { kind: 'hold', minScore: 750, weeks: 4 }, prize: { kind: 'money', dollars: 20 },
    });
    await setDoc(doc(d, `families/${FID}/rewards/r2`), {
      teenID: 'teen2', createdBy: 'mom', goal: { kind: 'reach', minScore: 700 }, prize: { kind: 'custom', text: 'Pizza' },
    });
  });
});

// ── Outsiders ────────────────────────────────────────────────────────────

test('outsiders and signed-out users cannot read a family', async () => {
  await assertFails(getDoc(doc(db('stranger'), `families/${FID}`)));
  await assertFails(getDocs(collection(db('stranger'), `families/${FID}/members`)));
  await assertFails(getDoc(doc(db('stranger'), `families/${FID}/members/teen1/drives/d1`)));
  await assertFails(getDoc(doc(anon(), `families/${FID}`)));
});

test('profiles are private to their owner', async () => {
  await assertSucceeds(setDoc(doc(db('teen1'), 'users/teen1'), { displayName: 'Riley' }));
  await assertFails(getDoc(doc(db('mom'), 'users/teen1')));
});

// ── Creating families and invites ────────────────────────────────────────

test('a parent can create a family and join it as its first parent', async () => {
  const d = db('dad');
  await assertSucceeds(setDoc(doc(d, 'families/fam2'), { name: 'Other', createdBy: 'dad' }));
  await assertSucceeds(setDoc(doc(d, 'families/fam2/members/dad'), { role: 'parent', displayName: 'Dad', sharing: false }));
});

test('you cannot create a family in someone else\'s name or self-join as parent', async () => {
  await assertFails(setDoc(doc(db('dad'), 'families/fam3'), { name: 'X', createdBy: 'mom' }));
  await assertFails(setDoc(doc(db('dad'), `families/${FID}/members/dad`), { role: 'parent', displayName: 'Dad', sharing: false }));
});

test('only parents create invites, and codes cannot be listed', async () => {
  await assertSucceeds(setDoc(doc(db('mom'), 'inviteCodes/NEWCODE2'),
    { familyID: FID, role: 'teen', createdBy: 'mom', expiresAt: inFuture() }));
  await assertFails(setDoc(doc(db('teen1'), 'inviteCodes/NEWCODE3'),
    { familyID: FID, role: 'teen', createdBy: 'teen1', expiresAt: inFuture() }));
  await assertSucceeds(getDoc(doc(db('stranger'), 'inviteCodes/TEENCODE')));
  await assertFails(getDocs(collection(db('stranger'), 'inviteCodes')));
});

// ── Joining ──────────────────────────────────────────────────────────────

test('a teen joins with a valid code', async () => {
  await assertSucceeds(setDoc(doc(db('teen3'), `families/${FID}/members/teen3`),
    { role: 'teen', displayName: 'Kai', sharing: false, inviteCode: 'TEENCODE' }));
});

test('joining fails with an expired code, no code, or the wrong role', async () => {
  const member = (code, role = 'teen') => ({ role, displayName: 'Kai', sharing: false, inviteCode: code });
  await assertFails(setDoc(doc(db('teen3'), `families/${FID}/members/teen3`), member('OLDCODE1')));
  await assertFails(setDoc(doc(db('teen3'), `families/${FID}/members/teen3`), member('NOPECODE')));
  await assertFails(setDoc(doc(db('teen3'), `families/${FID}/members/teen3`), member('TEENCODE', 'parent')));
  await assertSucceeds(setDoc(doc(db('dad'), `families/${FID}/members/dad`), member('PARENTCD', 'parent')));
});

test('you cannot add someone else as a member', async () => {
  await assertFails(setDoc(doc(db('teen1'), `families/${FID}/members/teen9`),
    { role: 'teen', displayName: 'X', sharing: false, inviteCode: 'TEENCODE' }));
});

// ── Consent ──────────────────────────────────────────────────────────────

test('a score can only be published while sharing is on', async () => {
  const teen2 = doc(db('teen2'), `families/${FID}/members/teen2`);
  await assertFails(updateDoc(teen2, { standing: { score: 650 } }));
  await assertSucceeds(updateDoc(teen2, { sharing: true, standing: { score: 650 } }));
  // Turning sharing off must clear the score in the same write.
  await assertFails(updateDoc(teen2, { sharing: false }));
  await assertSucceeds(updateDoc(teen2, { sharing: false, standing: null }));
});

test('drives can only be uploaded while sharing is on', async () => {
  await assertFails(setDoc(doc(db('teen2'), `families/${FID}/members/teen2/drives/x`), { score: 80 }));
  await assertSucceeds(setDoc(doc(db('teen1'), `families/${FID}/members/teen1/drives/x`), { score: 80 }));
});

test('nobody can change their role', async () => {
  await assertFails(updateDoc(doc(db('teen1'), `families/${FID}/members/teen1`), { role: 'parent' }));
});

// ── Who sees what ────────────────────────────────────────────────────────

test('parents see a sharing teen\'s drives', async () => {
  await assertSucceeds(getDoc(doc(db('mom'), `families/${FID}/members/teen1/drives/d1`)));
  await assertSucceeds(getDocs(collection(db('mom'), `families/${FID}/members/teen1/drives`)));
});

test('parents lose access to drives the moment a teen pauses sharing', async () => {
  await env.withSecurityRulesDisabled(async (ctx) =>
    updateDoc(doc(ctx.firestore(), `families/${FID}/members/teen1`), { sharing: false, standing: null }));
  await assertFails(getDoc(doc(db('mom'), `families/${FID}/members/teen1/drives/d1`)));
});

test('teens see the leaderboard but never another member\'s drives', async () => {
  await assertSucceeds(getDocs(collection(db('teen2'), `families/${FID}/members`)));
  await assertFails(getDoc(doc(db('teen2'), `families/${FID}/members/teen1/drives/d1`)));
  await assertFails(getDocs(collection(db('teen2'), `families/${FID}/members/teen1/drives`)));
});

test('teens can read their own drives and delete them', async () => {
  await assertSucceeds(getDoc(doc(db('teen1'), `families/${FID}/members/teen1/drives/d1`)));
  await assertSucceeds(deleteDoc(doc(db('teen1'), `families/${FID}/members/teen1/drives/d1`)));
});

test('teens cannot edit other members or the family', async () => {
  await assertFails(updateDoc(doc(db('teen1'), `families/${FID}/members/teen2`), { displayName: 'X' }));
  await assertFails(updateDoc(doc(db('teen1'), `families/${FID}`), { name: 'Hacked' }));
  await assertFails(deleteDoc(doc(db('teen1'), `families/${FID}/members/mom`)));
});

test('a parent can remove a teen and their shared drives; a teen can leave', async () => {
  await assertSucceeds(deleteDoc(doc(db('mom'), `families/${FID}/members/teen1/drives/d1`)));
  await assertSucceeds(deleteDoc(doc(db('mom'), `families/${FID}/members/teen1`)));
  await assertSucceeds(deleteDoc(doc(db('teen2'), `families/${FID}/members/teen2`)));
});

// ── Rewards ──────────────────────────────────────────────────────────────

const newReward = (extra = {}) => ({
  teenID: 'teen1', createdBy: 'mom', goal: { kind: 'reach', minScore: 760 }, prize: { kind: 'money', dollars: 10 }, ...extra,
});

test('parents create rewards for teens, not for parents, and not with progress pre-filled', async () => {
  await assertSucceeds(setDoc(doc(db('mom'), `families/${FID}/rewards/n1`), newReward()));
  await assertFails(setDoc(doc(db('mom'), `families/${FID}/rewards/n2`), newReward({ teenID: 'mom' })));
  await assertFails(setDoc(doc(db('mom'), `families/${FID}/rewards/n3`), newReward({ progress: { earnedAt: 1 } })));
  await assertFails(setDoc(doc(db('mom'), `families/${FID}/rewards/n4`), newReward({ createdBy: 'dad' })));
});

test('teens cannot create, edit, or delete rewards', async () => {
  await assertFails(setDoc(doc(db('teen1'), `families/${FID}/rewards/n5`), newReward({ createdBy: 'teen1' })));
  await assertFails(updateDoc(doc(db('teen1'), `families/${FID}/rewards/r1`), { prize: { kind: 'money', dollars: 500 } }));
  await assertFails(updateDoc(doc(db('teen1'), `families/${FID}/rewards/r1`), { givenAt: 1 }));
  await assertFails(deleteDoc(doc(db('teen1'), `families/${FID}/rewards/r1`)));
});

test('only the teen, while sharing, writes progress', async () => {
  await assertSucceeds(updateDoc(doc(db('teen1'), `families/${FID}/rewards/r1`), { progress: { currentScore: 752 } }));
  await assertFails(updateDoc(doc(db('mom'), `families/${FID}/rewards/r1`), { progress: { earnedAt: 1 } }));
  // teen2 isn't sharing.
  await assertFails(updateDoc(doc(db('teen2'), `families/${FID}/rewards/r2`), { progress: { currentScore: 702 } }));
});

test('teens see only their own rewards; parents see all', async () => {
  await assertSucceeds(getDoc(doc(db('teen1'), `families/${FID}/rewards/r1`)));
  await assertFails(getDoc(doc(db('teen1'), `families/${FID}/rewards/r2`)));
  await assertSucceeds(getDocs(query(collection(db('teen1'), `families/${FID}/rewards`), where('teenID', '==', 'teen1'))));
  await assertFails(getDocs(collection(db('teen1'), `families/${FID}/rewards`)));
  await assertSucceeds(getDocs(collection(db('mom'), `families/${FID}/rewards`)));
  await assertFails(getDoc(doc(db('stranger'), `families/${FID}/rewards/r1`)));
});

test('parents mark rewards given and can delete them', async () => {
  await assertSucceeds(updateDoc(doc(db('mom'), `families/${FID}/rewards/r1`), { givenAt: 1 }));
  await assertFails(updateDoc(doc(db('mom'), `families/${FID}/rewards/r1`), { teenID: 'teen2' }));
  await assertSucceeds(deleteDoc(doc(db('mom'), `families/${FID}/rewards/r1`)));
});
