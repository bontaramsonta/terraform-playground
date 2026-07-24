'use strict';

// Feeds the lambda's EXACT parsing code (from handler.js / prod index.js) the
// EXACT SFTP_TRUSTED_HOST_KEYS value observed in the AWS console, plus the same
// value with the newline restored, and checks whether each real prod host key
// would be accepted. No live server needed: the verifier keys off
// base64(rawKey), and for a real host key that base64 IS the public-key body,
// so we can drive the verifier directly with the real key material.

// --- the lambda's verifier, verbatim ---
function makeHostVerifier(trustedHostKeys) {
  const trusted = new Set(
    trustedHostKeys.map((line) => line.trim().split(/\s+/)[1]).filter(Boolean)
  );
  return { verify: (rawKey) => trusted.has(Buffer.from(rawKey).toString('base64')), trusted };
}
function parseEnv(value, delimiter = '\n') {
  return value.split(delimiter).map((l) => l.trim()).filter(Boolean);
}

// --- real prod key bodies (the base64 field of each authorized key line) ---
const RSA_BODY = 'AAAAB3NzaC1yc2EAAAADAQABAAABAQClFxX2pKEQ7HDwVLc5epLuMYgqmoNQMZapQgTTSpP+Y8rUhgfJ6mvdoKo9m2KCzfZposg+Lt0C1R6uaAegxG7vB61VFoIqfI+QLzRQmUssDsZjKB6aRpQ5+wTn0aDvWoGDV6ZtsJiW3UUWAKFKohHQwrDAQyP2JXhqiyacotmEH+gI8h8ZHht80lnS0wZQqyqpaoHVriT0aVCM1PM6xnejdiK8/czjoVbbslXozfnWRjKp8ZNxSvzfLoi1gDHApKvB36bB5Pz5+ef76jB7JI1lrYHUX8r7djxKbgumot075XhKMwKjKTtvrywqIjmjDfg1YHhw1j/YipcQVCmz3raV';
const ED_BODY = 'AAAAC3NzaC1lZDI1NTE5AAAAILRgjQ8HItDOZm7SStUEh9pviioZRY/NeNkrpaCGpReL';

// The server presents ONE key per connection; base64(rawKey) === that key's body.
const rsaRawKey = Buffer.from(RSA_BODY, 'base64');
const edRawKey = Buffer.from(ED_BODY, 'base64');

// --- the two candidate env var values ---
// (A) exactly as copied from the AWS console - keys concatenated, no separator.
const CONSOLE_VALUE =
  'ssh-rsa ' + RSA_BODY + 'ssh-ed25519 ' + ED_BODY;
// (B) what Terraform join("\n", ...) actually stores - one key per line.
const NEWLINE_VALUE =
  'ssh-rsa ' + RSA_BODY + '\n' + 'ssh-ed25519 ' + ED_BODY;

function report(label, value, delimiter) {
  const lines = parseEnv(value, delimiter);
  const { verify, trusted } = makeHostVerifier(lines);
  const rsaOk = verify(rsaRawKey);
  const edOk = verify(edRawKey);
  const connects = rsaOk || edOk; // server negotiates one; either match = success
  console.log(`\n### ${label}`);
  console.log(`  split('${delimiter === '\n' ? '\\n' : delimiter}') -> ${lines.length} line(s)`);
  console.log(`  trusted set (${trusted.size}): ${[...trusted].map((t) => t.slice(0, 24) + '...').join('  |  ')}`);
  console.log(`  accepts real RSA host key?     ${rsaOk}`);
  console.log(`  accepts real ed25519 host key? ${edOk}`);
  console.log(`  => lambda ${connects ? 'CONNECTS' : 'FAILS (denies every host key)'}`);
}

console.log('Does the SFTP fallback lambda accept the real prod host keys?');
report('AWS console value (keys concatenated, no separator)', CONSOLE_VALUE, '\n');
report('Terraform-stored value (join with \\n)', NEWLINE_VALUE, '\n');
