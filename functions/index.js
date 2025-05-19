require("dotenv").config(); // Loads .env variables

const functions = require("firebase-functions");
const stripe = require("stripe")(process.env.STRIPE_SECRET_KEY);

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
