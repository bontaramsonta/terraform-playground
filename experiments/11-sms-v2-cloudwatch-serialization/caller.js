// Drives the experiment: sends one success + one failure SMS through the
// simulator, then reads the RAW CloudWatch log lines so we can see the exact
// serialization (compact vs pretty, bare vs enveloped) and the eventType the
// failure magic number actually emits.
//
//   AWS_PROFILE=sourav node caller.js
//
// Reads the config-set / log-group / origination values from `terraform output`
// so it can't drift from what was applied.

import { execSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import {
  PinpointSMSVoiceV2Client,
  SendTextMessageCommand,
} from "@aws-sdk/client-pinpoint-sms-voice-v2";
import {
  CloudWatchLogsClient,
  FilterLogEventsCommand,
} from "@aws-sdk/client-cloudwatch-logs";

const REGION = "us-east-1";

function tf(output) {
  return execSync(`terraform output -raw ${output}`, { encoding: "utf-8" }).trim();
}

const logGroupName = tf("log_group_name");
const configurationSetName = tf("configuration_set_name");
const originationId = tf("origination_number_id");
const successTo = tf("sim_success_destination");
const failureTo = tf("sim_failure_destination");
const canaryPattern = tf("json_canary_filter_pattern");

const sms = new PinpointSMSVoiceV2Client({ region: REGION });
const logs = new CloudWatchLogsClient({ region: REGION });

async function send(destination, label) {
  const res = await sms.send(
    new SendTextMessageCommand({
      DestinationPhoneNumber: destination,
      OriginationIdentity: originationId,
      ConfigurationSetName: configurationSetName,
      MessageBody: `play sms-v2-serialization experiment (${label})`,
    }),
  );
  console.log(`sent ${label} -> ${destination}  MessageId=${res.MessageId}`);
}

async function run() {
  console.log({ logGroupName, configurationSetName, originationId, successTo, failureTo });
  console.log("canary filter pattern:", canaryPattern, "\n");

  await send(successTo, "SUCCESS");
  await send(failureTo, "FAILURE");

  // Events take a little while to land + the log stream to be created.
  console.log("\nwaiting 60s for events to reach CloudWatch...\n");
  await sleep(60_000);

  const start = Date.now() - 10 * 60 * 1000;
  const { events = [] } = await logs.send(
    new FilterLogEventsCommand({ logGroupName, startTime: start }),
  );

  if (events.length === 0) {
    console.log("NO log events yet — wait longer and re-run the read, or the");
    console.log("event destination isn't wired. Check the config set in console.");
    return;
  }

  console.log(`--- ${events.length} raw log event(s) ---\n`);
  for (const e of events) {
    // JSON.stringify of the raw string reveals exactly whether it is compact or
    // pretty and whether newlines are embedded — do NOT pretty-print it here.
    console.log("RAW:", JSON.stringify(e.message));
    try {
      const parsed = JSON.parse(e.message);
      // Is eventType at the top level (so $.eventType lands) or nested?
      console.log("  top-level eventType:", parsed.eventType ?? "(absent — check for envelope)");
      console.log("  isFinal:", parsed.isFinal, " messageStatus:", parsed.messageStatus);
    } catch {
      console.log("  (not parseable as a single JSON object)");
    }
    console.log("");
  }

  console.log("Next: check the LogMetrics/SMS_Failure_JsonCanary metric in");
  console.log("CloudWatch (us-east-1) — a datapoint of 1 means the ticket-04");
  console.log("filter matched the failure line and $.eventType lands for real.");
}

run();
