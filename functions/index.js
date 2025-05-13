/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const functions = require("firebase-functions");
const stripe = require("stripe")("sk_test_51RMuEjP8rCIii99HuU2d1SydZgDVHBb1AXSaun1l5jC3BHKSv6K7PN6IEGlBDgyE0LpAbgElGn6Pm5lctdkaPR9x00rWGcbz7B");

exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
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
});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
