/* eslint-env node */

const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const { JSDOM, VirtualConsole } = require("jsdom");
const xmlNameValidator = require("xml-name-validator").name;

const repositoryRoot = path.resolve(__dirname, "../../..");
const fixtureRoot = path.join(
  repositoryRoot,
  "Tests/SwiftReadabilityTests/Fixtures/test-pages"
);
const manifest = JSON.parse(
  fs.readFileSync(
    path.join(repositoryRoot, "Tests/SwiftReadabilityTests/Fixtures/readability-suite.json"),
    "utf8"
  )
);
const Readability = require(
  path.join(
    repositoryRoot,
    "Sources/SwiftReadabilityJavaScriptReference/Resources/Readability"
  )
);
const isProbablyReaderable = require(
  path.join(
    repositoryRoot,
    "Sources/SwiftReadabilityJavaScriptReference/Resources/Readability-readerable"
  )
);
const quietVirtualConsole = new VirtualConsole();

function fixtureNames() {
  const filter = process.env.SWIFT_READABILITY_DIFFERENTIAL_FILTER;
  const names = fs
    .readdirSync(fixtureRoot, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name)
    .filter(name => !filter || name.includes(filter))
    .sort();
  assert.ok(names.length > 0, "Differential corpus is empty");
  return names;
}

function removeComments(node) {
  for (const child of [...node.childNodes]) {
    if (child.nodeType === child.COMMENT_NODE) {
      child.remove();
    } else {
      removeComments(child);
    }
  }
}

function javascriptResults(names) {
  return names.map(name => {
    const source = fs.readFileSync(path.join(fixtureRoot, name, "source.html"), "utf8").trim();
    const dom = new JSDOM(source, {
      url: manifest.baseURL || "http://fakehost/test/page.html",
      virtualConsole: quietVirtualConsole,
    });
    removeComments(dom.window.document);
    const readerable = isProbablyReaderable(dom.window.document);
    const result = new Readability(dom.window.document, {
      classesToPreserve: ["caption"],
    }).parse();
    return {
      name,
      parsed: result !== null,
      readerable,
      title: result?.title ?? null,
      byline: result?.byline ?? null,
      direction: result?.dir ?? null,
      language: result?.lang ?? null,
      excerpt: result?.excerpt ?? null,
      siteName: result?.siteName ?? null,
      publishedTime: result?.publishedTime ?? null,
      content: result?.content ?? null,
      textContent: result?.textContent?.replace(/\r\n/g, "\n") ?? null,
      length: result?.length ?? null,
    };
  });
}

function swiftResults() {
  const arguments = [
    "run", "--disable-sandbox", "-c", "release", "SwiftReadabilityContract",
    "--fixtures", fixtureRoot,
  ];
  if (process.env.SWIFT_READABILITY_DIFFERENTIAL_FILTER) {
    arguments.push("--filter", process.env.SWIFT_READABILITY_DIFFERENTIAL_FILTER);
  }
  const command = spawnSync(
    "swift",
    arguments,
    {
      cwd: repositoryRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        CLANG_MODULE_CACHE_PATH:
          process.env.CLANG_MODULE_CACHE_PATH || path.join(os.tmpdir(), "swift-readability-differential-clang"),
        SWIFTPM_MODULECACHE_OVERRIDE:
          process.env.SWIFTPM_MODULECACHE_OVERRIDE || path.join(os.tmpdir(), "swift-readability-differential-spm"),
      },
      maxBuffer: 128 * 1024 * 1024,
    }
  );
  if (command.status !== 0) {
    throw new Error(`Native contract runner failed:\n${command.stderr}`);
  }
  return JSON.parse(command.stdout);
}

function canonicalDOM(html) {
  if (html === null) return null;
  const document = new JSDOM(html, { virtualConsole: quietVirtualConsole }).window.document;
  const records = [];
  const booleanAttributes = new Set([
    "allowfullscreen", "async", "autofocus", "autoplay", "checked", "compact",
    "controls", "declare", "default", "defaultchecked", "defaultmuted",
    "defaultselected", "defer", "disabled", "enabled", "formnovalidate", "hidden",
    "indeterminate", "inert", "ismap", "itemscope", "loop", "multiple", "muted",
    "nohref", "nomodule", "noresize", "noshade", "novalidate", "nowrap", "open",
    "pauseonexit", "readonly", "required", "reversed", "scoped", "seamless",
    "selected", "sortable", "truespeed", "typemustmatch",
  ]);

  function visit(node) {
    if (node.nodeType === node.COMMENT_NODE) return;
    if (node.nodeType === node.TEXT_NODE) {
      let text = node.textContent.replace(/\s+/g, " ");
      if (!text.trim()) return;
      if (!node.nextSibling) text = text.replace(/\s+$/, "");
      records.push(["text", text]);
      return;
    }
    if (node.nodeType === node.ELEMENT_NODE) {
      const attributes = [...node.attributes]
        .filter(attribute => xmlNameValidator(attribute.name))
        .map(attribute =>
          `${attribute.name}=${booleanAttributes.has(attribute.name.toLowerCase()) ? attribute.name : attribute.value}`
        )
        .sort();
      records.push(["start", node.localName, attributes]);
      for (const child of node.childNodes) visit(child);
      records.push(["end", node.localName]);
      return;
    }
    for (const child of node.childNodes || []) visit(child);
  }

  for (const child of document.body.childNodes) visit(child);
  return records;
}

function compare() {
  const names = fixtureNames();
  const javascript = javascriptResults(names);
  const swift = swiftResults();
  assert.deepEqual(swift.map(result => result.name), names, "Native fixture order differs");

  const failures = [];
  const scalarFields = [
    "parsed",
    "readerable",
    "title",
    "byline",
    "direction",
    "language",
    "excerpt",
    "siteName",
    "publishedTime",
    "textContent",
    "length",
  ];

  for (let index = 0; index < names.length; index += 1) {
    const expected = javascript[index];
    const actual = swift[index];
    try {
      for (const field of scalarFields) {
        assert.deepEqual(actual[field] ?? null, expected[field] ?? null, `${field} differs`);
      }
      assert.deepEqual(canonicalDOM(actual.content), canonicalDOM(expected.content), "content DOM differs");
    } catch (error) {
      failures.push(`${names[index]}: ${error.message}`);
    }
  }

  if (failures.length > 0) {
    throw new Error(`Swift/Mozilla differential failures (${failures.length}):\n${failures.join("\n")}`);
  }
  process.stdout.write(`Swift and Mozilla match across ${names.length} fixtures and all observable fields.\n`);
}

compare();
