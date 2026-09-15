# Lendly Setup & Cloning Guide 🚀

This guide provides step-by-step instructions for teammates to clone, configure, and run the **Lendly** project on their local development environments. It also details the exact SDKs, Gradle versions, and dependencies to ensure smooth builds and prevent environment issues.

---

## 🛠️ Complete Environment & SDK Requirements

To run this project, ensure that your device has the exact versions of the SDKs, JDK, and platforms listed below. Using different versions might cause build and compilation failures.

### 1. SDKs & Core Environments
| Tool / SDK | Version | Configuration Details |
| :--- | :--- | :--- |
| **Flutter SDK** | `3.29.0` (Dart `3.7.2`) | Locked per-project with **FVM** ([.fvm/fvm_config.json](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/.fvm/fvm_config.json)) |
| **Java JDK** | **JDK 11** | Required for Android build compatibility |
| **Node.js** | **v18.x** | Locked per-project with [functions/.nvmrc](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/functions/.nvmrc) |
| **Android NDK** | `27.0.12077973` | Specified in [app/build.gradle.kts](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/android/app/build.gradle.kts) |
| **CocoaPods** | `1.15.x` or later | (Optional) Required for iOS compilation |

### 2. Android Build Infrastructure
These settings are defined in the Gradle and settings configs inside the [android](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/android) directory:
*   **Gradle Wrapper Version**: `8.11.1` (configured in [gradle-wrapper.properties](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/android/gradle/wrapper/gradle-wrapper.properties))
*   **Android Gradle Plugin (AGP)**: `8.9.1` (declared in [settings.gradle.kts](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/android/settings.gradle.kts))
*   **Kotlin Plugin Version**: `2.2.21` (declared in [settings.gradle.kts](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/android/settings.gradle.kts))
*   **Compile SDK**: `36`
*   **Target SDK**: `36`
*   **Minimum SDK**: `23`
*   **Java Compatibility**: `JavaVersion.VERSION_11` (both Source & Target Compatibility)

---

## 📦 Project Dependencies & Versions

### Flutter App Dependencies (`pubspec.yaml` & `pubspec.lock`)
These packages will be automatically downloaded when running `fvm flutter pub get`. 

> [!IMPORTANT]
> The exact resolved package versions are committed in [pubspec.lock](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/pubspec.lock). **Never delete or ignore `pubspec.lock`**, as it guarantees every team member compiles with identical dependency trees.

| Package | Version Constraint | Purpose |
| :--- | :--- | :--- |
| **firebase_core** | `^4.10.0` | Root Firebase connection |
| **cloud_firestore** | `^6.5.0` | Real-time database services |
| **cloud_functions** | `^6.3.2` | Calling payment cloud functions |
| **firebase_auth** | `^6.5.2` | User auth flows |
| **firebase_storage** | `^13.4.2` | File storage hooks (rules restricted) |
| **firebase_messaging** | `^16.3.0` | Live notifications |
| **google_sign_in** | `^7.2.0` | Google Sign-in flow |
| **provider** | `^6.1.5` | App state helpers |
| **intl** | `^0.20.2` | Date/time and currency formatting |
| **cupertino_icons** | `^1.0.8` | iOS system icons |
| **image_picker** | `^1.2.1` | Native gallery/camera picker |
| **flutter_stripe** | `^13.0.0` | Stripe Payment Sheets integration |
| **fluttertoast** | `^9.0.0` | In-app alerts/toasts |
| **http** | `^1.6.0` | Cloudinary HTTP upload client |

### Firebase Cloud Functions Dependencies (`functions/package.json`)
Run `npm install` inside the `functions` folder to fetch these:

| Package | Version | Purpose |
| :--- | :--- | :--- |
| **dotenv** | `^16.5.0` | Local environment variable helper |
| **firebase-admin** | `^12.6.0` | Server-side Firebase interaction |
| **firebase-functions** | `^6.0.1` | Building HTTPS endpoints |
| **stripe** | `^18.1.0` | Interacting with the Stripe API |

---

## 🚀 Step-by-Step Cloning & Setup Instructions

Follow these steps precisely to set up and run Lendly on your device:

### Step 1: Clone the GitHub Repository
Clone the repository to your preferred local directory:
```bash
git clone https://github.com/jerian-tgg/lendly.git
cd lendly
```

### Step 2: Set Up Flutter SDK with FVM (Flutter Version Management)
To ensure that all team members run on the exact same Flutter SDK version (`3.29.0`), Lendly uses **FVM**:

