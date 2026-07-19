/* eslint-env node */

const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");
const { describe, it } = require("node:test");
const { JSDOM, VirtualConsole } = require("jsdom");
const prettyPrint = require("js-beautify").html;
const xmlNameValidator = require("xml-name-validator").name;

const readabilityPath = process.env.READABILITY_JS_PATH
  ? path.resolve(process.env.READABILITY_JS_PATH)
  : path.resolve(
      __dirname,
      "../../../Sources/SwiftReadabilityJavaScriptReference/Resources/Readability"
    );
const readerablePath = process.env.READERABLE_JS_PATH
  ? path.resolve(process.env.READERABLE_JS_PATH)
  : path.resolve(
      __dirname,
      "../../../Sources/SwiftReadabilityJavaScriptReference/Resources/Readability-readerable"
    );
const Readability = require(readabilityPath);
const isProbablyReaderable = require(readerablePath);

const fixtureRoot = path.resolve(
  __dirname,
  "../../SwiftReadabilityTests/Fixtures/test-pages"
);
const manifestPath = path.resolve(
  __dirname,
  "../../SwiftReadabilityTests/Fixtures/readability-suite.json"
);
const quietVirtualConsole = new VirtualConsole();
// Load once and fail during test discovery if the shared contract is malformed.
// A parity run with no valid manifest must never be reported as green.
const fixtureManifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

function selectedFixtureNames() {
  const value = process.env.SWIFT_READABILITY_FIXTURES;
  if (!value && process.env.SWIFT_READABILITY_FIXTURE_REGEX) {
    return null;
  }
  if (!value) {
    const defaults = fixtureManifest.defaultFixtureSelection?.javascript;
    return defaults?.length ? new Set(defaults) : null;
  }
  return new Set(
    value
      .split(",")
      .map(name => name.trim())
      .filter(Boolean)
  );
}

function knownFailureNames() {
  if (process.env.SWIFT_READABILITY_INCLUDE_KNOWN_FAILURES) {
    return new Set();
  }
  return new Set(
    (fixtureManifest.knownFailures || [])
      .filter(failure =>
        failure.runners?.includes("javascript") || failure.runners?.includes("*")
      )
      .map(failure => failure.name)
  );
}

function loadFixtures() {
  const selected = selectedFixtureNames();
  const knownFailures = knownFailureNames();
  const regex = process.env.SWIFT_READABILITY_FIXTURE_REGEX
    ? new RegExp(process.env.SWIFT_READABILITY_FIXTURE_REGEX)
    : null;

  const availableNames = fs
    .readdirSync(fixtureRoot, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name);
  assert.ok(availableNames.length > 0, `No fixture directories found at ${fixtureRoot}`);

  if (selected !== null) {
    const unknownNames = [...selected].filter(name => !availableNames.includes(name));
    assert.deepEqual(unknownNames, [], `Unknown fixture selection: ${unknownNames.join(", ")}`);
  }

  const unknownAssertions = Object.keys(fixtureManifest.assertions || {})
    .filter(name => !availableNames.includes(name));
  assert.deepEqual(
    unknownAssertions,
    [],
    `Manifest assertions reference unknown fixtures: ${unknownAssertions.join(", ")}`
  );

  const extensionProfiles = fixtureManifest.extensionProfiles || {};
  const unknownExtensionProfiles = Object.keys(extensionProfiles)
    .filter(name => !availableNames.includes(name));
  assert.deepEqual(
    unknownExtensionProfiles,
    [],
    `Manifest extension profiles reference unknown fixtures: ${unknownExtensionProfiles.join(", ")}`
  );
  const unsupportedExtensionProfiles = Object.entries(extensionProfiles)
    .filter(([, profile]) => profile !== "publisherAdaptations");
  assert.deepEqual(
    unsupportedExtensionProfiles,
    [],
    `Unsupported extension profiles: ${unsupportedExtensionProfiles.map(([name, profile]) => `${name}=${profile}`).join(", ")}`
  );

  const fixtures = availableNames
    .filter(name => selected === null || selected.has(name))
    .filter(name => !regex || regex.test(name))
    .filter(name => !knownFailures.has(name))
    .sort()
    .map(name => {
      const dir = path.join(fixtureRoot, name);
      const sourcePath = path.join(dir, "source.html");
      const expectedPath = path.join(dir, "expected.html");
      const metadataPath = path.join(dir, "expected-metadata.json");
      assert.ok(fs.existsSync(sourcePath), `Missing source.html for fixture ${name}`);
      return {
        name,
        source: fs.readFileSync(sourcePath, "utf8").trim(),
        expectedHTML: fs.existsSync(expectedPath)
          ? fs.readFileSync(expectedPath, "utf8").trim()
          : null,
        expectedMetadata: fs.existsSync(metadataPath)
          ? JSON.parse(fs.readFileSync(metadataPath, "utf8"))
          : null,
        assertions: fixtureManifest.assertions?.[name] || null,
        extensionProfile: extensionProfiles[name] || null,
      };
    });

  assert.ok(fixtures.length > 0, "Fixture selection matched zero runnable JavaScript fixtures");
  return fixtures;
}

function prettyHTML(html) {
  return prettyPrint(html, {
    indent_size: 4,
    indent_char: " ",
    indent_level: 0,
    indent_with_tabs: false,
    preserve_newlines: false,
    break_chained_methods: false,
    eval_code: false,
    unescape_strings: false,
    wrap_line_length: 0,
    wrap_attributes: "auto",
    wrap_attributes_indent_size: 4,
  });
}

function htmlTransform(value) {
  return value.replace(/\s+/g, " ");
}

