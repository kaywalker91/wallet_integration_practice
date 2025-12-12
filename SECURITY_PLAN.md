# Security Improvement Plan for Wallet Integration Practice

This document outlines the security measures implemented and planned for protecting sensitive keys and user data in the application.

## 1. Environment Variable Management (Implemented ✅)
We have migrated hardcoded sensitive keys (like WalletConnect Project ID) to environment variables using `.env` files.

- **Action Taken:**
  - Installed `flutter_dotenv` package.
  - Created `.env` file in project root.
  - Added `.env` to `.gitignore` to prevent accidental commits.
  - Updated `AppConstants.dart` to read from `dotenv`.
  - Updated `main.dart` to initialize `dotenv`.

- **Next Steps for Developer:**
  - Add other sensitive keys (RPC URLs, API Keys) to `.env` as needed.
  - Create a `.env.example` file with placeholder values for team members.

## 2. Secure Storage (Implemented ✅)
The app currently uses `flutter_secure_storage` to store sensitive user session data.

- **Usage:**
  - Wallet session tokens and connection metadata are stored in the platform's secure storage (Keychain on iOS, Keystore on Android).
  - This prevents data extraction from rooted devices or backups.

## 3. API Key Restrictions (Required Action ⚠️)
For third-party services like WalletConnect, Google Maps, or Firebase, you must restrict API key usage in the provider's console.

- **WalletConnect Cloud:**
  - Go to [WalletConnect Cloud Dashboard](https://cloud.reown.com).
  - Select your project (`f0c9...`).
  - Enable **Allowlist Domains** (e.g., `ility.io`).
  - Add **Bundle ID / Package Name** restriction: `com.example.wallet_integration_practice` (check your `android/app/build.gradle` for the exact ID).

## 4. Code Obfuscation (Production Build)
When building the app for release, always use obfuscation to make reverse engineering difficult.

- **Command:**
  ```bash
  flutter build apk --obfuscate --split-debug-info=/<project-name>/<directory>
  ```

## 5. Native Build Security
Protect keys used in native Android/iOS build configurations (e.g., Keystore passwords, Maps API keys in Manifest).

- **Android:**
  - Store keystore passwords in `android/key.properties` and add it to `.gitignore`.
  - Reference them in `android/app/build.gradle`.

## 6. Root/Jailbreak Detection (Optional)
Consider adding `flutter_jailbreak_detection` package to restrict app usage on compromised devices if high security is required.
