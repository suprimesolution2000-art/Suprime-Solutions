# SS Supreme Solutions – Mobile Billing Management System

A production-grade mobile billing and invoice management system built specifically for **SS Supreme Solutions**, an industrial hardware supplier specializing in gaskets, hydraulic products, and related engineering components in Bilaspur, Chhattisgarh.

Designed with an ultra-simple, high-contrast digital billing workflow so that non-technical users (including the founder/father) can replace handwritten paper bills with 1-tap digital invoices and instant WhatsApp sharing and Bluetooth/Wi-Fi printing.

---

## 🌟 Key Capabilities

1. **Exact Original Tax Invoice Reproduction**:
   - Master scan coordinates calibrated to sub-millimeter precision.
   - Original **SS Suprime Solutions** logo, typography, pre-printed bank details (PNB Bilaspur), and legal terms preserved.
   - Preserves the authentic authorized business signature directly in the output PDF.
2. **Simple 1-Minute Billing Form**:
   - Customer autocomplete & instant party creation without leaving the screen.
   - Industrial hardware unit selection (`PCS`, `NOS`, `SET`, `MTR`, `KG`, `BOX`, `ROLL`).
   - Automated intra-state (CGST 9% + SGST 9%) vs. inter-state (IGST 18%) tax logic based on state of supply (`22` for Chhattisgarh).
   - Real-time round-off to nearest rupee and automatic Indian currency words generation (e.g. *"Rupees Thirty One Thousand Three Hundred Twenty Nine Only"*).
3. **Offline-First Architecture**:
   - Local SQLite database on device. Full bill creation, saving, and PDF generation with zero internet connectivity.
   - Sequential, conflict-free offline numbering allocated in reserved blocks.
   - Automatic background synchronization to MongoDB Atlas when internet returns.
4. **Universal Instant Search & Filters**:
   - Single top search bar supporting invoice number, customer name, phone number, GSTIN, product description, and HSN code.
   - Quick status chips: `All`, `Unpaid`, `Partial`, `Paid`, `Overdue`.
5. **Customer Management & Ledgers**:
   - Detailed ledger per customer showing total billed, total paid, and net balance due.
   - History of all invoices and payments.
6. **Payment Management**:
   - Record payments via UPI, Cash, Bank Transfer (NEFT/RTGS), or Cheque.
   - Supports full and partial payments with real-time balance reduction.

---

## 🛠️ Technology Stack

- **Mobile App**: Flutter 3.41 / Dart 3.11, Material 3, Riverpod (`flutter_riverpod`), SQLite (`sqflite`), Dio, PDF generation (`pdf` & `printing`), Sharing (`share_plus`).
- **Backend API**: Node.js v24, Express, MongoDB Atlas, Mongoose, JWT authentication, bcryptjs, Helmet, Rate Limiting.
- **PDF Engine**: Coordinate-based vector overlay on the master scanned invoice template (`assets/invoice-template/master_invoice.pdf`).

---

## 📁 Project Structure

```
SUPRIME SOLUTIONS/
├── mobile/                        # Flutter Android Application
│   ├── assets/invoice-template/   # Master invoice templates & coordinates
│   ├── lib/
│   │   ├── core/                  # Theme, Colors, Utilities (Number to words, Currency)
│   │   ├── data/                  # SQLite database, models, and repositories
│   │   ├── features/              # Home, Billing, Invoices, Customers, Reports, Settings
│   │   ├── providers/             # Riverpod state management
│   │   ├── services/              # PDF generator, Printing, Sync, and API client
│   │   └── main.dart
│   └── test/                      # Flutter widget and unit tests
├── backend/                       # Node.js REST API Backend
│   ├── src/
│   │   ├── config/                # Database and environment configuration
│   │   ├── controllers/           # Auth, Customers, Invoices, Payments, Reports, Sync
│   │   ├── middleware/            # JWT authentication, role guards, error handling
│   │   ├── models/                # Mongoose schemas (Invoices, Customers, Payments, Devices, Audit)
│   │   ├── routes/                # REST endpoints
│   │   ├── services/              # GST calculation, invoice sequencing, PDF overlay
│   │   └── server.js
│   └── test/                      # Automated API & GST unit tests
└── assets/invoice-template/       # Master template assets & verified test outputs
```

---

## 🚀 Running the Project

### 1. Backend REST API
```bash
cd backend
npm install
npm test      # Runs all GST calculation and PDF generation tests
npm start     # Starts server on http://localhost:5000
```

### 2. Mobile Application
```bash
cd mobile
flutter pub get
flutter test        # Runs widget and currency tests
flutter run         # Runs app on connected Android phone or emulator
```

### 3. Building Android APK
```bash
cd mobile
flutter build apk --release
```
The APK will be generated at `mobile/build/app/outputs/flutter-apk/app-release.apk`.
