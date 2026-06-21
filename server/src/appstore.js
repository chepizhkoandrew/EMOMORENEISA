import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createPublicKey, createVerify, X509Certificate } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Apple Root CA - G3, downloaded from apple.com/certificateauthority and pinned.
const APPLE_ROOT = new X509Certificate(
  readFileSync(join(__dirname, "..", "certs", "AppleRootCA-G3.cer"))
);
const APPLE_ROOT_FINGERPRINT =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

function b64urlToBuffer(s) {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
}

function certFromX5cEntry(b64der) {
  // x5c entries are standard base64 DER (not base64url).
  return new X509Certificate(Buffer.from(b64der, "base64"));
}

// Verifies an Apple StoreKit 2 signed transaction (JWS) and returns the decoded
// transaction payload, or throws. Pins the chain to Apple Root CA - G3.
export function verifyStoreKitJWS(jws) {
  if (typeof jws !== "string" || jws.split(".").length !== 3) {
    throw new Error("malformed_jws");
  }
  const [headerB64, payloadB64, sigB64] = jws.split(".");

  const header = JSON.parse(b64urlToBuffer(headerB64).toString("utf8"));
  if (header.alg !== "ES256") throw new Error("unexpected_alg");
  if (!Array.isArray(header.x5c) || header.x5c.length < 2) throw new Error("missing_x5c");

  const leaf = certFromX5cEntry(header.x5c[0]);
  const root = certFromX5cEntry(header.x5c[header.x5c.length - 1]);

  // 1. The presented root must be Apple Root CA - G3 (pin by fingerprint).
  if (root.fingerprint256 !== APPLE_ROOT_FINGERPRINT || root.raw.compare(APPLE_ROOT.raw) !== 0) {
    throw new Error("untrusted_root");
  }

  // 2. Each cert in the chain must be issued by the next one.
  for (let i = 0; i < header.x5c.length - 1; i++) {
    const child = certFromX5cEntry(header.x5c[i]);
    const issuer = certFromX5cEntry(header.x5c[i + 1]);
    if (child.checkIssued(issuer) === false) throw new Error(`broken_chain_${i}`);
    if (!child.verify(issuer.publicKey)) throw new Error(`bad_signature_${i}`);
  }

  // 3. Validity window of the leaf.
  const now = Date.now();
  if (now < Date.parse(leaf.validFrom) || now > Date.parse(leaf.validTo)) {
    throw new Error("leaf_expired");
  }

  // 4. Verify the JWS signature with the leaf public key (ES256 = P1363 r||s).
  const signingInput = `${headerB64}.${payloadB64}`;
  const leafPub = createPublicKey(leaf.publicKey);
  const verifier = createVerify("SHA256");
  verifier.update(signingInput);
  verifier.end();
  const ok = verifier.verify(
    { key: leafPub, dsaEncoding: "ieee-p1363" },
    b64urlToBuffer(sigB64)
  );
  if (!ok) throw new Error("bad_jws_signature");

  return JSON.parse(b64urlToBuffer(payloadB64).toString("utf8"));
}
