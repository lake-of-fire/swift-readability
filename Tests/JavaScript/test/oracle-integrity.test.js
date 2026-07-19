/* eslint-env node */

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const resources = path.resolve(
  __dirname,
  "../../../Sources/SwiftReadabilityJavaScriptReference/Resources"
);

// These are the byte-for-byte upstream files from mozilla/readability at
// ab4027a. A changed hash means the behavioral oracle was modified and must be
// reviewed as an upstream-version change, never as an ordinary fixture fix.
const expectedSHA256 = {
  "Readability.js": "e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed",
  "Readability-readerable.js": "e73600367067be2da322c0f26be9c4ec7759cd01b630dbb57278c326e5b5aba8",
};

for (const [name, expected] of Object.entries(expectedSHA256)) {
  test(`${name} is the unmodified Mozilla ab4027a oracle`, () => {
    const bytes = fs.readFileSync(path.join(resources, name));
    const actual = crypto.createHash("sha256").update(bytes).digest("hex");
    assert.equal(actual, expected);
  });
}
