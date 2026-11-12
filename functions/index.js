require("dotenv").config(); // Loads .env variables

const functions = require("firebase-functions/v1");
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
      const currency = data.currency || "php";

      try {
        const params = {
          amount: amount,
          currency: currency,
        };
        if (context.auth) {
          params.metadata = {
            userId: context.auth.uid,
            orcAmount: String(Math.round(amount / 100)),
            type: "cash_in",
          };
        }
        const paymentIntent = await stripe.paymentIntents.create(params);

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
 * Creates a Stripe Checkout Session and PaymentIntent for ORC Cash-In in PHP.
 * Rate: ₱1 = 1 ORC.
 */
exports.createStripeCashInSession = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "User must be logged in to cash in.",
        );
      }

      const rawAmount = Number(data && data.amount);
      if (!rawAmount || isNaN(rawAmount) || rawAmount < 20) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Minimum cash-in amount is ₱20 PHP.",
        );
      }

      const uid = context.auth.uid;
      const amountInCentavos = Math.round(rawAmount * 100);

      try {
        const session = await stripe.checkout.sessions.create({
          payment_method_types: ["card"],
          mode: "payment",
          line_items: [
            {
              price_data: {
                currency: "php",
                product_data: {
                  name: `${rawAmount} ORC Credits`,
                  description: "Lendly ORC Wallet Cash-In (₱1 = 1 ORC)",
                },
                unit_amount: amountInCentavos,
              },
              quantity: 1,
            },
          ],
          client_reference_id: uid,
          metadata: {
            userId: uid,
            orcAmount: String(rawAmount),
            type: "cash_in",
          },
          success_url: (data && data.successUrl) ||
            "https://lendly.app/wallet/success?session_id={CHECKOUT_SESSION_ID}",
          cancel_url: (data && data.cancelUrl) ||
            "https://lendly.app/wallet/cancel",
        });

        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountInCentavos,
          currency: "php",
          metadata: {
            userId: uid,
            orcAmount: String(rawAmount),
            type: "cash_in",
          },
        });

        return {
          sessionId: session.id,
          sessionUrl: session.url,
          clientSecret: paymentIntent.client_secret,
          amount: rawAmount,
        };
      } catch (error) {
        console.error("Error creating cash-in session:", error);
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);

/**
 * Stripe Webhook endpoint.
 * Validates Stripe signature and credits ORC idempotently.
 */
