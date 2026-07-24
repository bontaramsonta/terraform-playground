'use strict';

// Test matrix proving how the SFTP fallback lambda verifies host keys that are
// passed in via SFTP_TRUSTED_HOST_KEYS, exactly like prod (Terraform joins the
// list, the lambda splits it). Each case starts a real ssh2 SFTP server that
// presents a chosen host key, sets the env var the way prod would, invokes the
// lambda handler, and checks whether the connection was ACCEPTED or DENIED.

const { handler } = require('./handler');
const { generateHostKey, startServer } = require('./sftp-server');

// Stable keypairs for the whole run.
const rsa = generateHostKey('rsa');        // an RSA host key (what the AWS Transfer connector uses)
const ed = generateHostKey('ed25519');     // an ed25519 host key (fallback-only in prod)
const stranger = generateHostKey('ed25519'); // a key we never trust

// Build the env var value the way Terraform's join() would, with a chosen delimiter.
function joinKeys(lines, delimiter) {
  return lines.join(delimiter);
}

async function attempt({ serverHostKey, trustedLines, buildDelimiter, splitDelimiter }) {
  const server = await startServer(serverHostKey);
  process.env.SFTP_ENDPOINT = `sftp://127.0.0.1:${server.port}`;
  process.env.SFTP_USERNAME = 'tester';
  process.env.SFTP_PASSWORD = 'irrelevant';
  process.env.SFTP_TRUSTED_HOST_KEYS = joinKeys(trustedLines, buildDelimiter);
  try {
    const res = await handler({}, { keyDelimiter: splitDelimiter });
    return { outcome: 'ACCEPTED', detail: res };
  } catch (err) {
    return { outcome: 'DENIED', detail: err.message };
  } finally {
    await server.close();
  }
}

const CASES = [
  {
    name: 'single ed25519 trusted, server presents ed25519',
    cfg: { serverHostKey: ed, trustedLines: [ed.opensshPublicLine], buildDelimiter: '\n', splitDelimiter: '\n' },
    expect: 'ACCEPTED',
    proves: 'baseline: one matching key works',
  },
  {
    name: 'merged [rsa, ed25519] newline-joined, server presents ed25519',
    cfg: { serverHostKey: ed, trustedLines: [rsa.opensshPublicLine, ed.opensshPublicLine], buildDelimiter: '\n', splitDelimiter: '\n' },
    expect: 'ACCEPTED',
    proves: 'MULTIPLE keys via \\n-joined env var parse correctly',
  },
  {
    name: 'merged [rsa, ed25519] newline-joined, server presents rsa',
    cfg: { serverHostKey: rsa, trustedLines: [rsa.opensshPublicLine, ed.opensshPublicLine], buildDelimiter: '\n', splitDelimiter: '\n' },
    expect: 'ACCEPTED',
    proves: 'the prod merge: connector RSA key is now trusted by the fallback too',
  },
  {
    name: 'only ed25519 trusted, server presents rsa  (pre-merge state)',
    cfg: { serverHostKey: rsa, trustedLines: [ed.opensshPublicLine], buildDelimiter: '\n', splitDelimiter: '\n' },
    expect: 'DENIED',
    proves: 'the latent bug the merge fixed: RSA-negotiating server would be rejected',
  },
  {
    name: 'server presents an untrusted key',
    cfg: { serverHostKey: stranger, trustedLines: [rsa.opensshPublicLine, ed.opensshPublicLine], buildDelimiter: '\n', splitDelimiter: '\n' },
    expect: 'DENIED',
    proves: 'fails closed: an unknown host key is rejected',
  },
  {
    name: 'merged [rsa, ed25519] COMMA-joined, prod \\n splitter, server presents ed25519',
    cfg: { serverHostKey: ed, trustedLines: [rsa.opensshPublicLine, ed.opensshPublicLine], buildDelimiter: ',', splitDelimiter: '\n' },
    expect: 'DENIED',
    proves: 'changing the join to comma WITHOUT changing the split breaks verification',
  },
  {
    name: 'merged [rsa, ed25519] COMMA-joined AND comma splitter, server presents ed25519',
    cfg: { serverHostKey: ed, trustedLines: [rsa.opensshPublicLine, ed.opensshPublicLine], buildDelimiter: ',', splitDelimiter: ',' },
    expect: 'ACCEPTED',
    proves: 'comma works too IF both sides agree - no advantage over \\n, just a non-idiomatic separator',
  },
];

async function main() {
  console.log('SFTP fallback lambda - host key verification matrix\n');
  let failures = 0;
  for (const c of CASES) {
    const { outcome, detail } = await attempt(c.cfg);
    const ok = outcome === c.expect;
    if (!ok) failures++;
    const mark = ok ? 'PASS' : 'FAIL';
    console.log(`[${mark}] ${outcome.padEnd(8)} (expected ${c.expect.padEnd(8)}) - ${c.name}`);
    console.log(`         ${c.proves}`);
    if (!ok) console.log(`         got detail: ${JSON.stringify(detail)}`);
    console.log('');
  }
  console.log(failures === 0
    ? 'All cases behaved as expected.'
    : `${failures} case(s) did not match expectation.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => { console.error(err); process.exit(1); });
