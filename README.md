# Orchid — Peer-to-Peer Item Rental Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.29.0%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.8.0-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20Functions%20%7C%20Storage-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Stripe](https://img.shields.io/badge/Stripe-SDK%20%5E14.2.0%20%7C%20Webhooks-635BFF?logo=stripe&logoColor=white)](https://stripe.com)

**Orchid** is a mobile-first peer-to-peer (P2P) physical item rental platform engineered to make local borrowing and lending secure, transparent, and verifiable. Built with **Flutter** and **Firebase**, Orchid protects both borrowers and lenders through an **ORC virtual wallet with automated escrow settlement**, **quantitative third-party item appraisals**, **algorithmic Bayesian trust scoring**, **geolocated proximity discovery**, **RA 8792–compliant electronic contracts**, and **QR-verified physical handoffs**.

> [!NOTE]
> **Repository & Package Naming:** The Flutter package (`pubspec.yaml`), Android application ID (`com.example.lendly`), and Firebase project (`lendly-6ee08`) retain the internal `lendly` identifier, while the user-facing application, branding, and Android launcher (`Orchid`) present the platform as **Orchid**.

---

## Core Features & System Mechanics

### 1. ORC Virtual Wallet & Stripe Integration
- **1:1 In-App Currency (`₱1 PHP = 1 ORC`):** Users fund their ORC Wallet (`lib/features/wallet/`) via **Stripe** in Philippine Pesos (minimum cash-in: **₱20 PHP**).
- **Multi-Platform Cash-In Flow:** `CashInDialog` calls the `createStripeCashInSession` Cloud Function (`functions/index.js`), which provisions both a Stripe Checkout Session and a `PaymentIntent`. Mobile builds invoke the native Stripe Payment Sheet via `flutter_stripe`, with automatic fallback to Stripe Checkout via `url_launcher` on web or unsupported environments.
- **Idempotent Webhook Fulfillment:** The `stripeWebhook` HTTPS endpoint verifies Stripe signatures (`STRIPE_WEBHOOK_SECRET`), deduplicates incoming events (`checkout.session.completed`, `payment_intent.succeeded`) in `stripe_events/{eventId}`, and atomically increments `wallets/{userId}.availableBalance` while recording a `cash_in` ledger entry.

### 2. Automated Escrow Release Mechanism
Orchid enforces a state-driven rental pipeline inside Firestore (`conversations/{convoId}`) backed by atomic transactions in `functions/index.js` and `WalletRepository`:
1. **Request & Escrow Lock (`acceptRentalRequest`):** When a lender approves a borrow request, the agreed rental total (`totalPrice` or `price × totalDays`) is atomically transferred from the borrower's `availableBalance` to `escrowBalance` (`escrowStatus: "held"`) and logged as an `escrow_hold` in both the borrower's wallet and the Admin Ledger.
2. **Digital Contract & Physical Verification:** Both parties execute an electronic lending agreement (`ElectronicContractPage` / `ContractService`, compliant with Philippine **RA 8792**) with PDF generation and Firebase Storage archival, followed by mutual in-person QR code scanning (`QrHandoffScreen`) to confirm **Handoff** (`isPaid`, `isReceived`) and **Return** (`isReturned`, `isReturnConfirmed`).
3. **Automated 90% / 10% Settlement:** Return confirmation triggers `completeRental` (and the `onConversationStatusChange` Firestore trigger / `WalletRepository.settleEscrowInFirestore` verification), atomically releasing escrow:
   - **90%** is credited to the lender's `availableBalance` (`rental_earning` / `lender_payout`).
   - **10%** platform service fee is credited to the Admin Wallet (`service_fee`).
4. **Automated Refunds (`cancelOrRefundRental`):** If an approved rental is denied or cancelled prior to completion, `refundEscrowTransaction` atomically returns 100% of the held ORC back to the borrower's `availableBalance` (`rental_refund` / `escrow_refund`).

### 3. Bayesian-Adjusted Trust Score System
To prevent rating manipulation and protect new community members, Trust Scores (`0–100`) are computed server-side by `computeTrustScore` (`functions/index.js`), guarded against client tampering by `firebase/firestore.rules`, and mirrored for UI breakdown and unit testing in `TrustScoreService` (`lib/core/services/trust_score_service.dart`) and `TrustScoreCard`:

$$\text{TrustScore} = (\text{BayesianPct} \times 0.60) + (\text{ReliabilityPct} \times 0.30) + (\text{ExperienceScore} \times 0.10)$$

| Component | Weight | Formula & Anti-Manipulation Logic |
| :--- | :---: | :--- |
| **Bayesian Rating** | **60%** | $\frac{C \cdot M + N \cdot R}{C + N}$ where prior weight $C = 5$ and prior mean $M = 4.0$, normalized to a percentage of `5.0`. Prevents a single 5★ or 1★ review from skewing reputation. |
| **Transaction Reliability** | **30%** | $\frac{\text{completedTransactions}}{\text{eligibleTransactions}} \times 100$ (defaults to `100%` baseline). Post-approval lender denials penalize lender reliability while excluding fault from the borrower. |
| **Platform Experience** | **10%** | $\min\left(\frac{\text{completedTransactions}}{20}, 1\right) \times 100$, rewarding consistent community participation up to 20 completed rentals. |

- **Automatic Triggers:** Recalculated automatically on review writes (`onReviewWrite`) and terminal conversation states (`onConversationStatusChange`), or manually via the `recalculateTrustScore` Cloud Function.
- **Reputation Tiers:** *Excellent Standing* (`90–100`), *Very Good Standing* (`75–89`), *Good Standing* (`60–74`), *Fair Standing* (`40–59`), and *Developing Member* (`< 40`).

### 4. Structured Item Appraisal Workflows
Orchid integrates an accredited appraiser portal (`AppraisalDashboard`, `AppraisalFormDialog`, `AppraisalModel`) for standardized pre-rental item valuation and condition grading:
- **Specialty-Locked Access:** Only KYC-verified users whose business registration/BIR permits (`RegisterBusinessScreen`) have been approved by an administrator can appraise items, and strict 1-to-1 category matching (`ItemCategories`) restricts appraisers to their certified specialty while blocking self-appraisals and prohibited asset classes (real estate, vehicles, firearms, luxury jewelry).
- **Mandatory QR Meetup Verification:** Before submitting an appraisal, the appraiser must verify physical inspection by scanning the owner's QR code via `OwnerMeetupScannerDialog` or `QrHandoffScreen` (`appraisal_meetup`).
- **Dual-Axis Quantitative Rubric:** Appraisers score **Function (`1–10`)** and **Cosmetic (`1–10`)** condition, producing an averaged **Overall Score (`1.0–10.0`)** and deterministic grade (`Mint / Like New`, `Excellent (Minor Wear)`, `Good (Fully Functional)`, `Fair (Visible Wear)`, or `Poor / Needs Repair`), alongside a private estimated market value, serial/cleanliness flags, unique certificate ID (`CERT-2026-APP...`), and pre-existing `DocumentedDefect` records (`Minor`, `Moderate`, `Major` with photos) that embed directly into rental contracts.

### 5. Location Radius Filtering
- **Geospatial Discovery (`LocationHelper` & `LocationPickerMapDialog`):** Combines `geolocator`, `flutter_map`, `latlong2`, OpenStreetMap Nominatim reverse geocoding, and IP geolocation fallback (`ip-api.com`), bounded within the Philippine archipelago (`4.2°–21.5° N`, `116.0°–127.0° E`) with quick city presets.
- **Proximity Filtering & Sorting:** Users drop a custom map pin and adjust a discovery radius slider (**5 km – 100 km / Any distance**, defaulting to **10 km**). `HomeScreen` calculates real-world spherical Haversine distances (`LocationHelper.calculateDistance`) and sorts nearby listings by proximity.