exports.stripeWebhook = functions.https.onRequest(
    async (req, res) => {
      if (req.method === "GET") {
        return res.status(200).send("Stripe webhook endpoint is active.");
      }
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }

      const sig = req.headers["stripe-signature"];
      const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

      let event;
      try {
        if (webhookSecret) {
          event = stripe.webhooks.constructEvent(
              req.rawBody,
              sig,
              webhookSecret,
          );
        } else {
          console.warn("STRIPE_WEBHOOK_SECRET missing; parsing body directly.");
          event = typeof req.body === "string" ?
            JSON.parse(req.body) : req.body;
        }
      } catch (err) {
        console.error("Stripe webhook signature error:", err.message);
        return res.status(400).send(`Webhook Error: ${err.message}`);
      }

      const eventId = event && event.id;
      if (!eventId) {
        return res.status(400).send("Missing event ID");
      }

      const db = admin.firestore();
      const eventRef = db.collection("stripe_events").doc(eventId);

      try {
        let userId = null;
        let orcAmount = 0;
        let referenceId = eventId;

        if (event.type === "checkout.session.completed") {
          const session = event.data.object;
          userId = (session.metadata && session.metadata.userId) ||
            session.client_reference_id;
          orcAmount = session.metadata && session.metadata.orcAmount ?
            Number(session.metadata.orcAmount) :
            (session.amount_total ? Math.round(session.amount_total / 100) : 0);
          referenceId = session.id || eventId;
        } else if (event.type === "payment_intent.succeeded") {
          const pi = event.data.object;
          userId = pi.metadata && pi.metadata.userId;
          orcAmount = pi.metadata && pi.metadata.orcAmount ?
            Number(pi.metadata.orcAmount) :
            (pi.amount ? Math.round(pi.amount / 100) : 0);
          referenceId = pi.id || eventId;
        }

        if (!userId || orcAmount <= 0) {
          return res.status(200).json({received: true, ignored: true});
        }

        await db.runTransaction(async (t) => {
          const eventDoc = await t.get(eventRef);
          if (eventDoc.exists && eventDoc.data().processed) {
            return;
          }

          const walletRef = db.collection("wallets").doc(userId);
          const walletDoc = await t.get(walletRef);

          const currentAvailable = walletDoc.exists ?
            (walletDoc.data().availableBalance || 0) : 0;
          const currentCashedIn = walletDoc.exists ?
            (walletDoc.data().totalCashedIn || 0) : 0;

          const newAvailable = currentAvailable + orcAmount;
          const newCashedIn = currentCashedIn + orcAmount;

          t.set(walletRef, {
            availableBalance: newAvailable,
            totalCashedIn: newCashedIn,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          t.set(db.collection("users").doc(userId), {
            balance: newAvailable,
          }, {merge: true});

          const txRef = walletRef.collection("transactions").doc();
          t.set(txRef, {
            id: txRef.id,
            type: "cash_in",
            amount: orcAmount,
            referenceId: referenceId,
            description: `Stripe Cash-in (₱${orcAmount} = ${orcAmount} ORC)`,
            status: "completed",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          t.set(eventRef, {
            processed: true,
            eventType: event.type,
            userId: userId,
            orcAmount: orcAmount,
            referenceId: referenceId,
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });

        return res.status(200).json({
          received: true,
          credited: orcAmount,
          userId: userId,
        });
      } catch (err) {
        console.error("Error processing Stripe webhook:", err);
        return res.status(500).send("Internal processing error");
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
            callback: "lendly://verify/done",
            callback_method: "both",
          }),
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error(
              "Didit session creation failed:",
              response.status,
              errorText,
          );
          throw new functions.https.HttpsError(
              "internal",
              `Didit session creation failed (${response.status}): ` +
              errorText,
          );
        }

        const session = await response.json();
        const sessionToken = session.session_token;
        const hostedUrl = session.url ||
          (sessionToken ?
            `https://verify.didit.me/session/${sessionToken}` :
            null);
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

/**
 * Shortens whole floats for X-Signature-V2 canonicalisation.
 * @param {*} v Value to process
 * @return {*} Processed value
 */
function shortenFloats(v) {
  if (Array.isArray(v)) return v.map(shortenFloats);
  if (v && typeof v === "object") {
    return Object.fromEntries(
        Object.entries(v).map(([k, x]) => [k, shortenFloats(x)]),
    );
  }
  if (typeof v === "number" && !Number.isInteger(v) && v % 1 === 0) {
    return Math.trunc(v);
  }
  return v;
}

/**
 * Recursively sorts keys for X-Signature-V2 canonicalisation.
 * @param {*} v Object or value to sort
 * @return {*} Object with sorted keys
 */
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
          console.error(
              "Didit session retrieve failed:",
              response.status,
              errorText,
          );
          throw new functions.https.HttpsError(
              "internal",
              `Didit session retrieve failed (${response.status}): ` +
              errorText,
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
 * Verifies X-Signature-V2 HMAC and updates user status in Firestore.
 */
exports.diditWebhook = functions.https.onRequest(
    async (req, res) => {
      if (req.method === "GET") {
        return res.status(200).send("Didit webhook endpoint is active.");
      }
      if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
      }

      const webhookSecret = process.env.DIDIT_WEBHOOK_SECRET;
      const sig = req.headers["x-signature-v2"] || "";
      const ts = Number(req.headers["x-timestamp"]);

      // 1. Freshness check (≤ 300s) when secret is configured
      if (webhookSecret && (!ts || Math.abs(Date.now() / 1000 - ts) > 300)) {
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
      const eventId =
        parsed.event_id || `${parsed.session_id}_${parsed.timestamp}`;
      const eventRef =
        admin.firestore().collection("didit_events").doc(eventId);
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

// ═══════════════════════════════════════════════════════════════════════════
// TRUST SCORE SYSTEM
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Core trust score calculation logic.
 * Reads reviews and conversations from Firestore, computes the weighted score,
 * and writes the result to the user document.
 *
 * Formula:
 *   TrustScore = (BayesianRatingPct × 0.60) + (ReliabilityPct × 0.30)
 *                + (ExperienceScore × 0.10)
 *
 * Bayesian Average: (C × M + N × R) / (C + N)
 *   C = 5 (prior weight), M = 4.0 (prior mean),
 *   N = number of ratings, R = actual average
 *
 * Reliability: completedTransactions / eligibleTransactions × 100
 *   Eligible = approved conversations not denied through no fault of user.
 *
 * Experience: min(completedTransactions / 20, 1) × 100
 *
 * @param {string} userId – The UID to recalculate.
 * @return {object} The computed trust score and stats.
 */
async function computeTrustScore(userId) {
  const db = admin.firestore();

  // ── 1. Fetch all reviews where this user is the reviewee ──
  const reviewsSnap = await db
      .collection("reviews")
      .where("revieweeId", "==", userId)
      .get();

  const ratings = [];
  reviewsSnap.forEach((doc) => {
    const r = doc.data().rating;
    if (typeof r === "number" && r > 0 && r <= 5) {
      ratings.push(r);
    }
  });

  const totalRatings = ratings.length;
  const actualAvg = totalRatings > 0 ?
    ratings.reduce((a, b) => a + b, 0) / totalRatings : 0;

  // Bayesian average
  const priorWeight = 5;
  const priorMean = 4.0;
  const bayesianRating =
    (priorWeight * priorMean + totalRatings * actualAvg) /
    (priorWeight + totalRatings);
  const bayesianPct = (bayesianRating / 5) * 100;

  // ── 2. Fetch conversations where this user is a participant ──
  const convosSnap = await db
      .collection("conversations")
      .where("participants", "array-contains", userId)
      .where("approved", "==", true)
      .get();

  let completedAsLender = 0;
  let eligibleAsLender = 0;
  let completedAsBorrower = 0;
  let eligibleAsBorrower = 0;

  convosSnap.forEach((doc) => {
    const d = doc.data();
    const isLender = d.itemOwnerId === userId || d.ownerId === userId;
    const isDenied = d.denied === true;

    const isCompleted = d.isPaid === true &&
      d.isReceived === true &&
      d.isReturned === true &&
      d.isReturnConfirmed === true;

    if (isLender) {
      // Lender approved then denied → counts against lender reliability
      eligibleAsLender++;
      if (isCompleted) {
        completedAsLender++;
      }
    } else {
      // Borrower: if lender denied, not borrower's fault → exclude
      if (!isDenied) {
        eligibleAsBorrower++;
        if (isCompleted) {
          completedAsBorrower++;
        }
      }
    }
  });

  const completedTransactions = completedAsLender + completedAsBorrower;
  const eligibleTransactions = eligibleAsLender + eligibleAsBorrower;

  // Reliability percentage (default 100% for users with no transactions)
  const reliabilityPct = eligibleTransactions > 0 ?
    (completedTransactions / eligibleTransactions) * 100 : 100;

  // Experience score: min(completed / 20, 1) × 100
  const experienceScore = Math.min(completedTransactions / 20, 1) * 100;

  // ── 3. Weighted final score ──
  const rawScore = (bayesianPct * 0.60) +
    (reliabilityPct * 0.30) +
    (experienceScore * 0.10);

  const trustScore = Math.max(0, Math.min(100, Math.round(rawScore)));

  const stats = {
    bayesianRating: Math.round(bayesianRating * 100) / 100,
    totalRatings,
    averageRating: Math.round(actualAvg * 100) / 100,
    completedTransactions,
    totalEligibleTransactions: eligibleTransactions,
    completedAsLender,
    eligibleAsLender,
    completedAsBorrower,
    eligibleAsBorrower,
    reliabilityPercentage: Math.round(reliabilityPct * 100) / 100,
    experienceScore: Math.round(experienceScore * 100) / 100,
    lastCalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // ── 4. Write to Firestore ──
  await db.collection("users").doc(userId).set({
    trustScore,
    trustScoreStats: stats,
  }, {merge: true});

  return {trustScore, stats};
}

/**
 * HTTPS Callable: recalculateTrustScore
 * Allows an authenticated user to trigger recalculation of their own score,
 * or an admin to recalculate any user's score.
 */
exports.recalculateTrustScore = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be logged in.",
        );
      }

      let targetUserId = context.auth.uid;
      if (data && data.userId) {
        const callerEmail = context.auth.token.email || "";
        const adminCheck = callerEmail === "admin-portal@lendly.internal" ||
          callerEmail === "palenciajerjer28@gmail.com";
        if (data.userId !== context.auth.uid && !adminCheck) {
          throw new functions.https.HttpsError(
              "permission-denied",
              "Cannot recalculate another user's trust score.",
          );
        }
        targetUserId = data.userId;
      }

      try {
        const result = await computeTrustScore(targetUserId);
        return result;
      } catch (error) {
        console.error("Error computing trust score:", error);
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);

/**
 * Firestore Trigger: When a conversation document is updated and reaches
 * a terminal state (completed or denied), recalculate trust scores for
 * all participants.
 */
/**
 * Helper to atomically settle escrow for a completed rental.
 * Releases escrow: 10% commission to admin wallet, 90% to lender's available.
 * All Firestore t.get() reads execute before any t.set()/t.update() writes.
 *
 * @param {admin.firestore.Transaction} t Firestore transaction
 * @param {admin.firestore.Firestore} db Firestore instance
 * @param {admin.firestore.DocumentSnapshot} convoDoc Conversation doc
 * @param {object} [extraConvoUpdates] Extra fields for conversation update
 * @return {Promise<object|null>} Settlement details or null
 */
async function settleEscrowTransaction(
    t,
    db,
    convoDoc,
    extraConvoUpdates = {},
) {
  const convoData = convoDoc.data();
  if (!convoData ||
      convoData.conversationType === "appraisal" ||
      convoData.isSettled === true ||
      convoData.escrowStatus === "settled" ||
      convoData.escrowStatus === "refunded") {
    if (Object.keys(extraConvoUpdates).length > 0) {
      t.update(convoDoc.ref, extraConvoUpdates);
    }
    return null;
  }

  const convoId = convoDoc.id;
  const itemId = convoData.itemId || "";

  // ── PHASE 1: ALL READS FIRST (Firestore Transaction Requirement) ──────────
  let itemData = null;
  if (itemId) {
    const itemDoc = await t.get(db.collection("items").doc(itemId));
    if (itemDoc.exists) {
      itemData = itemDoc.data();
    }
  }

  const lenderId = convoData.itemOwnerId ||
    convoData.ownerId ||
    (itemData && itemData.ownerId) ||
    "";
  const participants = Array.isArray(convoData.participants) ?
    convoData.participants : [];
  const borrowerId = convoData.borrowerId ||
    participants.find((p) => p && p !== lenderId) ||
    "";

  let total = Number(convoData.escrowAmount) || 0;
  if (total <= 0) {
    if (typeof convoData.totalPrice === "number" && convoData.totalPrice > 0) {
      total = convoData.totalPrice;
    } else {
      const days = Number(convoData.totalDays) || 1;
      const price = Number(convoData.price) ||
        Number(itemData && itemData.price) || 0;
      total = price * days;
    }
  }

  if (total <= 0 || !borrowerId || !lenderId) {
    t.update(convoDoc.ref, {
      ...extraConvoUpdates,
      escrowStatus: "settled",
      isSettled: true,
      settledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  }

  const adminEmail = "palenciajerjer28@gmail.com";
  const borrowerWalletRef = db.collection("wallets").doc(borrowerId);
  const lenderWalletRef = db.collection("wallets").doc(lenderId);
  const adminDedicatedWalletRef = db.collection("wallets").doc(adminEmail);
  const adminWalletRef = db.collection("admin_wallet").doc("main");

  const [
    borrowerWalletDoc,
    lenderWalletDoc,
    adminDedicatedWalletDoc,
    adminWalletDoc,
  ] = await Promise.all([
    t.get(borrowerWalletRef),
    t.get(lenderWalletRef),
    t.get(adminDedicatedWalletRef),
    t.get(adminWalletRef),
  ]);

  // ── PHASE 2: COMPUTE BALANCES & SPLITS (10% Admin / 90% Lender) ───────────
  const adminCommission = Math.round(total * 0.10 * 100) / 100;
  const lenderEarnings = Math.round((total - adminCommission) * 100) / 100;
  const itemName = convoData.itemName ||
    (itemData && (itemData.name || itemData.title)) ||
    "Rental Item";
  const nowTs = admin.firestore.FieldValue.serverTimestamp();

  // Borrower current escrow
  const borrowerEscrow = borrowerWalletDoc.exists ?
    Number(borrowerWalletDoc.data().escrowBalance || 0) : 0;
  const newBorrowerEscrow = convoData.escrowStatus === "held" ?
    Math.max(0, Math.round((borrowerEscrow - total) * 100) / 100) :
    borrowerEscrow;

  // Lender current balances
  const lenderAvailable = lenderWalletDoc.exists ?
    Number(lenderWalletDoc.data().availableBalance || 0) : 0;
  const lenderTotalEarned = lenderWalletDoc.exists ?
    Number(lenderWalletDoc.data().totalEarned || 0) : 0;
  const newLenderAvailable =
    Math.round((lenderAvailable + lenderEarnings) * 100) / 100;
  const newLenderTotalEarned =
    Math.round((lenderTotalEarned + lenderEarnings) * 100) / 100;

  // Dedicated Admin Wallet balances
  const currentAdminBalance = adminDedicatedWalletDoc.exists ?
    Number(adminDedicatedWalletDoc.data().balance ||
      adminDedicatedWalletDoc.data().availableBalance || 0) : 0;
  const currentAdminFees = adminDedicatedWalletDoc.exists ?
    Number(adminDedicatedWalletDoc.data().totalFeesCollected ||
      adminDedicatedWalletDoc.data().totalCommission || 0) : 0;
  const currentAdminPayouts = adminDedicatedWalletDoc.exists ?
    Number(adminDedicatedWalletDoc.data().totalPayoutsProcessed || 0) : 0;

  const newAdminBalance =
    Math.round((currentAdminBalance + adminCommission) * 100) / 100;
  const newAdminFees =
    Math.round((currentAdminFees + adminCommission) * 100) / 100;
  const newAdminPayouts =
    Math.round((currentAdminPayouts + lenderEarnings) * 100) / 100;

  // Legacy Admin Wallet balances
  const legacyAdminBalance = adminWalletDoc.exists ?
    Number(adminWalletDoc.data().balance || 0) : 0;
  const legacyTotalCommission = adminWalletDoc.exists ?
    Number(adminWalletDoc.data().totalCommission || 0) : 0;
  const legacyTotalPayouts = adminWalletDoc.exists ?
    Number(adminWalletDoc.data().totalPayoutsProcessed || 0) : 0;

  const newLegacyBalance =
    Math.round((legacyAdminBalance + adminCommission) * 100) / 100;
  const newLegacyCommission =
    Math.round((legacyTotalCommission + adminCommission) * 100) / 100;
  const newLegacyPayouts =
    Math.round((legacyTotalPayouts + lenderEarnings) * 100) / 100;

  // ── PHASE 3: ALL WRITES (t.set / t.update) ────────────────────────────────
  // 1. Borrower: release escrow balance & record settlement
  t.set(borrowerWalletRef, {
    escrowBalance: newBorrowerEscrow,
    updatedAt: nowTs,
  }, {merge: true});

  const borrowerTxRef = borrowerWalletRef
      .collection("transactions")
      .doc(`settle_${convoId}`);
  t.set(borrowerTxRef, {
    id: borrowerTxRef.id,
    type: "rental_payment",
    amount: -total,
    referenceId: convoId,
    itemId: itemId,
    itemName: itemName,
    description: `Rental completed — escrow released ` +
      `for ${itemName} (₱${total} ORC)`,
    status: "completed",
    createdAt: nowTs,
  }, {merge: true});

  // 2. Lender: credit 90% earnings to available balance
  t.set(lenderWalletRef, {
    availableBalance: newLenderAvailable,
    totalEarned: newLenderTotalEarned,
    updatedAt: nowTs,
  }, {merge: true});

  t.set(db.collection("users").doc(lenderId), {
    balance: newLenderAvailable,
  }, {merge: true});

  const lenderTxRef = lenderWalletRef
      .collection("transactions")
      .doc(`earn_${convoId}`);
  t.set(lenderTxRef, {
    id: lenderTxRef.id,
    type: "rental_earning",
    amount: lenderEarnings,
    grossAmount: total,
    commissionDeducted: adminCommission,
    referenceId: convoId,
    itemId: itemId,
    itemName: itemName,
    description: `Rental earnings for ${itemName} ` +
      `(90% of ₱${total} ORC = ₱${lenderEarnings} ORC)`,
    status: "completed",
    createdAt: nowTs,
  }, {merge: true});

  // 3. Admin wallet: credit 10% service fee to palenciajerjer28@gmail.com
  t.set(adminDedicatedWalletRef, {
    balance: newAdminBalance,
    availableBalance: newAdminBalance,
    totalFeesCollected: newAdminFees,
    totalCommission: newAdminFees,
    totalPayoutsProcessed: newAdminPayouts,
    role: "admin",
    email: adminEmail,
    updatedAt: nowTs,
  }, {merge: true});

  // Mirror balance and admin role to users/palenciajerjer28@gmail.com
  const adminUserRef = db.collection("users").doc(adminEmail);
  t.set(adminUserRef, {
    email: adminEmail,
    role: "admin",
    isAdmin: true,
    balance: newAdminBalance,
    totalFeesCollected: newAdminFees,
    updatedAt: nowTs,
  }, {merge: true});

  // Synchronize legacy admin_wallet/main for backward compatibility
  t.set(adminWalletRef, {
    balance: newLegacyBalance,
    totalCommission: newLegacyCommission,
    totalFeesCollected: newLegacyCommission,
    totalPayoutsProcessed: newLegacyPayouts,
    updatedAt: nowTs,
  }, {merge: true});

  // 4. Write Complete Admin Ledger Records:
  //    (a) Update Escrow Hold record to settled
  const holdId = `hold_${convoId}`;
  const holdRecord = {
    id: holdId,
    type: "escrow_hold",
    amount: total,
    grossAmount: total,
    referenceId: convoId,
    rentalId: convoId,
    itemId: itemId,
    itemName: itemName,
    borrowerId: borrowerId,
    lenderId: lenderId,
    description: `Escrow Hold settled for ${itemName} (₱${total} ORC)`,
    status: "settled",
    settledAt: nowTs,
  };
  t.set(
      adminDedicatedWalletRef.collection("transactions").doc(holdId),
      holdRecord,
      {merge: true},
  );
  t.set(
      adminWalletRef.collection("ledger").doc(holdId),
      holdRecord,
      {merge: true},
  );

  //    (b) Write 90% User Payout ledger record
  const payoutId = `payout_${convoId}`;
  const adminPayoutRecord = {
    id: payoutId,
    type: "lender_payout",
    amount: lenderEarnings,
    grossAmount: total,
    commissionAmount: adminCommission,
    referenceId: convoId,
    rentalId: convoId,
    itemId: itemId,
    itemName: itemName,
    borrowerId: borrowerId,
    lenderId: lenderId,
    description: `90% Lender Payout for ${itemName} ` +
      `(₱${lenderEarnings} ORC transferred to lender)`,
    status: "completed",
    createdAt: nowTs,
    timestamp: nowTs,
  };
  t.set(
      adminDedicatedWalletRef.collection("transactions").doc(payoutId),
      adminPayoutRecord,
      {merge: true},
  );
  t.set(
      adminDedicatedWalletRef.collection("wallet_logs").doc(payoutId),
      adminPayoutRecord,
      {merge: true},
  );
  t.set(
      adminWalletRef.collection("ledger").doc(payoutId),
      adminPayoutRecord,
      {merge: true},
  );

  //    (c) Write 10% Commission Collection ledger record
  const feeId = `fee_${convoId}`;
  const adminFeeRecord = {
    id: feeId,
    type: "service_fee",
    amount: adminCommission,
    grossAmount: total,
    payoutAmount: lenderEarnings,
    referenceId: convoId,
    rentalId: convoId,
    itemId: itemId,
    itemName: itemName,
    borrowerId: borrowerId,
    lenderId: lenderId,
    description: `10% Platform Commission from ${itemName} ` +
      `(₱${adminCommission} ORC of ₱${total} ORC)`,
    status: "completed",
    createdAt: nowTs,
    timestamp: nowTs,
  };
  t.set(
      adminDedicatedWalletRef.collection("transactions").doc(feeId),
      adminFeeRecord,
      {merge: true},
  );
  t.set(
      adminDedicatedWalletRef.collection("wallet_logs").doc(feeId),
      adminFeeRecord,
      {merge: true},
  );
  t.set(
      adminWalletRef.collection("ledger").doc(feeId),
      adminFeeRecord,
      {merge: true},
  );

  const commRef = adminWalletRef.collection("commissions").doc(convoId);
  t.set(commRef, {
    rentalId: convoId,
    itemId: itemId,
    itemName: itemName,
    amount: adminCommission,
    payoutAmount: lenderEarnings,
    grossAmount: total,
    lenderId: lenderId,
    borrowerId: borrowerId,
    status: "completed",
    timestamp: nowTs,
  }, {merge: true});

  // 5. Update conversation as settled
  t.update(convoDoc.ref, {
    ...extraConvoUpdates,
    escrowAmount: total,
    escrowStatus: "settled",
    settledAt: nowTs,
    adminCommission: adminCommission,
    lenderEarnings: lenderEarnings,
    isSettled: true,
  });

  return {adminCommission, lenderEarnings, total};
}

/**
 * Helper to atomically refund escrow to borrower.
 * Guards against double refunds by checking escrowStatus === "held".
 *
 * @param {admin.firestore.Transaction} t Firestore transaction
 * @param {admin.firestore.Firestore} db Firestore instance
 * @param {admin.firestore.DocumentSnapshot} convoDoc Conversation doc
 * @param {string} reason Cancellation / refund reason
 * @param {object} [extraConvoUpdates] Additional conversation fields to update
 * @return {Promise<number>} Refunded amount
 */
async function refundEscrowTransaction(
    t,
    db,
    convoDoc,
    reason,
    extraConvoUpdates = {},
) {
  const convoData = convoDoc.data();
  if (!convoData || convoData.escrowStatus !== "held") {
    if (Object.keys(extraConvoUpdates).length > 0) {
      t.update(convoDoc.ref, extraConvoUpdates);
    }
    return 0;
  }

  const convoId = convoDoc.id;
  const total = Number(convoData.escrowAmount) || 0;
  const borrowerId = convoData.borrowerId;
  const lenderId = convoData.itemOwnerId || convoData.ownerId || "";
  const itemId = convoData.itemId || "";
  const itemName = convoData.itemName || "Rental Item";
  const nowTs = admin.firestore.FieldValue.serverTimestamp();

  // Phase 1: Read borrower wallet first
  let borrowerWalletDoc = null;
  const borrowerWalletRef = borrowerId ?
    db.collection("wallets").doc(borrowerId) : null;
  if (total > 0 && borrowerWalletRef) {
    borrowerWalletDoc = await t.get(borrowerWalletRef);
  }

  // Phase 2: All writes
  if (total > 0 && borrowerId && borrowerWalletRef) {
    const currentAvailable = borrowerWalletDoc && borrowerWalletDoc.exists ?
      Number(borrowerWalletDoc.data().availableBalance || 0) : 0;
    const currentEscrow = borrowerWalletDoc && borrowerWalletDoc.exists ?
      Number(borrowerWalletDoc.data().escrowBalance || 0) : 0;

    const newAvailable = Math.round((currentAvailable + total) * 100) / 100;
    t.set(borrowerWalletRef, {
      availableBalance: newAvailable,
      escrowBalance: Math.max(
          0,
          Math.round((currentEscrow - total) * 100) / 100,
      ),
      updatedAt: nowTs,
    }, {merge: true});

    t.set(db.collection("users").doc(borrowerId), {
      balance: newAvailable,
    }, {merge: true});

    const txRef = borrowerWalletRef
        .collection("transactions")
        .doc(`refund_${convoId}`);
    t.set(txRef, {
      id: txRef.id,
      type: "rental_refund",
      amount: total,
      referenceId: convoId,
      description: `Refund for rental (${reason || "Rental cancelled"})`,
      status: "completed",
      createdAt: nowTs,
    }, {merge: true});

    // Log refund & update hold in Admin Ledger
    const adminEmail = "palenciajerjer28@gmail.com";
    const adminDedicatedWalletRef = db.collection("wallets").doc(adminEmail);
    const adminWalletRef = db.collection("admin_wallet").doc("main");
    const holdId = `hold_${convoId}`;
    const refundId = `refund_${convoId}`;

    const holdUpdate = {
      id: holdId,
      type: "escrow_hold",
      status: "refunded",
      refundedAt: nowTs,
    };
    t.set(
        adminDedicatedWalletRef.collection("transactions").doc(holdId),
        holdUpdate,
        {merge: true},
    );
    t.set(
        adminWalletRef.collection("ledger").doc(holdId),
        holdUpdate,
        {merge: true},
    );

    const refundRecord = {
      id: refundId,
      type: "escrow_refund",
      amount: total,
      grossAmount: total,
      referenceId: convoId,
      rentalId: convoId,
      itemId: itemId,
      itemName: itemName,
      borrowerId: borrowerId,
      lenderId: lenderId,
      description: `Escrow Refund to borrower ` +
        `(${reason || "Rental cancelled"}) — ₱${total} ORC`,
      status: "refunded",
      createdAt: nowTs,
      timestamp: nowTs,
    };
    t.set(
        adminDedicatedWalletRef.collection("transactions").doc(refundId),
        refundRecord,
        {merge: true},
    );
    t.set(
        adminWalletRef.collection("ledger").doc(refundId),
        refundRecord,
        {merge: true},
    );
  }

  t.update(convoDoc.ref, {
    ...extraConvoUpdates,
    escrowStatus: "refunded",
    refundedAt: nowTs,
    refundReason: reason || "Cancelled",
  });

  return total;
}

/**
 * Accepts a rental request and escrows the required ORC from borrower.
 */
exports.acceptRentalRequest = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be logged in to accept borrow requests.",
        );
      }

      const convoId = data && data.convoId;
      if (!convoId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "convoId is required.",
        );
      }

      const db = admin.firestore();
      const convoRef = db.collection("conversations").doc(convoId);

      return db.runTransaction(async (t) => {
        // Phase 1: All reads first
        const convoDoc = await t.get(convoRef);
        if (!convoDoc.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "Conversation does not exist.",
          );
        }

        const convoData = convoDoc.data();
        const itemId = convoData.itemId || "";
        let itemData = null;
        if (itemId) {
          const itemDoc = await t.get(db.collection("items").doc(itemId));
          if (itemDoc.exists) {
            itemData = itemDoc.data();
          }
        }

        const lenderId = convoData.itemOwnerId ||
          convoData.ownerId ||
          (itemData && itemData.ownerId);
        const participants = Array.isArray(convoData.participants) ?
          convoData.participants : [];
        const borrowerId = convoData.borrowerId ||
          participants.find((p) => p && p !== lenderId);

        if (context.auth.uid !== lenderId) {
          throw new functions.https.HttpsError(
              "permission-denied",
              "Only the item owner can accept this request.",
          );
        }

        if (convoData.approved === true) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "This request has already been accepted.",
          );
        }

        if (convoData.denied === true) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "This request has been denied.",
          );
        }

        // Calculate total = agreed price * duration
        let total = 0;
        if (typeof convoData.totalPrice === "number" &&
            convoData.totalPrice > 0) {
          total = convoData.totalPrice;
        } else {
          const days = Number(convoData.totalDays) || 1;
          const price = Number(convoData.price) ||
            Number(itemData && itemData.price) || 0;
          total = price * days;
        }

        if (!borrowerId) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "Conversation is missing borrower information.",
          );
        }

        const borrowerWalletRef = db.collection("wallets").doc(borrowerId);
        const borrowerWalletDoc = await t.get(borrowerWalletRef);

        const currentAvailable = borrowerWalletDoc.exists ?
          Number(borrowerWalletDoc.data().availableBalance || 0) : 0;
        const currentEscrow = borrowerWalletDoc.exists ?
          Number(borrowerWalletDoc.data().escrowBalance || 0) : 0;

        if (currentAvailable < total) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              `Borrower has insufficient ORC balance ` +
              `(Available: ₱${currentAvailable}, Required: ₱${total}).`,
          );
        }

        // Phase 2: All writes
        const nowTs = admin.firestore.FieldValue.serverTimestamp();
        const itemName = convoData.itemName ||
          (itemData && (itemData.name || itemData.title)) ||
          convoData.lastMessageText ||
          "Rental Item";

        if (total > 0) {
          const newAvailable =
            Math.round((currentAvailable - total) * 100) / 100;
          const newEscrow =
            Math.round((currentEscrow + total) * 100) / 100;

          t.set(borrowerWalletRef, {
            availableBalance: newAvailable,
            escrowBalance: newEscrow,
            updatedAt: nowTs,
          }, {merge: true});

          t.set(db.collection("users").doc(borrowerId), {
            balance: newAvailable,
          }, {merge: true});

          const txRef = borrowerWalletRef
              .collection("transactions")
              .doc(`escrow_${convoId}`);
          t.set(txRef, {
            id: txRef.id,
            type: "rental_escrow",
            amount: -total,
            referenceId: convoId,
            itemId: itemId,
            itemName: itemName,
            description: `Escrow hold for rental (${itemName})`,
            status: "held",
            createdAt: nowTs,
          }, {merge: true});

          // Log Escrow Hold in Admin Ledger
          const adminEmail = "palenciajerjer28@gmail.com";
          const adminDedicatedWalletRef =
            db.collection("wallets").doc(adminEmail);
          const adminWalletRef = db.collection("admin_wallet").doc("main");
          const holdId = `hold_${convoId}`;
          const holdRecord = {
            id: holdId,
            type: "escrow_hold",
            amount: total,
            grossAmount: total,
            referenceId: convoId,
            rentalId: convoId,
            itemId: itemId,
            itemName: itemName,
            borrowerId: borrowerId,
            lenderId: lenderId,
            description: `Escrow Hold locked for ${itemName} (₱${total} ORC)`,
            status: "held",
            createdAt: nowTs,
            timestamp: nowTs,
          };
          t.set(
              adminDedicatedWalletRef.collection("transactions").doc(holdId),
              holdRecord,
              {merge: true},
          );
          t.set(
              adminDedicatedWalletRef.collection("wallet_logs").doc(holdId),
              holdRecord,
              {merge: true},
          );
          t.set(
              adminWalletRef.collection("ledger").doc(holdId),
              holdRecord,
              {merge: true},
          );
        }

        t.update(convoRef, {
          approved: true,
          denied: false,
          isSettled: false,
          borrowerId: borrowerId,
          itemOwnerId: lenderId,
          ownerId: lenderId,
          escrowAmount: total,
          escrowStatus: total > 0 ? "held" : "none",
          acceptedAt: nowTs,
          lastUpdated: nowTs,
        });

        return {
          success: true,
          convoId,
          escrowAmount: total,
        };
      });
    },
);