function nodeStr(node) {
  if (!node) {
    return "(no node)";
  }
  if (node.nodeType === 3) {
    return `#text(${htmlTransform(node.textContent)})`;
  }
  if (node.nodeType !== 1) {
    return `some other node type: ${node.nodeType}`;
  }
  let result = node.localName;
  if (node.id) {
    result += `#${node.id}`;
  }
  if (node.className) {
    result += `.(${node.className})`;
  }
  return result;
}

function inOrderTraverse(node) {
  if (node.firstChild) {
    return node.firstChild;
  }
  while (node && !node.nextSibling) {
    node = node.parentNode;
  }
  return node ? node.nextSibling : null;
}

function inOrderIgnoreEmptyTextNodes(node) {
  do {
    node = inOrderTraverse(node);
  } while (
    node &&
    ((node.nodeType === 3 && !node.textContent.trim()) || node.nodeType === 8)
  );
  return node;
}

function attributesForNode(node) {
  return Array.from(node.attributes)
    .filter(attr => xmlNameValidator(attr.name))
    .map(attr => `${attr.name}=${attr.value}`);
}

function expectDOMEqual(actualHTML, expectedHTML) {
  const actualDOM = new JSDOM(prettyHTML(actualHTML), {
    virtualConsole: quietVirtualConsole,
  }).window.document;
  const expectedDOM = new JSDOM(prettyHTML(expectedHTML), {
    virtualConsole: quietVirtualConsole,
  }).window.document;
  let actualNode = actualDOM.documentElement || actualDOM.childNodes[0];
  let expectedNode = expectedDOM.documentElement || expectedDOM.childNodes[0];

  while (actualNode || expectedNode) {
    assert.equal(nodeStr(actualNode), nodeStr(expectedNode));
    assert.ok(actualNode && expectedNode, "DOM trees have different lengths");

    if (actualNode.nodeType === 3) {
      assert.equal(
        htmlTransform(actualNode.textContent),
        htmlTransform(expectedNode.textContent)
      );
    } else if (actualNode.nodeType === 1) {
      assert.deepEqual(
        attributesForNode(actualNode),
        attributesForNode(expectedNode)
      );
    }

    actualNode = inOrderIgnoreEmptyTextNodes(actualNode);
    expectedNode = inOrderIgnoreEmptyTextNodes(expectedNode);
  }
}

function expectOptionalEqual(actual, expected) {
  assert.equal(actual ?? null, expected ?? null);
}

function removeCommentNodesRecursively(node) {
  for (let index = node.childNodes.length - 1; index >= 0; index -= 1) {
    const child = node.childNodes[index];
    if (child.nodeType === child.COMMENT_NODE) {
      node.removeChild(child);
    } else if (child.nodeType === child.ELEMENT_NODE) {
      removeCommentNodesRecursively(child);
    }
  }
}

// Resolve the corpus at module load so infrastructure errors set a nonzero
// process status instead of becoming a zero-test suite that npm reports green.
const fixtures = loadFixtures();

describe("Readability.js fixture parity", { timeout: 30000 }, function () {
  for (const fixture of fixtures) {
    it(`parses ${fixture.name}`, function () {
      const baseURL = fixtureManifest.baseURL || "http://fakehost/test/page.html";
      const dom = new JSDOM(fixture.source, {
        url: baseURL,
        virtualConsole: quietVirtualConsole,
      });
      removeCommentNodesRecursively(dom.window.document);

      if (!fixture.extensionProfile && fixture.expectedMetadata?.readerable != null) {
        assert.equal(
          isProbablyReaderable(dom.window.document),
          fixture.expectedMetadata.readerable
        );
      }

      const result = new Readability(dom.window.document, {
        classesToPreserve: ["caption"],
      }).parse();
      assert.ok(result, `${fixture.name} should produce an article`);

      for (const key of ["content", "title", "excerpt", "byline"]) {
        assert.ok(Object.prototype.hasOwnProperty.call(result, key), `Missing ${key}`);
      }

      // Publisher-extension fixtures intentionally describe the native opt-in
      // profile, not Mozilla's output. They still exercise the unmodified oracle
      // for parse safety here and receive exact field coverage in the differential suite.
      if (!fixture.extensionProfile && fixture.expectedMetadata) {
        expectOptionalEqual(result.title, fixture.expectedMetadata.title);
        expectOptionalEqual(result.byline, fixture.expectedMetadata.byline);
        expectOptionalEqual(result.dir, fixture.expectedMetadata.dir);
        expectOptionalEqual(result.lang, fixture.expectedMetadata.lang);
        expectOptionalEqual(result.excerpt, fixture.expectedMetadata.excerpt);
        expectOptionalEqual(result.siteName, fixture.expectedMetadata.siteName);
        expectOptionalEqual(
          result.publishedTime,
          fixture.expectedMetadata.publishedTime
        );
      }

      if (!fixture.extensionProfile && fixture.assertions) {
        for (const excludedText of fixture.assertions.textExcludes || []) {
          assert.ok(
            !result.textContent.includes(excludedText),
            `${fixture.name} should not include text: ${excludedText}`
          );
        }
        for (const excludedContent of fixture.assertions.contentExcludes || []) {
          assert.ok(
            !result.content.includes(excludedContent),
            `${fixture.name} should not include content: ${excludedContent}`
          );
        }
        for (const includedContent of fixture.assertions.contentIncludes || []) {
          assert.ok(
            result.content.includes(includedContent),
            `${fixture.name} should include content: ${includedContent}`
          );
        }
      }

      if (!fixture.extensionProfile && fixture.expectedHTML) {
        expectDOMEqual(result.content, fixture.expectedHTML);
      }
    });
  }
});