### 6. Role-Based Access & Admin Panel
Orchid enforces distinct operational capabilities across four user roles:
- **Visitor (Guest):** Browse and search available marketplace items in read-only mode (`HomeScreen(isGuest: true)`).
- **Standard User (Borrower / Lender):** Email/Password (with mandatory email verification) or Google Sign-In (`FirebaseAuthService`), Didit KYC identity & liveness verification (`DiditVerificationService`), listing management, real-time chat, RA 8792 contract signing, ORC Wallet transactions, reviews, and violation reporting (`ReportService`).
- **Verified Appraiser:** KYC-verified user with an admin-approved business/permit application, unlocking `AppraisalDashboard` for specialty-matched item certifications.
- **Administrator (`AdminLoginPage` & `AdminDashboardPage`):** Protected by Firestore `isAdmin()` rules and server-side email authorization, providing:
  - **User Management (`AdminUserManagementPage`):** Search users, verify KYC status, and block/unblock accounts (`isBlocked`).
  - **Violation Reports (`AdminReportsPage`):** Triage `Pending`, `Reviewed`, and `Dismissed` user/item reports with uploaded photo/video evidence and admin notes.
  - **Appraiser Verification Queue (`AdminDashboardScreen`):** Inspect uploaded BIR/DTI/SEC/PRC permits (`DocumentViewerDialog`) and approve or reject applications with structured feedback.
  - **Admin Wallet & Escrow Ledger (`AdminWalletPage`, `AdminWalletSummaryCard`):** Real-time monitoring of Admin Fee Balance, 10% platform commissions, active escrow holds, 90% lender payouts, escrow refunds, and ledger reconciliation (`seedAdminWallet` / `reconcileRentalsAndAdminLedger`).

---

## Tech Stack & Architecture

| Layer | Technologies & Verified Versions (`pubspec.yaml` / `functions/package.json`) |
| :--- | :--- |
| **Frontend & UI** | Flutter (`3.29.0` pinned in `.fvmrc`; tested with `3.47.4`), Dart (`^3.8.0`), Material Design (`ColorScheme.fromSeed`, `#98259A` Orchid theme), `cupertino_icons ^1.0.8`, `fluttertoast ^9.0.0`, `intl ^0.20.2` |
| **State Management** | Lightweight reactive `ValueNotifier` + `ValueListenableBuilder` (e.g., `LocationPickerMapDialog` map pin, radius, and geocoding state), `StreamBuilder` real-time Firestore bindings, `StatefulWidget` / `StatelessWidget` modular composition, `provider ^6.1.5` |
| **Backend & Database** | `firebase_core ^4.10.0`, `firebase_auth ^6.5.2`, `google_sign_in ^7.2.0`, `cloud_firestore ^6.5.0`, `cloud_functions ^6.3.2` (Node.js `22`, `firebase-functions ^6.0.1`, `firebase-admin ^12.6.0`), `firebase_storage ^13.4.2`, `firebase_messaging ^16.3.0` |
| **Payments & Webhooks** | `flutter_stripe ^14.2.0` (mobile Payment Sheet), `stripe ^18.1.0` (Cloud Functions Checkout Sessions, PaymentIntents & `stripeWebhook`), `url_launcher ^6.3.2` |
| **KYC & Media Storage** | Didit Verification API v3 (`DiditVerificationService`, `createDiditVerificationSession`, `getDiditVerificationSession`, `diditWebhook` HMAC-SHA256), Cloudinary REST API (`image_picker ^1.2.1`, `http ^1.6.0`) |
| **Maps, QR & Contracts** | `flutter_map ^8.3.2`, `latlong2 ^0.10.1`, `geolocator ^14.1.2`, OpenStreetMap Nominatim, `qr_flutter ^4.1.0`, `mobile_scanner ^7.0.1`, `pdf ^3.11.1`, `printing ^5.13.2` |
| **Tooling & Testing** | `flutter_test`, `flutter_lints ^6.0.0`, `dotenv ^16.5.0`, `eslint ^8.15.0`, `eslint-config-google ^0.14.0` |

### Architectural Pattern
Orchid uses a **feature-first layered architecture** under `lib/features/`, separating domain entities/models, data sources/repositories, and presentation pages/widgets, supported by cross-cutting services and helpers in `lib/core/`:
- **Client vs. Server Authority:** Critical financial mutations (Stripe cash-in crediting, escrow locks, 90%/10% settlement splits, refunds) and reputation calculations (`trustScore`, `trustScoreStats`) are implemented as transactional Cloud Functions (`functions/index.js`) and protected in `firebase/firestore.rules`, with idempotent client fallback/reconciliation in `WalletRepository` where applicable.

---

## Sandbox / Demo Credentials (For Testers & Evaluators)

> [!IMPORTANT]
> **Evaluator Quick-Access Credentials**
> Use the administrative account below via the **Admin Portal** (accessible from `LoginPage` or `AdminLoginPage`) to inspect moderation queues, escrow ledgers, and verification workflows.