/**
 * Callable endpoint to cancel a rental and refund any escrow to the borrower.
 */
exports.cancelOrRefundRental = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be logged in to cancel rental.",
        );
      }

      const convoId = data && data.convoId;
      if (!convoId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "convoId is required.",
        );
      }

      const db = admin.firestore();
      const convoRef = db.collection("conversations").doc(convoId);

      return db.runTransaction(async (t) => {
        const convoDoc = await t.get(convoRef);
        if (!convoDoc.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "Conversation not found.",
          );
        }

        const convoData = convoDoc.data();
        const uid = context.auth.uid;
        const isParticipant = (convoData.participants || []).includes(uid) ||
          convoData.borrowerId === uid ||
          convoData.itemOwnerId === uid ||
          convoData.ownerId === uid;

        const callerEmail = context.auth.token.email || "";
        const isAdminUser = callerEmail === "admin-portal@lendly.internal" ||
          callerEmail === "palenciajerjer28@gmail.com";

        if (!isParticipant && !isAdminUser) {
          throw new functions.https.HttpsError(
              "permission-denied",
              "Unauthorized to cancel this rental.",
          );
        }

        const refundedAmount = await refundEscrowTransaction(
            t,
            db,
            convoDoc,
            data.reason || "Rental cancelled",
            {
              denied: true,
              approved: false,
              cancelled: true,
              cancelReason: data.reason || "Rental cancelled",
              lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            },
        );

        return {success: true, refundedAmount};
      });
    },
);

