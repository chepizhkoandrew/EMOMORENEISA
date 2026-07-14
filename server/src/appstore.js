import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createPublicKey, createVerify, X509Certificate } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Apple Root CA - G3, downloaded from apple.com/certificateauthority and pinned.
const APPLE_ROOT = new X509Certificate(
  readFileSync(join(__dirname, "..", "certs", "AppleRootCA-G3.cer"))
);
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
  const intermediate = certFromX5cEntry(header.x5c[1]);

  // 1. Trust anchor: verify the intermediate chains up to OUR pinned Apple
  // Root CA - G3, using its public key — never by requiring the 3rd x5c
  // entry (if Apple even sends one) to be byte-identical to our pinned file.
  // This mirrors Apple's own SignedDataVerifier reference implementation,
  // which discards x5c's 3rd entry entirely and validates against a
  // separately-supplied, locally-trusted root list instead.
  if (!intermediate.checkIssued(APPLE_ROOT) || !intermediate.verify(APPLE_ROOT.publicKey)) {
    throw new Error("untrusted_root");
  }

  // 2. Leaf must be issued by the intermediate.
  if (!leaf.checkIssued(intermediate) || !leaf.verify(intermediate.publicKey)) {
    throw new Error("broken_chain");
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