| Role | Email / Identifier | Password | Key Capabilities to Test |
| :--- | :--- | :--- | :--- |
| **Platform Admin** | `palenciajerjer28@gmail.com` | `[INSERT_ADMIN_PASSWORD]` | • **Appraiser Verification Queue:** Review BIR/business permits and approve/reject applicants (`AdminDashboardScreen`)<br>• **Escrow & Ledger Oversight:** Inspect active escrow holds, 90% lender payouts, 10% commissions, refunds, and run ledger sync (`AdminWalletPage`)<br>• **User Management:** Search accounts, audit KYC status, and block/unblock users (`AdminUserManagementPage`)<br>• **Dispute & Violation Resolution:** Review pending reports with evidence media and log admin notes (`AdminReportsPage`)<br>• **Trust Score Recalculation:** Authorized admin invocation of `recalculateTrustScore` for any `userId` (`functions/index.js`) |
| **Borrower (Standard User)** | `[INSERT_BORROWER_EMAIL]` | `[INSERT_BORROWER_PASSWORD]` | • Top up ORC Wallet via Stripe test cards, filter items by map pin & radius, request rentals, sign RA 8792 contracts, scan QR handoff/return, and submit reviews/reports |
| **Lender / Appraiser** | `[INSERT_LENDER_EMAIL]` | `[INSERT_LENDER_PASSWORD]` | • List items, accept borrow requests (triggering borrower escrow lock), sign contracts, confirm returns (triggering 90%/10% settlement), and certify specialty items after QR meetup scan |

> [!TIP]
> **Alternative Evaluation Paths:** Testers can also register two fresh accounts via **Sign Up** (email verification required) or **Google Sign-In**, or tap **Skip** on the login screen to evaluate read-only **Visitor** discovery and proximity filtering immediately.

---

## Getting Started & Local Setup