/**
 * Callable endpoint to mark a rental as completed and settle escrow.
 */
exports.completeRental = functions.https.onCall(
    async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Must be logged in.",
        );
      }

      const convoId = data && data.convoId;
      if (!convoId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "convoId is required.",
        );
      }

      const db = admin.firestore();
      const convoRef = db.collection("conversations").doc(convoId);

      return db.runTransaction(async (t) => {
        const convoDoc = await t.get(convoRef);
        if (!convoDoc.exists) {
          throw new functions.https.HttpsError(
              "not-found",
              "Conversation not found.",
          );
        }

        const convoData = convoDoc.data();
        const uid = context.auth.uid;
        const lenderId = convoData.itemOwnerId || convoData.ownerId;
        const borrowerId = convoData.borrowerId;
        const isParticipant = (convoData.participants || []).includes(uid) ||
          uid === lenderId ||
          uid === borrowerId;
        const callerEmail = context.auth.token.email || "";
        const isAdminUser = callerEmail === "admin-portal@lendly.internal" ||
          callerEmail === "palenciajerjer28@gmail.com";

        if (!isParticipant && !isAdminUser) {
          throw new functions.https.HttpsError(
              "permission-denied",
              "Only a rental participant or admin can complete this rental.",
          );
        }

        const nowTs = admin.firestore.FieldValue.serverTimestamp();
        const completionFields = {
          isPaid: true,
          isReceived: true,
          isReturned: true,
          isReturnConfirmed: true,
          returnConfirmedAt: nowTs,
          lastUpdated: nowTs,
        };

        const settlement = await settleEscrowTransaction(
            t,
            db,
            convoDoc,
            completionFields,
        );
        return {success: true, settlement};
      });
    },
);

