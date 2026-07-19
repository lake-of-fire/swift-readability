/* eslint-env node */

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { JSDOM, VirtualConsole } = require("jsdom");
const { assertDOMEqual } = require("../support/dom-comparator");

const repositoryRoot = path.resolve(__dirname, "../../..");
const fixtureRoot = path.join(
  repositoryRoot,
  "Tests/SwiftReadabilityTests/Fixtures/test-pages"
);
const manifestPath = path.join(
  repositoryRoot,
  "Tests/SwiftReadabilityTests/Fixtures/readability-suite.json"
);
const readabilityPath = path.join(
  repositoryRoot,
  "Sources/SwiftReadabilityJavaScriptReference/Resources/Readability.js"
);
const expectedOracleSHA256 =
  "e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed";
const rawInputSnapshotName = "expected-raw-input.html";
const quietVirtualConsole = new VirtualConsole();

function verifyOracle() {
  const bytes = fs.readFileSync(readabilityPath);
  const actual = crypto.createHash("sha256").update(bytes).digest("hex");
  assert.equal(
    actual,
    expectedOracleSHA256,
    "Raw-input snapshots may only be generated with unmodified Mozilla Readability ab4027a"
  );
}

function removeCommentsForLegacyFixtureInput(document) {
  const walker = document.createTreeWalker(
    document,
    document.defaultView.NodeFilter.SHOW_COMMENT
  );
  const comments = [];
  while (walker.nextNode()) {
    comments.push(walker.currentNode);
  }
  for (const comment of comments) {
    comment.remove();
  }
}

function extractWithPinnedOracle({ Readability, source, baseURL, removeComments }) {
  const dom = new JSDOM(source, {
    url: baseURL,
    virtualConsole: quietVirtualConsole,
  });
  try {
    if (removeComments) {
      removeCommentsForLegacyFixtureInput(dom.window.document);
    }
    return new Readability(dom.window.document, {
      classesToPreserve: ["caption"],
    }).parse();
  } finally {
    dom.window.close();
  }
}

function generateExpectedSnapshots({ write }) {
  verifyOracle();
  const Readability = require(readabilityPath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const extensionProfiles = manifest.extensionProfiles || {};
  const baseURL = manifest.baseURL || "http://fakehost/test/page.html";
  const fixtureNames = fs
    .readdirSync(fixtureRoot, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name)
    .sort();

  assert.ok(fixtureNames.length > 0, `No fixtures found at ${fixtureRoot}`);
  const requiredOverlays = new Map();

  for (const name of fixtureNames) {
    const directory = path.join(fixtureRoot, name);
    const sourcePath = path.join(directory, "source.html");
    const legacyPath = path.join(directory, "expected.html");
    const overlayPath = path.join(directory, rawInputSnapshotName);

    if (extensionProfiles[name] || !fs.existsSync(legacyPath)) {
      assert.ok(
        !fs.existsSync(overlayPath),
        `${name}: raw Mozilla overlay is invalid for an extension fixture or a fixture without expected.html`
      );
      continue;
    }

    const source = fs.readFileSync(sourcePath, "utf8");
    const legacyExpected = fs.readFileSync(legacyPath, "utf8");
    const result = extractWithPinnedOracle({
      Readability,
      source,
      baseURL,
      removeComments: false,
    });
    assert.ok(result, `${name}: pinned Mozilla oracle did not return an article`);

    let matchesLegacy = true;
    try {
      assertDOMEqual(result.content, legacyExpected, `${name} legacy snapshot`);
    } catch {
      matchesLegacy = false;
    }

    if (matchesLegacy) {
      assert.ok(
        !fs.existsSync(overlayPath),
        `${name}: stale ${rawInputSnapshotName}; raw output already matches expected.html`
      );
      continue;
    }

    // Mozilla's own JSDOM fixture runner removes source comments before
    // extraction. Reproduce that exact preprocessing and prove the frozen
    // expected.html is still authoritative under its historical policy before
    // accepting a raw-input overlay. Comments can affect sibling traversal and
    // therefore extraction structure, so deleting them only from the finished
    // result would not be an equivalent proof.
    const legacyResult = extractWithPinnedOracle({
      Readability,
      source,
      baseURL,
      removeComments: true,
    });
    assert.ok(legacyResult, `${name}: legacy Mozilla fixture policy returned no article`);
    assertDOMEqual(
      legacyResult.content,
      legacyExpected,
      `${name}: expected.html does not match Mozilla's comment-free fixture policy`
    );

    requiredOverlays.set(name, {
      path: overlayPath,
      content: `${result.content}\n`,
    });
  }

  // Validate the complete corpus before writing anything. A newly discovered
  // non-comment divergence must not leave a half-updated snapshot set behind.
  assert.ok(requiredOverlays.size > 0, "Raw-input overlay generation selected zero fixtures");
  for (const [name, overlay] of requiredOverlays) {
    if (write) {
      if (!fs.existsSync(overlay.path) || fs.readFileSync(overlay.path, "utf8") !== overlay.content) {
        fs.writeFileSync(overlay.path, overlay.content);
      }
    } else {
      assert.ok(
        fs.existsSync(overlay.path),
        `${name}: missing generated ${rawInputSnapshotName}; run npm run fixtures:write-raw-input`
      );
      assert.equal(
        fs.readFileSync(overlay.path, "utf8"),
        overlay.content,
        `${name}: stale ${rawInputSnapshotName}; run npm run fixtures:write-raw-input`
      );
    }
  }

  return [...requiredOverlays.keys()];
}

function parseMode(arguments_) {
  assert.deepEqual(
    arguments_.filter(argument => argument !== "--write" && argument !== "--check"),
    [],
    "Usage: node tools/raw-input-fixture-snapshots.js [--check|--write]"
  );
  assert.ok(
    !(arguments_.includes("--write") && arguments_.includes("--check")),
    "Choose either --check or --write"
  );
  return { write: arguments_.includes("--write") };
}

if (require.main === module) {
  const names = generateExpectedSnapshots(parseMode(process.argv.slice(2)));
  const mode = process.argv.includes("--write") ? "wrote" : "verified";
  process.stdout.write(
    `Raw-input fixture snapshots: ${mode} ${names.length} comment-bearing overlays.\n`
  );
}

module.exports = {
  generateExpectedSnapshots,
};