### 1. Prerequisites
- **Flutter SDK:** `>=3.29.0` (project `.fvmrc` targets `3.29.0`; verified on Flutter `3.47.4` / Dart `^3.8.0`)
- **Node.js & npm:** Node.js `v22` (`functions/package.json`)
- **CLI Tools:** [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools`) and FlutterFire CLI (`dart pub global activate flutterfire_cli`)
- **IDE & Android Tooling:** Android Studio (Android SDK `compileSdk 36`, `ndkVersion 28.2.13676358`, Java 17 per `android/app/build.gradle.kts`) and/or VS Code with Flutter/Dart extensions
- **External Accounts:** Firebase project (Blaze plan for Cloud Functions), Stripe Developer account (Test Mode), Cloudinary account (unsigned upload preset), and Didit KYC account (optional for live ID verification)

### 2. Installation
Clone the repository and install Flutter and Cloud Functions dependencies:

```bash
git clone https://github.com/jerian-tgg/lendly.git
cd lendly
flutter pub get
cd functions && npm install && cd ..
```

### 3. Environment & Firebase Configuration

<details>
<summary><strong>Step-by-Step Firebase, Stripe, Didit & Cloudinary Setup</strong></summary>

#### A. Firebase Project & Native Config
1. Create or select your project in the [Firebase Console](https://console.firebase.google.com/) and enable:
   - **Authentication:** *Email/Password* and *Google* providers.
   - **Cloud Firestore:** Provision the database.
   - **Firebase Storage:** Enable for signed RA 8792 lending contract PDFs (`contracts/{convoId}/orchid_contract.pdf`).
   - **Cloud Functions:** Ensure the project is on the **Blaze** plan.
2. Link your Firebase apps and regenerate `lib/core/config/firebase_options.dart` and `android/app/google-services.json` (plus `GoogleService-Info.plist` for iOS/macOS if targeting Apple platforms):
   ```bash
   flutterfire configure
   ```
3. Deploy Firestore rules, indexes, and Storage rules from `firebase/`:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```

#### B. Cloud Functions Environment Variables (`functions/.env`)
Copy `functions/.env.example` to `functions/.env` and populate your test credentials:
```env
# Stripe API Keys (Test Mode)
STRIPE_SECRET_KEY=sk_test_your_secret_stripe_key_here
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_signing_secret_here

# Didit KYC API Keys
DIDIT_API_KEY=your_didit_api_key_here
DIDIT_WEBHOOK_SECRET=your_didit_webhook_secret_here
```

Deploy Cloud Functions (or run locally via the Firebase Emulator Suite configured on port `5001` / UI port `4000` in `firebase.json`):
```bash
firebase deploy --only functions
# Or run locally:
firebase emulators:start --only functions
```

#### C. Admin Provisioning Script (Optional)
To initialize the admin user record and dedicated ORC wallet in Firestore (`users/palenciajerjer28@gmail.com`, `wallets/palenciajerjer28@gmail.com`, and `admin_wallet/main`), run with Firebase Admin credentials configured:
```bash
node functions/seed_admin.js
```

#### D. Client-Side Service Configuration
Update the client configuration constants to match your sandbox accounts:
- **Stripe Publishable Key:** `lib/features/payments/data/config/stripe_keys.dart` (`StripeKeys.publishableKey`)
- **Didit KYC Config:** `lib/core/config/didit_config.dart` (`DiditAppConfig.workflowId`, `DiditAppConfig.apiKey`, callback scheme `orchid://verify/done`)
- **Cloudinary Upload Preset & Cloud Name:**
  - `lib/features/items/data/repositories/item_repository_impl.dart`
  - `lib/core/services/document_upload_service.dart`
  - `lib/core/services/cloudinary/cloudinary_service_mobile.dart`
  - `lib/core/services/cloudinary/cloudinary_service_web.dart`

</details>

### 4. Running the App & Tests
Ensure an Android emulator, iOS simulator, physical device, or Chrome browser is available:

```bash
# Run in debug mode on connected device/emulator
flutter run

# Run on Chrome (Web)
flutter run -d chrome

# Build a release Android APK
flutter build apk --release

# Run the unit and widget test suite (13 test files in test/)
flutter test
```

---

## Project Directory Structure

```text
lendly/
├── android/ & ios/ & web/ ...               # Native platform configs (Android app label: "Orchid", compile/targetSdk 36)
├── assets/                                  # Fonts (Roboto, Montserrat), icons, images, and Orchid brand logos
├── firebase/                                # Firebase security & deployment definitions
│   ├── firestore.rules                      # Role-based rules (protects trustScore, wallets, admin_wallet, stripe_events)
│   ├── firestore.indexes.json               # Composite index for violation reports (status + createdAt)
│   └── storage.rules                        # Access rules for signed RA 8792 PDF contracts
├── functions/                               # Node.js 22 Firebase Cloud Functions
│   ├── .env.example                         # Template for Stripe & Didit secrets
│   ├── index.js                             # Stripe Cash-In/Webhook, Didit KYC, Escrow Engine, Trust Score triggers
│   ├── package.json                         # Functions dependencies (stripe ^18.1.0, firebase-admin, firebase-functions)
│   └── seed_admin.js                        # Standalone script to provision admin user & wallet documents
├── test/                                    # Unit & widget tests (trust_score_test.dart, orc_wallet_test.dart, etc.)
├── pubspec.yaml                             # Flutter dependencies, SDK constraints (^3.8.0), and asset declarations
└── lib/
    ├── main.dart                            # App entry point, Firebase & Stripe SDK initialization, Orchid Material theme
    ├── core/                                # Cross-cutting configs, constants, services, theme, and utilities
    │   ├── config/
    │   │   ├── didit_config.dart            # Didit KYC API v3 workflow ID, base URL, and deep-link callback
    │   │   └── firebase_options.dart        # FlutterFire-generated platform Firebase options
    │   ├── constants/
    │   │   └── item_categories.dart         # Canonical item categories, specialty matching, prohibited asset guardrails
    │   ├── services/
    │   │   ├── cloudinary/                  # Conditional mobile/web/stub Cloudinary image uploaders
    │   │   ├── didit/
    │   │   │   └── didit_verification_service.dart  # Hosted Didit KYC session launch & decision polling
    │   │   ├── document_upload_service.dart # Cross-platform BIR/business permit & report media uploads
    │   │   ├── report_service.dart          # User/item violation report submission & admin streaming
    │   │   ├── review_service.dart          # Item/user reviews & automatic trust score recalculation trigger
    │   │   └── trust_score_service.dart     # Server-synced Trust Score reader & Bayesian computation mirror
    │   ├── theme/
    │   │   └── app_colors.dart              # Orchid purple (#98259A) palette and gradient constants
    │   └── utils/
    │       ├── convo_id.dart                # Deterministic participant conversation ID generator
    │       ├── convo_utils.dart             # Rental & appraisal conversation lookup/creation helpers
    │       ├── image_utils.dart             # Network image URL validation helper
    │       └── location_helper.dart         # Haversine distance, PH bounds check, GPS/IP/Nominatim geocoding
    ├── features/                            # Modular feature-first packages
    │   ├── admin/presentation/
    │   │   ├── pages/                       # AdminLoginPage, AdminDashboardPage, AdminUserManagementPage,
    │   │   │                                # AdminReportsPage, AdminDashboardScreen (appraisers), AdminWalletPage
    │   │   └── widgets/                     # AdminWalletSummaryCard, AdminLedgerTransactionCard, DocumentViewerDialog
    │   ├── appraisal/
    │   │   ├── domain/models/
    │   │   │   └── appraisal_model.dart     # Quantitative rubric (1–10 Function/Cosmetic), grades, DocumentedDefect
    │   │   └── presentation/
    │   │       ├── pages/appraisal_dashboard.dart         # Specialty-filtered portal for certified appraisers
    │   │       └── widgets/                 # AppraisalFormDialog, OwnerMeetupScannerDialog
    │   ├── auth/
    │   │   ├── data/datasources/firebase_auth_service.dart # Email/Password, Google Sign-In, profile initialization
    │   │   └── presentation/pages/          # AuthWrapper, LoginPage (with Guest skip & Admin redirect), SignupPage
    │   ├── business/
    │   │   ├── data/repositories/business_application_repository.dart # Appraiser permit submission & admin review
    │   │   ├── domain/entities/business_application.dart
    │   │   └── presentation/pages/register_business_screen.dart # Business/BIR permit onboarding for appraisers
    │   ├── chat/
    │   │   ├── data/                        # ChatRemoteDataSource, ChatMessageModel, ChatRepositoryImpl
    │   │   ├── domain/                      # ChatMessage, Conversation entities & ChatRepository interface
    │   │   └── presentation/pages/          # ConversationScreen, ChatScreen, QrHandoffScreen (handoff/return/appraisal)
    │   ├── items/
    │   │   ├── data/repositories/item_repository_impl.dart # Firestore CRUD & Cloudinary item photo uploads
    │   │   ├── domain/                      # Item entity & ItemRepository interface
    │   │   └── presentation/
    │   │       ├── pages/                   # HomeScreen, SearchScreen, ItemDetailScreen, TransactionsPage,
    │   │       │                            # BorrowedItemsScreen, ElectronicContractPage, ContractService, ReportScreen
    │   │       └── widgets/                 # ItemCard, AddItemDialog, LocationPickerMapDialog (ValueNotifier), RibbonBanner
    │   ├── payments/
    │   │   ├── data/                        # StripeKeys config & StripeService Cloud Function calls
    │   │   ├── domain/usecases/payment_use_case.dart # Direct Stripe Payment Sheet execution
    │   │   └── presentation/widgets/pay_button.dart
    │   ├── profile/
    │   │   ├── data/datasources/firebase_user_service.dart # Firestore user profile & KYC sync service
    │   │   └── presentation/
    │   │       ├── pages/                   # UserProfilePage (KYC, appraiser entry, reviews, listings), EditProfilePage
    │   │       └── widgets/                 # TrustScoreCard, PersonalQrCodeCard, ReviewDialog
    │   ├── wallet/
    │   │   ├── data/repositories/wallet_repository.dart # ORC streams, escrow hold/settle/refund & ledger reconciliation
    │   │   ├── domain/entities/             # Wallet & WalletTransaction entities
    │   │   └── presentation/                # OrcWalletScreen & CashInDialog (Stripe PHP-to-ORC top-ups)
    │   ├── insurance/                       # [Placeholder] Planned rental insurance module
    │   ├── requests/                        # [Placeholder] Planned standalone request manager module
    │   └── search_filter/                   # [Placeholder] Planned advanced search module
    └── shared/                              # [Placeholder] Shared utilities & cross-feature widgets
```
