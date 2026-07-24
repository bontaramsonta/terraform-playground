'use strict';

// Faithful copy of the host-key handling in the avhana-etl SFTP fallback lambda
// (infra-setup/Application/sftp-lambda/index.js). Only S3/Secrets Manager are
// stripped out - everything about how SFTP_TRUSTED_HOST_KEYS is parsed and how
// the ssh2 client is created is identical to prod, so this experiment exercises
// the real verification path.

const SftpClient = require('ssh2-sftp-client');

// Trusted keys are OpenSSH public key lines ("ssh-ed25519 AAAA..."); the base64
// body is the same wire-format blob ssh2 passes to hostVerifier.
function makeHostVerifier(trustedHostKeys) {
  const trusted = new Set(
    trustedHostKeys.map((line) => line.trim().split(/\s+/)[1]).filter(Boolean)
  );
  return (rawKey) => trusted.has(Buffer.from(rawKey).toString('base64'));
}

// The prod lambda splits the env var on "\n". The delimiter is injectable here
// ONLY so the experiment can prove what happens when the producer (Terraform
// join) and consumer (this split) disagree. Prod hardcodes "\n".
exports.handler = async (event, { keyDelimiter = '\n' } = {}) => {
  const endpoint = process.env.SFTP_ENDPOINT;
  const username = process.env.SFTP_USERNAME;
  const password = process.env.SFTP_PASSWORD;

  const trustedHostKeys = (process.env.SFTP_TRUSTED_HOST_KEYS || '')
    .split(keyDelimiter)
    .map((line) => line.trim())
    .filter(Boolean);
  if (trustedHostKeys.length === 0) {
    throw new Error('No trusted host key pinned in SFTP_TRUSTED_HOST_KEYS - refusing to connect');
  }

  const [hostname, port] = endpoint.replace(/^sftp:\/\//, '').split(':');
  const sftp = new SftpClient();
  try {
    await sftp.connect({
      host: hostname,
      port: port ? Number(port) : 22,
      username,
      ...(password ? { password } : {}),
      readyTimeout: 10000,
      hostVerifier: makeHostVerifier(trustedHostKeys),
    });
    // Reaching here means the host key passed verification, auth succeeded, and
    // the SFTP subsystem opened - the full handshake the fallback relies on.
    return { status: 'CONNECTED', trustedCount: trustedHostKeys.length };
  } finally {
    await sftp.end().catch(() => {});
  }
};
