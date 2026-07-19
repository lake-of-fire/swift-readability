/* eslint-env node */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { JSDOM } = require("jsdom");

const cases = JSON.parse(
  fs.readFileSync(
    path.resolve(
      __dirname,
      "../../SwiftReadabilityTests/Fixtures/inline-style-cssom-cases.json"
    ),
    "utf8"
  )
);

for (const fixture of cases) {
  test(`pinned jsdom inline CSSOM: ${fixture.name}`, () => {
    const document = new JSDOM("<!doctype html><p></p>").window.document;
    const element = document.querySelector("p");
    element.setAttribute("style", fixture.style);

    assert.equal(element.style.display || null, fixture.display);
    assert.equal(element.style.visibility || null, fixture.visibility);
  });
}
