/**
 * Standalone provisioning script for Admin Account & Wallet: palenciajerjer28@gmail.com
 *
 * Run with: node seed_admin.js
 */

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

const ADMIN_EMAIL = "palenciajerjer28@gmail.com";
const DEFAULT_AUTH_PASSWORD = "Lendly@Admin2024!"; // Meets Firebase Auth 6+ char rule

async function seedAdmin() {
  console.log(`[Seed] Provisioning Admin account & wallet for: ${ADMIN_EMAIL}...`);

  // 1. Firebase Auth user
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(ADMIN_EMAIL);
    console.log(`[Seed] Firebase Auth user already exists: ${userRecord.uid}`);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      userRecord = await auth.createUser({
        email: ADMIN_EMAIL,
        password: DEFAULT_AUTH_PASSWORD,
        displayName: "Lendly Admin",
        emailVerified: true,
      });
      console.log(`[Seed] Created Firebase Auth user: ${userRecord.uid}`);
    } else {
      console.warn(`[Seed] Auth lookup notice: ${err.message}`);
    }
  }

  // 2. Firestore User Document: users/palenciajerjer28@gmail.com
  const userRef = db.collection("users").doc(ADMIN_EMAIL);
  const userDoc = await userRef.get();
  if (!userDoc.exists) {
    await userRef.set({
      email: ADMIN_EMAIL,
      displayName: "Lendly Admin",
      role: "admin",
      isAdmin: true,
      balance: 0.0,
      totalFeesCollected: 0.0,
      isVerified: true,
      accountType: "admin",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[Seed] Created user document: users/${ADMIN_EMAIL}`);
  } else {
    await userRef.set({
      role: "admin",
      isAdmin: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    console.log(`[Seed] Updated role: "admin" on users/${ADMIN_EMAIL}`);
  }

  // If userRecord exists, also ensure users/{uid} is mirrored
  if (userRecord && userRecord.uid) {
    const uidRef = db.collection("users").doc(userRecord.uid);
    await uidRef.set({
      email: ADMIN_EMAIL,
      displayName: "Lendly Admin",
      role: "admin",
      isAdmin: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  // 3. Firestore Wallet Document: wallets/palenciajerjer28@gmail.com
  const walletRef = db.collection("wallets").doc(ADMIN_EMAIL);
  const walletDoc = await walletRef.get();
  if (!walletDoc.exists) {
    await walletRef.set({
      balance: 0.0,
      availableBalance: 0.0,
      totalFeesCollected: 0.0,
      totalCommission: 0.0,
      role: "admin",
      email: ADMIN_EMAIL,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[Seed] Initialized wallet: wallets/${ADMIN_EMAIL} (balance: 0.0, totalFeesCollected: 0.0)`);
  } else {
    console.log(`[Seed] Wallet already exists: wallets/${ADMIN_EMAIL}`);
  }

  // 4. Ensure legacy admin_wallet/main document exists
  const legacyRef = db.collection("admin_wallet").doc("main");
  const legacyDoc = await legacyRef.get();
  if (!legacyDoc.exists) {
    await legacyRef.set({
      balance: 0.0,
      totalCommission: 0.0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log("[Seed] Initialized legacy admin_wallet/main document");
  }

  console.log("[Seed] Completed successfully! Credentials mapping:");
  console.log(`       UI Login: ${ADMIN_EMAIL} / admin`);
  console.log(`       Firebase Auth: ${ADMIN_EMAIL} / ${DEFAULT_AUTH_PASSWORD}`);
}

seedAdmin().catch((err) => {
  console.error("[Seed] Error provisioning admin:", err);
  process.exit(1);
});

