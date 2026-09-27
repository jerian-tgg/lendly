require("dotenv").config(); // Loads .env variables

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) {
  admin.initializeApp();
}

const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);

// Workflow ID for Didit KYC ("Free KYC")
const DIDIT_WORKFLOW_ID = "99c79fd1-9b53-4c2d-a1b7-341b4a893c3b";

exports.createPaymentIntent = functions.https.onCall(
    async (data, context) => {
      const amount = data.amount;
      const currency = data.currency;

      try {
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amount,
          currency: currency,
        });

        return {
          clientSecret: paymentIntent.client_secret,
        };
      } catch (error) {
        console.error("Stripe error:", error);
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);

/**
 * Creates a Didit Verification Session for an authenticated user.
 * Returns session_token (for Flutter Didit SDK) and session_id.
 */
exports.createDiditVerificationSession = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be logged in to create a verification session.",
        );
      }

      const apiKey = process.env.DIDIT_API_KEY;
      if (!apiKey) {
        console.error("DIDIT_API_KEY is not configured in functions/.env");
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Didit API key is not configured.",
        );
      }

      const uid = context.auth.uid;
      const vendorData = data && data.vendorData ? data.vendorData : uid;

      try {
        const response = await fetch("https://verification.didit.me/v3/session/", {
          method: "POST",
          headers: {
            "x-api-key": apiKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            workflow_id: DIDIT_WORKFLOW_ID,
            vendor_data: vendorData,
            callback: "https://lendly.app/verify/done",
          }),
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error("Didit session creation failed:", response.status, errorText);
          throw new functions.https.HttpsError(
              "internal",
              `Didit session creation failed (${response.status}): ${errorText}`,
          );
        }

        const session = await response.json();
        const sessionToken = session.session_token;
        const hostedUrl = session.url ||
          (sessionToken ? `https://verify.didit.me/session/${sessionToken}` : null);
        return {
          sessionId: session.session_id,
          sessionToken,
          url: hostedUrl,
          status: session.status,
        };
      } catch (error) {
        console.error("Error creating Didit verification session:", error);
        if (error instanceof functions.https.HttpsError) {
          throw error;
        }
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);

// Helper for X-Signature-V2 canonicalisation
function shortenFloats(v) {
  if (Array.isArray(v)) return v.map(shortenFloats);
  if (v && typeof v === "object") {
    return Object.fromEntries(
        Object.entries(v).map(([k, x]) => [k, shortenFloats(x)]),
    );
  }
  if (typeof v === "number" && !Number.isInteger(v) && v % 1 === 0) return Math.trunc(v);
  return v;
}

function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === "object") {
    return Object.keys(v)
        .sort()
        .reduce((acc, k) => {
          acc[k] = sortKeys(v[k]);
          return acc;
        }, {});
  }
  return v;
}

/**
 * Retrieves a Didit session decision and syncs it to the signed-in user's
 * Firestore profile. Used when the user returns from the hosted flow.
 */
exports.getDiditVerificationSession = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be logged in to check verification status.",
        );
      }

      const apiKey = process.env.DIDIT_API_KEY;
      if (!apiKey) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Didit API key is not configured.",
        );
      }

      const sessionId = data && data.sessionId;
      if (!sessionId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "sessionId is required.",
        );
      }

      try {
        const response = await fetch(
            `https://verification.didit.me/v3/session/${sessionId}/decision/`,
            {headers: {"x-api-key": apiKey}},
        );

        if (!response.ok) {
          const errorText = await response.text();
          console.error("Didit session retrieve failed:", response.status, errorText);
          throw new functions.https.HttpsError(
              "internal",
              `Didit session retrieve failed (${response.status}): ${errorText}`,
          );
        }

        const decision = await response.json();
        const uid = context.auth.uid;
        await applyDiditStatusToUser(uid, sessionId, decision.status);

        return {
          sessionId,
          status: decision.status,
        };
      } catch (error) {
        console.error("Error retrieving Didit verification session:", error);
        if (error instanceof functions.https.HttpsError) {
          throw error;
        }
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);

/**
 * Applies a Didit session status to a Firestore user document.
 * @param {string} userId
 * @param {string} sessionId
 * @param {string} status
 */
async function applyDiditStatusToUser(userId, sessionId, status) {
  if (!userId) return;
  const userRef = admin.firestore().collection("users").doc(userId);
  const updates = {
    verificationStatus: status,
    verificationSessionId: sessionId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (status === "Approved") {
    updates.isVerified = true;
    updates.verifiedAt = admin.firestore.FieldValue.serverTimestamp();
    updates.isVerificationPending = false;
  } else if (status === "Declined") {
    updates.isVerified = false;
    updates.isVerificationPending = false;
  } else if (status === "In Review") {
    updates.isVerificationPending = true;
  }

  await userRef.set(updates, {merge: true});
}

/**
 * Didit Webhook endpoint.
 * Verifies X-Signature-V2 HMAC and updates user verification status in Firestore.
 */
exports.diditWebhook = functions.https.onRequest(
    async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }

      const webhookSecret = process.env.DIDIT_WEBHOOK_SECRET;
      const sig = req.headers["x-signature-v2"] || "";
      const ts = Number(req.headers["x-timestamp"]);

      // 1. Freshness check (≤ 300s)
      if (!ts || Math.abs(Date.now() / 1000 - ts) > 300) {
        return res.status(401).send("stale");
      }

      const body = req.body;
      const raw = typeof body === "string" ? body : JSON.stringify(body);
      let parsed;
      try {
        parsed = typeof body === "string" ? JSON.parse(raw) : body;
      } catch (e) {
        return res.status(400).send("invalid json");
      }

      // 2. Canonicalisation & signature verification (if secret configured)
      if (webhookSecret) {
        const canonical = JSON.stringify(sortKeys(shortenFloats(parsed)));
        const expected = crypto
            .createHmac("sha256", webhookSecret)
            .update(canonical, "utf8")
            .digest("hex");

        if (
          sig.length !== expected.length ||
          !crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sig))
        ) {
          return res.status(401).send("bad sig");
        }
      }

      // 3. Idempotency via Firestore event_id
      const eventId = parsed.event_id || `${parsed.session_id}_${parsed.timestamp}`;
      const eventRef = admin.firestore().collection("didit_events").doc(eventId);
      const eventDoc = await eventRef.get();
      if (eventDoc.exists) {
        return res.status(200).send("ok");
      }
      await eventRef.set({
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
        sessionId: parsed.session_id,
        status: parsed.status,
      });

      // 4. Update user in Firestore based on status
      const userId = parsed.vendor_data;
      await applyDiditStatusToUser(userId, parsed.session_id, parsed.status);

      return res.status(200).send("ok");
    },
);

