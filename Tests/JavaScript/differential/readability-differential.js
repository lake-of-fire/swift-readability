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
const workerFlag = "--compare-batch";
const batchSize = 8;
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
  // `content` is a public Mozilla result field. Compare its exact browser
  // `innerHTML` serialization before the semantic DOM diagnostic below so
  // attribute order, entity spelling, and void syntax cannot be hidden.
  "content",
  "textContent",
  "length",
];

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

function javascriptResult(name) {
  // FixtureCorpus performs the same UTF-8 transport without trimming. The two
  // parsers must receive identical source text before their DOM work begins.
  const source = fs.readFileSync(path.join(fixtureRoot, name, "source.html"), "utf8");
  const dom = new JSDOM(source, {
    url: manifest.baseURL || "http://fakehost/test/page.html",
    virtualConsole: quietVirtualConsole,
  });
  try {
    const readerable = isProbablyReaderable(dom.window.document);
    const result = new Readability(dom.window.document).parse();
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
  } finally {
    // JSDOM windows retain a complete browsing context until explicitly closed.
    // Closing each fixture is essential because the upstream corpus contains
    // several megabyte-scale pages and the differential gate runs all of them.
    dom.window.close();
  }
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

function compareCanonicalDOM(actualHTML, expectedHTML) {
  assert.equal(actualHTML === null, expectedHTML === null, "only one content result is null");
  if (actualHTML === null) return;

  const actualDOM = new JSDOM(actualHTML, { virtualConsole: quietVirtualConsole });
  const expectedDOM = new JSDOM(expectedHTML, { virtualConsole: quietVirtualConsole });
  const booleanAttributes = new Set([
    "allowfullscreen", "async", "autofocus", "autoplay", "checked", "compact",
    "controls", "declare", "default", "defaultchecked", "defaultmuted",
    "defaultselected", "defer", "disabled", "enabled", "formnovalidate", "hidden",
    "indeterminate", "inert", "ismap", "itemscope", "loop", "multiple", "muted",
    "nohref", "nomodule", "noresize", "noshade", "novalidate", "nowrap", "open",
    "pauseonexit", "readonly", "required", "reversed", "scoped", "seamless",
    "selected", "sortable", "truespeed", "typemustmatch",
  ]);

  function* tokens(node) {
    if (node.nodeType === node.COMMENT_NODE) {
      yield ["comment", node.data];
      return;
    }
    if (node.nodeType === node.TEXT_NODE) {
      let text = node.textContent.replace(/\s+/g, " ");
      if (!text.trim()) return;
      if (!node.nextSibling) text = text.replace(/\s+$/, "");
      yield ["text", text];
      return;
    }
    if (node.nodeType === node.ELEMENT_NODE) {
      const attributes = [...node.attributes]
        .filter(attribute => xmlNameValidator(attribute.name))
        .map(attribute =>
          `${attribute.name}=${booleanAttributes.has(attribute.name.toLowerCase()) ? attribute.name : attribute.value}`
        )
        .sort();
      yield ["start", node.localName, attributes];
      for (const child of node.childNodes) yield* tokens(child);
      yield ["end", node.localName];
      return;
    }
    for (const child of node.childNodes || []) yield* tokens(child);
  }

  function* bodyTokens(document) {
    for (const child of document.body.childNodes) yield* tokens(child);
  }

  try {
    const actualTokens = bodyTokens(actualDOM.window.document);
    const expectedTokens = bodyTokens(expectedDOM.window.document);
    let tokenIndex = 0;
    while (true) {
      const actual = actualTokens.next();
      const expected = expectedTokens.next();
      assert.equal(actual.done, expected.done, `content DOM length differs at token ${tokenIndex}`);
      if (actual.done) return;
      assert.deepEqual(actual.value, expected.value, `content DOM differs at token ${tokenIndex}`);
      tokenIndex += 1;
    }
  } finally {
    actualDOM.window.close();
    expectedDOM.window.close();
  }
}

function compareFixture(name, actual) {
  // Keep the JSDOM-backed Mozilla result inside this function so references do
  // not escape the short-lived worker that owns this fixture batch.
  const expected = javascriptResult(name);
  for (const field of scalarFields) {
    assert.deepEqual(actual[field] ?? null, expected[field] ?? null, `${field} differs`);
  }
  compareCanonicalDOM(actual.content, expected.content);
}

function compareBatchWorker() {
  const payload = JSON.parse(fs.readFileSync(0, "utf8"));
  assert.ok(Array.isArray(payload.names), "Worker fixture names are missing");
  assert.ok(Array.isArray(payload.actual), "Worker native results are missing");
  assert.equal(payload.actual.length, payload.names.length, "Worker batch lengths differ");

  const failures = [];
  for (let index = 0; index < payload.names.length; index += 1) {
    try {
      compareFixture(payload.names[index], payload.actual[index]);
    } catch (error) {
      failures.push(`${payload.names[index]}: ${error.message}`);
    }
  }
  process.stdout.write(JSON.stringify(failures));
}

function compareBatch(names, actual) {
  // JSDOM VM realms are not always reclaimed promptly even after window.close().
  // A short-lived worker process gives every batch a hard memory lifetime while
  // retaining exact field and DOM comparisons against the Mozilla oracle.
  const command = spawnSync(
    process.execPath,
    ["--max-old-space-size=512", __filename, workerFlag],
    {
      cwd: repositoryRoot,
      encoding: "utf8",
      input: JSON.stringify({ names, actual }),
      maxBuffer: 128 * 1024 * 1024,
    }
  );
  if (command.error) {
    throw new Error(`Could not start Mozilla comparison worker: ${command.error.message}`);
  }
  if (command.status !== 0) {
    throw new Error(
      `Mozilla comparison worker failed for ${names.join(", ")} ` +
      `(status ${command.status}, signal ${command.signal ?? "none"}):\n${command.stderr}`
    );
  }
  return JSON.parse(command.stdout);
}

function compare() {
  const names = fixtureNames();
  const swift = swiftResults();
  assert.deepEqual(swift.map(result => result.name), names, "Native fixture order differs");

  const failures = [];

  for (let start = 0; start < names.length; start += batchSize) {
    const batchNames = names.slice(start, start + batchSize);
    if (process.env.SWIFT_READABILITY_DIFFERENTIAL_PROGRESS) {
      process.stderr.write(
        `[${start + 1}-${start + batchNames.length}/${names.length}] ${batchNames.join(", ")}\n`
      );
    }
    failures.push(...compareBatch(batchNames, swift.slice(start, start + batchSize)));
  }

  if (failures.length > 0) {
    throw new Error(`Swift/Mozilla differential failures (${failures.length}):\n${failures.join("\n")}`);
  }
  process.stdout.write(`Swift and Mozilla match across ${names.length} fixtures and all observable fields.\n`);
}

if (process.argv.includes(workerFlag)) {
  compareBatchWorker();
} else {
  compare();
}
