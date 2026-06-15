# Lendly 🤝

Lendly is a modern peer-to-peer item lending and renting platform built with **Flutter** and powered by **Firebase**. It allows users to list items for rent, browse/search available items, chat in real-time, process secure payments, and track the entire lifecycle of a transaction from initial request to return confirmation.

---

## 🌟 Key Features

*   **Secure Authentication**: Dual authentication flow supporting traditional Email/Password (with email verification) and Google Sign-In.
*   **Item Directory & Search**: Browse items by categories (Electronics, Appliances, Tools, Books, Furniture, Clothing, etc.), search items, and view availability.
*   **Real-time Chat**: Message system between borrowers and owners to negotiate terms directly within the app.
*   **State-driven Transactions**: Step-by-step transaction workflow:
    1.  **Request**: Borrower requests an item.
    2.  **Approval**: Owner approves the request.
    3.  **Payment**: Borrower pays for the rent.
    4.  **Receive**: Borrower marks the item as received.
    5.  **Return**: Borrower marks the item as returned.
    6.  **Confirm**: Owner confirms the return and completes the transaction.
*   **Stripe Payment Integration**: Secure payment intent generation using Firebase Cloud Functions and Stripe Payment Sheet.
*   **Dual-Platform Cloudinary Uploads**: Direct multi-platform photo uploading (Web & Mobile) using Cloudinary API.
*   **Detailed Profiles**: Edit profile details, locate items, view items listed by a user, and read ratings/reviews.

---

## 📂 Project Directory Structure

```text
lendly/
├── android/ & ios/ & macos/ & web/ ... # Native platform configuration files
├── assets/                             # App assets (icons, images, logos, fonts)
├── firebase/                           # Firebase local files (rules, index configuration)
│   ├── firestore.rules                 # Security rules for Firestore databases
│   └── storage.rules                   # Security rules for Firebase Storage (disabled)
├── functions/                          # Node.js Firebase Cloud Functions (Stripe API)
│   ├── index.js                        # Cloud Function endpoints (createPaymentIntent)
│   └── .env                            # Local environment keys for Cloud Functions
├── lib/                                # Flutter source code
│   ├── core/                           # Application core dependencies
│   │   ├── config/                     # Configurations (e.g. Firebase options)
│   │   ├── services/                   # App services (Cloudinary conditional imports)
│   │   └── utils/                      # Shared utility methods
│   ├── features/                       # Modular business features
│   │   ├── auth/                       # Signup, Login, Email Verification logic
│   │   ├── chat/                       # Live messaging, request negotiations
│   │   ├── items/                      # Items listings, Home feed, Borrowed dashboard
│   │   ├── payments/                   # Stripe integration, payment buttons
│   │   ├── profile/                    # User profile screen, Edit profiles, ratings
│   │   ├── insurance/                  # [Skeleton] Planned insurance flow
│   │   ├── requests/                   # [Skeleton] Planned request manager
│   │   └── search_filter/              # [Skeleton] Planned advanced filters
│   ├── shared/                         # Reusable UI widgets and cross-feature utilities
│   └── main.dart                       # App entry point & initialization
├── test/                               # Widget and unit tests
└── pubspec.yaml                        # Flutter dependencies and assets assets
```

For a detailed explanation of the architecture and data flows, please see [ARCHITECTURE.md](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/ARCHITECTURE.md).

---

## 🛠️ Prerequisites

Before you start, make sure you have the following installed on your machine:
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.7.2` or later)
*   [Node.js](https://nodejs.org/) (v16+ recommended for running Firebase Functions)
*   [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools`)
*   An active Google Account (for Firebase, Google sign-in)
*   Stripe Developer Account (for API testing keys)
*   Cloudinary Account (for image hosting)

---

## 🚀 Step-by-Step Local Setup

Follow these steps to set up the project locally on your development machine.

### 1. Clone the Repository
Clone the repository to your local machine:
```bash
git clone https://github.com/jerian-tgg/lendly.git
cd lendly
```

### 2. Install Flutter Dependencies
Run the command below to retrieve all required Flutter packages:
```bash
flutter pub get
```

### 3. Firebase Console Setup
1.  Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project named `lendly`.
2.  Enable the following Firebase services:
    *   **Authentication**: Enable *Email/Password* provider and *Google* provider.
    *   **Cloud Firestore**: Create a database in test mode.
    *   **Cloud Functions**: Upgrade your Firebase project to the *Blaze Plan* (required to run node.js functions).
3.  Configure your Flutter project with Firebase. Run the command below and follow the prompt:
    ```bash
    dart pub global activate flutterfire_cli
    flutterfire configure
    ```
    This will automatically link the apps and update [lib/core/config/firebase_options.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/core/config/firebase_options.dart).

### 4. Stripe & Cloud Functions Setup
1.  Go to your Stripe Dashboard and copy your **Test Secret Key** (`sk_test_...`).
2.  Navigate to the `functions` directory:
    ```bash
    cd functions
    npm install
    ```
3.  Create or update [functions/.env](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/functions/.env) file:
    ```env
    STRIPE_SECRET_KEY=your_stripe_test_secret_key_here
    ```
4.  Deploy your Cloud Functions:
    ```bash
    firebase deploy --only functions
    ```
    *Alternatively, you can run the emulator locally using `firebase emulators:start`.*

### 5. Cloudinary Configuration
Lendly uses Cloudinary to store images instead of Firebase Storage.
1.  Sign up or log in to [Cloudinary](https://cloudinary.com/).
2.  Obtain your **Cloud Name** and create an **unsigned upload preset** (e.g., `lendly_preset`).
3.  Update the credentials in the codebase:
    *   Open [lib/features/items/data/repositories/item_repository_impl.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/features/items/data/repositories/item_repository_impl.dart#L33-L34) and set `cloudName` and `uploadPreset`.
    *   Open [lib/core/services/cloudinary/cloudinary_service_mobile.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/core/services/cloudinary/cloudinary_service_mobile.dart#L7-L8) and update `cloudName` and `uploadPreset`.
    *   Open [lib/core/services/cloudinary/cloudinary_service_web.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/core/services/cloudinary/cloudinary_service_web.dart#L8-L9) and update `cloudName` and `uploadPreset`.

### 6. Run the Application
Make sure you have an emulator open or a physical device connected.
Run the application using:
```bash
flutter run
flutter run -d chrome
```

---

## 🧪 Running Tests

Ensure that everything builds and passes initial validation:
```bash
flutter test
```

---

## 🔒 Security Rules Deployment

To deploy the security rules for Firestore:
```bash
firebase deploy --only firestore:rules
```
This deploys the rules defined in [firebase/firestore.rules](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/firebase/firestore.rules) to keep conversation and chat data secure.
