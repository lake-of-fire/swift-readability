/* eslint-env node */

const assert = require("node:assert/strict");
const { test } = require("node:test");
const { assertDOMEqual } = require("../support/dom-comparator");

test("raw-input fixture comparison observes comments", () => {
  assert.throws(() => {
    assertDOMEqual(
      "<div><!-- retained --><p>Text</p></div>",
      "<div><p>Text</p></div>"
    );
  });
  assert.throws(() => {
    assertDOMEqual(
      "<div><!-- first --><p>Text</p></div>",
      "<div><!-- second --><p>Text</p></div>"
    );
  });
  assert.doesNotThrow(() => {
    assertDOMEqual(
      "<div><!-- retained --><p>Text</p></div>",
      "<div><!-- retained --><p>Text</p></div>"
    );
  });
});