/**
 * Firestore Trigger: When a conversation document is updated and reaches
 * a terminal state (completed or denied), recalculate trust scores for
 * all participants, and settle/refund escrow.
 */
exports.onConversationStatusChange = functions.firestore
    .document("conversations/{convoId}")
    .onUpdate(async (change) => {
      const before = change.before.data();
      const after = change.after.data();

      const wasCompleted = before.isPaid === true &&
        before.isReceived === true &&
        before.isReturned === true &&
        before.isReturnConfirmed === true;

      const nowCompleted = after.isPaid === true &&
        after.isReceived === true &&
        after.isReturned === true &&
        after.isReturnConfirmed === true;

      const isReturnComplete = after.isReturned === true &&
        after.isReturnConfirmed === true &&
        (after.isPaid === true || after.approved === true);

      const deniedChanged = before.denied !== after.denied;

      // ── Settle Escrow if completed and not yet settled ──────
      if (isReturnComplete &&
          after.isSettled !== true &&
          after.escrowStatus !== "settled" &&
          after.escrowStatus !== "refunded" &&
          after.conversationType !== "appraisal") {
        await admin.firestore().runTransaction(async (t) => {
          const freshConvoDoc = await t.get(change.after.ref);
          await settleEscrowTransaction(t, admin.firestore(), freshConvoDoc);
        }).catch((err) => {
          console.error(
              `Escrow settlement error for convo ${change.after.id}:`,
              err,
          );
        });
      }

      // ── Refund Escrow if denied after being approved ────────
      if (after.denied === true && before.denied !== true &&
          after.escrowStatus === "held") {
        await admin.firestore().runTransaction(async (t) => {
          const freshConvoDoc = await t.get(change.after.ref);
          await refundEscrowTransaction(
              t,
              admin.firestore(),
              freshConvoDoc,
              "Lender denied rental request",
          );
        }).catch((err) => {
          console.error(
              `Escrow refund error for convo ${change.after.id}:`,
              err,
          );
        });
      }

      if (!deniedChanged && wasCompleted === nowCompleted) {
        return null;
      }

      const participants = after.participants || [];
      const promises = participants.map((uid) => {
        return computeTrustScore(uid).catch((err) => {
          console.error(`Trust score recalc error for ${uid}:`, err);
        });
      });

      return Promise.all(promises);
    });

