```markdown
# Chanda 💸

Chanda is a modern, cross-platform expense-sharing application built with Flutter and Firebase. Designed to simplify group expense tracking, bill splitting, and debt settlements, Chanda features a clean, high-performance UI and advanced AI-powered receipt scanning.

## 🌍 Live Web App
**[https://chanda-401.web.app/](https://chanda-401.web.app/)**

## ✨ Key Features

* **Smart Bill Scanning (AI OCR):** Automatically extracts itemized lists, quantities, prices, delivery fees, taxes, and discounts from digital receipts.
  * *Primary Engine:* Google Gemini (Flash) for images and native PDF parsing.
  * *Fallback Engine:* Groq Cloud (Qwen 3.8 27B) vision integration ensuring 99.9% uptime.
  * *Local Extraction:* Syncfusion PDF extraction for robust digital invoice processing.
* **Real-Time Group Balances:** Calculates global balances ("Overall, you are owed") and per-group dynamic top debtor/creditor breakdowns instantly.
* **Advanced Debt Settlement:** Built-in exact-amount settlement flows (UPI/Cash/Bank) that perfectly balance out ledger mathematics.
* **Interactive Activity Feed:** A chronological, WhatsApp-style timeline tracking group creations, transaction updates, and manual user comments.
* **Read Receipts & Tracking:** Tracks bill views, displaying a blue dot for unread bills and a green double-tick (`✓✓`) once reviewed by members.
* **Cross-Platform:** Beautiful, responsive UI available on Android, iOS, and Web.

## 🛠️ Tech Stack

* **Frontend:** [Flutter](https://flutter.dev/) (Dart)
* **State Management:** Riverpod
* **Backend:** [Firebase](https://firebase.google.com/) (Firestore, Authentication, Hosting)
* **AI & Vision:** 
  * `google_generative_ai` (Gemini API)
  * Groq REST API (Qwen 3.8 27B)
* **Utilities:** `image_picker`, `file_picker`, `printing`, `syncfusion_flutter_pdf`

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (v3.19.0 or higher)
* A Firebase Project with Firestore and Authentication enabled.
* API Keys for Google Gemini and Groq Cloud.

### Installation

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/Sadam452/splitwise.git](https://github.com/Sadam452/splitwise.git)
   cd splitwise

```

2. **Install dependencies:**
```bash
flutter pub get

```


3. **Configure Firebase:**
* Run `flutterfire configure` to connect your Firebase project.
* Ensure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are placed in their respective directories.


4. **Configure AI API Keys:**
Chanda securely fetches API keys from Firestore rather than local `.env` files.
* Open your Firebase Firestore console.
* Create a collection named `app_config` and a document named `secrets`.
* Add two string fields: `gemini_api_key` and `groq_api_key`, containing your respective keys.


5. **Run the app:**
```bash
flutter run

```



## 🔒 Firestore Security Rules

To ensure the app functions correctly while protecting user data, ensure your Firestore rules are configured. For local development and testing, use:

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}

```

*(Note: Update these to stricter group-based access rules before production deployment).*

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://www.google.com/search?q=https://github.com/Sadam452/splitwise/issues).

## 📄 License

This project is licensed under the MIT License.

```

```