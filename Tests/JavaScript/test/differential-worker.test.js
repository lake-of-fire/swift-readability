/* eslint-env node */

const assert = require("node:assert/strict");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");

const harness = path.resolve(
  __dirname,
  "../differential/readability-differential.js"
);

function runWorker(payload) {
  return spawnSync(
    process.execPath,
    ["--max-old-space-size=512", harness, "--compare-batch"],
    {
      encoding: "utf8",
      input: JSON.stringify(payload),
      maxBuffer: 16 * 1024 * 1024,
    }
  );
}

test("the isolated differential worker reports a native mismatch", () => {
  const result = runWorker({ names: ["001"], actual: [{}] });
  assert.equal(result.status, 0, result.stderr);
  const failures = JSON.parse(result.stdout);
  assert.equal(failures.length, 1);
  assert.match(failures[0], /^001: parsed differs/);
});

test("the isolated differential worker fails closed for a malformed batch", () => {
  const result = runWorker({ names: ["001"], actual: [] });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Worker batch lengths differ/);
});
