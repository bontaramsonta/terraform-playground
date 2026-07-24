'use strict';

// Minimal in-process SFTP server used to drive the fallback lambda's host-key
// verification. It presents exactly the host key(s) it is given, accepts any
// password auth, and opens the SFTP subsystem. That's enough: host-key
// verification happens during the SSH handshake, before any file operation, so
// a resolved connect() proves the key was accepted and a rejected one proves it
// was denied.

const { Server, utils } = require('ssh2');

// keyType: 'rsa' | 'ed25519'. Returns { privateKey, opensshPublicLine }.
function generateHostKey(keyType) {
  const kp = keyType === 'rsa'
    ? utils.generateKeyPairSync('rsa', { bits: 2048 })
    : utils.generateKeyPairSync('ed25519');
  const parsed = utils.parseKey(kp.private);
  const opensshPublicLine = `${parsed.type} ${parsed.getPublicSSH().toString('base64')}`;
  return { privateKey: kp.private, opensshPublicLine };
}

// Start a server that presents `hostKey.privateKey`. Resolves with { port, close }.
function startServer(hostKey) {
  return new Promise((resolve) => {
    const server = new Server({ hostKeys: [hostKey.privateKey] }, (client) => {
      client.on('authentication', (ctx) => ctx.accept());
      client.on('ready', () => {
        client.on('session', (acceptSession) => {
          const session = acceptSession();
          session.on('sftp', (acceptSftp) => {
            const sftp = acceptSftp();
            // Answer the client's protocol requests so ssh2-sftp-client's
            // connect() settles. REALPATH is the first thing it asks for.
            sftp.on('REALPATH', (reqid) => {
              sftp.name(reqid, [{ filename: '/', longname: '/', attrs: {} }]);
            });
          });
        });
      });
      client.on('error', () => {});
    });
    server.listen(0, '127.0.0.1', () => resolve({
      port: server.address().port,
      close: () => new Promise((r) => server.close(r)),
    }));
  });
}

module.exports = { generateHostKey, startServer };