1. Install FVM globally (if you haven't already):
   ```bash
   dart pub global activate fvm
   ```
   *(Make sure the Dart global pub cache `bin` directory is added to your system `PATH`)*.

2. Install and link the project-specified Flutter version:
   ```bash
   fvm install
   ```

3. **IDE Configuration**:
   * **VS Code**: Already configured via [.vscode/settings.json](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/.vscode/settings.json) to use `.fvm/flutter_sdk`.
   * **Android Studio**: Open **Settings > Languages & Frameworks > Flutter**, and set the Flutter SDK path to:
     `<project_directory>/.fvm/flutter_sdk`

### Step 3: Set Up Android Local Properties
1. Navigate to the `android` folder and create a file named `local.properties`.
2. Add your local Android SDK and FVM Flutter SDK path:
   ```properties
   sdk.dir=C:/Users/YOUR_USERNAME/AppData/Local/Android/Sdk
   flutter.sdk=c:/Users/YOUR_USERNAME/.../lendly/.fvm/flutter_sdk
   ```
   *(Ensure forward slashes `/` are used even on Windows).*

### Step 4: Install Flutter Dependencies
Run the command in the root folder of the project using FVM:
```bash
fvm flutter pub get
```

### Step 5: Verify Environment Diagnostics
Verify that your Flutter SDK, Android Studio, Gradle environment, and JDK are properly integrated:
```bash
fvm flutter doctor -v
```
> [!IMPORTANT]
> Make sure `flutter doctor` displays JDK 11 under the Android toolchain details. If it shows JDK 17 or JDK 21, it may trigger compilation failures on older Gradle configs.

### Step 6: Firebase Project Association
1. Log in to your Firebase CLI:
   ```bash
   firebase login
   ```
2. Activate and run `flutterfire_cli` to configure Firebase definitions:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   Follow the prompts to associate the project with your Firebase console.

### Step 7: Install Backend Functions Dependencies
1. Navigate to the `functions` directory:
   ```bash
   cd functions
   ```
2. Switch to Node 18 using `.nvmrc` (if using nvm):
   ```bash
   nvm use
   ```
3. Install dependencies:
   ```bash
   npm install
   ```
4. Create a local environment variables file `functions/.env` and insert your Stripe secret key:
   ```env
   STRIPE_SECRET_KEY=sk_test_your_secret_stripe_key
   ```
5. Deploy the backend functions to Firebase:
   ```bash
   firebase deploy --only functions
   ```

### Step 8: Cloudinary Credentials Configuration
To enable product and profile image uploads, configure your Cloudinary keys inside these three files:
1. **Mobile Service**: [cloudinary_service_mobile.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/core/services/cloudinary/cloudinary_service_mobile.dart#L7-L8)
2. **Web Service**: [cloudinary_service_web.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/core/services/cloudinary/cloudinary_service_web.dart#L8-L9)
3. **Repository**: [item_repository_impl.dart](file:///c:/Users/palen/OneDrive/Documents/GitHub/lendly/lib/features/items/data/repositories/item_repository_impl.dart#L33-L34)

Replace the placeholder `cloudName` and `uploadPreset` parameters with your Cloudinary account details.

### Step 9: Run the Application
Start your preferred emulator/device and execute:
```bash
fvm flutter run
```

---

## 🔍 Common Build Issues & Troubleshooting

### ❌ Issue 1: Gradle Build Failure (Unsupported Java / Class File Version)
*   **Cause**: You are using a Java version newer than JDK 11 (such as JDK 17 or JDK 21).
*   **Fix**: 
    1. Download and install **JDK 11**.
    2. Set your environment variables (`JAVA_HOME`) pointing to your JDK 11 path.
    3. In Android Studio, navigate to **Settings > Build, Execution, Deployment > Build Tools > Gradle** and verify that the Gradle JDK is explicitly configured to JDK 11.

### ❌ Issue 2: NDK missing or version mismatch
*   **Cause**: Android Studio does not have NDK `27.0.12077973` downloaded.
*   **Fix**:
    1. Open Android Studio and open **SDK Manager**.
    2. Go to **SDK Tools** and check the box **Show Package Details**.
    3. Expand **NDK (Side by side)** and check the box next to version `27.0.12077973`.
    4. Click **Apply** and wait for download to finish.

### ❌ Issue 3: Firebase Functions deploy fails with engine constraints
*   **Cause**: Node.js environment is not matching version 18.
*   **Fix**: Install `nvm` (Node Version Manager) and switch to Node 18:
    ```bash
    nvm install 18
    nvm use 18
    ```