/**
 * Firestore Trigger: When a review is created, updated, or deleted,
 * recalculate the trust score for the affected reviewee(s).
 */
exports.onReviewWrite = functions.firestore
    .document("reviews/{reviewId}")
    .onWrite(async (change) => {
      const affectedUserIds = new Set();

      if (change.before.exists) {
        const d = change.before.data();
        if (d.revieweeId) affectedUserIds.add(d.revieweeId);
      }
      if (change.after.exists) {
        const d = change.after.data();
        if (d.revieweeId) affectedUserIds.add(d.revieweeId);
      }

      const promises = [...affectedUserIds].map((uid) => {
        return computeTrustScore(uid).catch((err) => {
          console.error(`Trust score recalc error for ${uid}:`, err);
        });
      });

      return Promise.all(promises);
    });

/**
 * Callable endpoint to initialize or seed the admin user and wallet
 * documents for palenciajerjer28@gmail.com with role "admin", and
 * reconcile any completed rentals whose escrow settlement had not run.
 */
exports.seedAdminWallet = functions.https.onCall(
    async () => {
      const db = admin.firestore();
      const adminEmail = "palenciajerjer28@gmail.com";

      const walletRef = db.collection("wallets").doc(adminEmail);
      const walletSnap = await walletRef.get();
      if (!walletSnap.exists) {
        await walletRef.set({
          balance: 0.0,
          availableBalance: 0.0,
          totalFeesCollected: 0.0,
          totalCommission: 0.0,
          totalPayoutsProcessed: 0.0,
          role: "admin",
          email: adminEmail,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const userRef = db.collection("users").doc(adminEmail);
      const userSnap = await userRef.get();
      if (!userSnap.exists) {
        await userRef.set({
          email: adminEmail,
          role: "admin",
          isAdmin: true,
          balance: 0.0,
          totalFeesCollected: 0.0,
          displayName: "System Admin",
          joinedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const legacyRef = db.collection("admin_wallet").doc("main");
      const legacySnap = await legacyRef.get();
      if (!legacySnap.exists) {
        await legacyRef.set({
          balance: 0.0,
          totalCommission: 0.0,
          totalPayoutsProcessed: 0.0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Reconcile any completed rentals that were not yet settled
      let reconciledCount = 0;
      try {
        const convosSnap = await db
            .collection("conversations")
            .where("approved", "==", true)
            .get();

        for (const doc of convosSnap.docs) {
          const d = doc.data();
          if (d.conversationType === "appraisal") continue;
          const isCompleted = d.isReturned === true &&
            d.isReturnConfirmed === true;
          const isUnsettled = d.isSettled !== true &&
            d.escrowStatus !== "settled" &&
            d.escrowStatus !== "refunded";

          if (isCompleted && isUnsettled) {
            await db.runTransaction(async (t) => {
              const freshDoc = await t.get(doc.ref);
              const res = await settleEscrowTransaction(t, db, freshDoc);
              if (res) reconciledCount++;
            });
          }
        }
      } catch (err) {
        console.error("Error reconciling unsettled rentals:", err);
      }

      return {
        success: true,
        reconciledCount,
        message: "Admin account and wallet seeded and reconciled.",
      };
    },
);
