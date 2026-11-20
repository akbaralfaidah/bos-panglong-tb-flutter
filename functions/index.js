const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

function formatRupiah(amount) {
  const num = Number(amount) || 0;
  return "Rp " + Math.round(num).toLocaleString("id-ID");
}

/**
 * Mengirim push FCM prioritas tinggi (Android & iOS) ke semua perangkat Pemilik Toko
 * ketika karyawan membuat transaksi baru di `stores/{storeId}/transactions/{txId}`.
 *
 * Tetap berjalan 24/7 meskipun aplikasi Pemilik ditutup total, HP terkunci,
 * atau berhari-hari tidak dibuka (membutuhkan paket Firebase Blaze).
 */
exports.notifyOwnerOnEmployeeTransaction = onDocumentCreated(
  "stores/{storeId}/transactions/{txId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const tx = snap.data();
    const { storeId, txId } = event.params;
    if (!tx || tx.is_legacy_titipan === true) return;

    const role = String(tx.cashier_role || "").trim().toUpperCase();
    if (role === "OWNER") return;

    const tokensSnap = await admin
      .firestore()
      .collection("stores")
      .doc(storeId)
      .collection("owner_fcm_tokens")
      .where("enabled", "==", true)
      .get();

    if (tokensSnap.empty) return;

    const cashierName = String(tx.cashier_name || "Kasir").trim() || "Kasir";
    const customerName =
      String(tx.customer_name || "Pelanggan Umum").trim() || "Pelanggan Umum";
    const status = String(tx.payment_status || "Lunas").trim() || "Lunas";
    const method = String(tx.payment_method || "Tunai").trim() || "Tunai";
    const total = Number(tx.total_price) || 0;

    const title = `Transaksi Baru • Kasir ${cashierName}`;
    const body = `${customerName} • ${formatRupiah(total)} (${status} • ${method})`;

    const tokens = [];
    const tokenDocRefs = [];

    for (const doc of tokensSnap.docs) {
      const data = doc.data();
      // Fallback untuk app kasir versi lama tanpa `cashier_role`
      if (role !== "EMPLOYEE") {
        const ownerName = String(data.owner_name || "").trim();
        if (
          ownerName &&
          cashierName.toLowerCase() === ownerName.toLowerCase()
        ) {
          continue;
        }
      }
      if (data.token) {
        tokens.push(data.token);
        tokenDocRefs.push(doc.ref);
      }
    }

    if (tokens.length === 0) return;

    const message = {
      tokens,
      notification: { title, body },
      data: {
        docId: String(txId),
        txId: String(tx.id || txId),
        title,
        body,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "owner_employee_tx_channel_v2",
          sound: "default",
          visibility: "public",
          priority: "max",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
            "interruption-level": "time-sensitive",
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    const cleanup = [];
    response.responses.forEach((res, idx) => {
      if (!res.success) {
        const code = res.error && res.error.code;
        if (
          code === "messaging/invalid-registration-token" ||
          code === "messaging/registration-token-not-registered"
        ) {
          cleanup.push(tokenDocRefs[idx].delete());
        }
      }
    });
    if (cleanup.length > 0) {
      await Promise.allSettled(cleanup);
    }
  }
);
