import { readFile, writeFile } from "node:fs/promises";
import { faker } from "@faker-js/faker";
import { SyncRedactor } from "redact-pii";

const redactor = new SyncRedactor();

const SAVE_PREFIX = "";
const TIME = new Date().toISOString();
const USE_SAVED = "";
const URL = process.env.FN_URL;

async function gen_logs(numEntries) {
  const logs = [];
  for (let i = 0; i < numEntries; i++) {
    const logEntry = {
      timestamp: Date.now() + i,
      name: faker.person.fullName(),
      dump: [
        faker.food.adjective(),
        faker.food.description(),
        faker.person.middleName(),
        faker.person.lastName(), //!
        faker.food.ethnicCategory(),
        faker.food.dish(),
        faker.finance.accountNumber(), //!
        faker.finance.creditCardNumber(), //!
        faker.hacker.noun(),
      ].join(" "),
      address: [
        faker.location.buildingNumber(),
        faker.location.streetAddress(),
        faker.location.city(),
        faker.location.state(),
        faker.location.country(),
        faker.location.zipCode(),
      ].join(", "), //!
      additionalInfo: faker.lorem.sentence(),
      info: [
        faker.lorem.words({ min: 3, max: 4 }),
        faker.helpers.arrayElement([
          ("amalgamrx", "amalgam", "amalgam-rx", "amalgamorg"), //! custom redaction
        ]),
        faker.lorem.words({ min: 3, max: 4 }),
      ].join(" "),
    };
    logs.push(logEntry);
  }
  // save
  await writeFile(`./logs/${TIME}.json`, JSON.stringify(logs, null, 2));
  return logs;
}

async function run() {
  let logs = null;
  if (USE_SAVED) {
    logs = JSON.parse(
      await readFile(`./logs/${USE_SAVED}`, { encoding: "utf-8" }),
    );
  } else {
    logs = await gen_logs(10);
  }
  console.log(logs);
  // call the lambda
  const response = await fetch(URL, {
    method: "POST",
    body: JSON.stringify(logs),
    headers: [["Content-Type", "Application/json"]],
  });
  if (!response.ok) console.log("response failed", response);
  const response_body = await response.json();
  // output the response
  console.log({ response_body });
  // redact using redact-pii
  const redactedText = redactor.redact(JSON.stringify(logs, null, 2));
  // save redact-pii_
  await writeFile(`./logs/${TIME}_redact-pii.json`, redactedText);
}
run();
