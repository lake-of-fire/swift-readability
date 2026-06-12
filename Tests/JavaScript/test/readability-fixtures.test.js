/* eslint-env node, mocha */

const fs = require("fs");
const path = require("path");
const { expect } = require("chai");
const { JSDOM, VirtualConsole } = require("jsdom");
const prettyPrint = require("js-beautify").html;
const xmlNameValidator = require("xml-name-validator").name;

const Readability = require("../../../Sources/SwiftReadability/Resources/Readability");
const isProbablyReaderable = require("../../../Sources/SwiftReadability/Resources/Readability-readerable");

const fixtureRoot = path.resolve(
  __dirname,
  "../../SwiftReadabilityTests/Fixtures/test-pages"
);
const manifestPath = path.resolve(
  __dirname,
  "../../SwiftReadabilityTests/Fixtures/readability-suite.json"
);
const quietVirtualConsole = new VirtualConsole();

function fixtureManifest() {
  return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
}

function selectedFixtureNames() {
  const manifest = fixtureManifest();
  const value = process.env.SWIFT_READABILITY_FIXTURES;
  if (!value && process.env.SWIFT_READABILITY_FIXTURE_REGEX) {
    return null;
  }
  if (!value) {
    const defaults = manifest.defaultFixtureSelection?.javascript;
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
  const manifest = fixtureManifest();
  return new Set(
    (manifest.knownFailures || [])
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

  return fs
    .readdirSync(fixtureRoot, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name)
    .filter(name => selected === null || selected.has(name))
    .filter(name => !regex || regex.test(name))
    .filter(name => !knownFailures.has(name))
    .sort()
    .map(name => {
      const dir = path.join(fixtureRoot, name);
      const sourcePath = path.join(dir, "source.html");
      const expectedPath = path.join(dir, "expected.html");
      const metadataPath = path.join(dir, "expected-metadata.json");
      if (!fs.existsSync(sourcePath)) {
        return null;
      }
      return {
        name,
        source: fs.readFileSync(sourcePath, "utf8").trim(),
        expectedHTML: fs.existsSync(expectedPath)
          ? fs.readFileSync(expectedPath, "utf8").trim()
          : null,
        expectedMetadata: fs.existsSync(metadataPath)
          ? JSON.parse(fs.readFileSync(metadataPath, "utf8"))
          : null,
        assertions: fixtureManifest().assertions?.[name] || null,
      };
    })
    .filter(Boolean);
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
    expect(nodeStr(actualNode)).to.equal(nodeStr(expectedNode));

    if (actualNode.nodeType === 3) {
      expect(htmlTransform(actualNode.textContent)).to.equal(
        htmlTransform(expectedNode.textContent)
      );
    } else if (actualNode.nodeType === 1) {
      expect(attributesForNode(actualNode)).to.deep.equal(
        attributesForNode(expectedNode)
      );
    }

    actualNode = inOrderIgnoreEmptyTextNodes(actualNode);
    expectedNode = inOrderIgnoreEmptyTextNodes(expectedNode);
  }
}

function expectOptionalEqual(actual, expected) {
  expect(actual ?? null).to.equal(expected ?? null);
}

describe("Readability.js fixture parity", function () {
  this.timeout(30000);

  for (const fixture of loadFixtures()) {
    it(`parses ${fixture.name}`, function () {
      const baseURL = fixtureManifest().baseURL || "http://fakehost/test/page.html";
      const dom = new JSDOM(fixture.source, {
        url: baseURL,
        virtualConsole: quietVirtualConsole,
      });

      if (fixture.expectedMetadata?.readerable != null) {
        expect(isProbablyReaderable(dom.window.document)).to.equal(
          fixture.expectedMetadata.readerable
        );
      }

      const result = new Readability(dom.window.document, {
        classesToPreserve: ["caption"],
      }).parse();

      expect(result).to.include.keys("content", "title", "excerpt", "byline");

      if (fixture.expectedMetadata) {
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

      if (fixture.assertions) {
        for (const excludedText of fixture.assertions.textExcludes || []) {
          expect(result.textContent).not.to.include(excludedText);
        }
        for (const excludedContent of fixture.assertions.contentExcludes || []) {
          expect(result.content).not.to.include(excludedContent);
        }
        for (const includedContent of fixture.assertions.contentIncludes || []) {
          expect(result.content).to.include(includedContent);
        }
      }

      if (fixture.expectedHTML) {
        expectDOMEqual(result.content, fixture.expectedHTML);
      }
    });
  }
});
