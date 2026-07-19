/* eslint-env node */

const assert = require("node:assert/strict");
const { JSDOM, VirtualConsole } = require("jsdom");
const prettyPrint = require("js-beautify").html;
const xmlNameValidator = require("xml-name-validator").name;

const quietVirtualConsole = new VirtualConsole();

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

function nodeDescription(node) {
  if (!node) {
    return "(no node)";
  }
  if (node.nodeType === node.TEXT_NODE) {
    return `#text(${htmlTransform(node.textContent)})`;
  }
  if (node.nodeType === node.COMMENT_NODE) {
    return `#comment(${node.data})`;
  }
  if (node.nodeType !== node.ELEMENT_NODE) {
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

function nextComparableNode(node) {
  do {
    node = inOrderTraverse(node);
  } while (node && node.nodeType === node.TEXT_NODE && !node.textContent.trim());
  return node;
}

function attributesForNode(node) {
  return Array.from(node.attributes)
    .filter(attribute => xmlNameValidator(attribute.name))
    .map(attribute => `${attribute.name}=${attribute.value}`);
}

/**
 * Compare the complete observable DOM used by the fixture gates.
 *
 * Formatting-only text nodes are ignored, as in Mozilla's fixture harness.
 * Comments are intentionally not ignored: their position and exact data are
 * part of raw-input Readability output and are covered by the direct oracle.
 */
function assertDOMEqual(actualHTML, expectedHTML, context = "DOM output") {
  const actualJSDOM = new JSDOM(prettyHTML(actualHTML), {
    virtualConsole: quietVirtualConsole,
  });
  const expectedJSDOM = new JSDOM(prettyHTML(expectedHTML), {
    virtualConsole: quietVirtualConsole,
  });
  const actualDOM = actualJSDOM.window.document;
  const expectedDOM = expectedJSDOM.window.document;

  try {
    let actualNode = actualDOM.documentElement || actualDOM.childNodes[0];
    let expectedNode = expectedDOM.documentElement || expectedDOM.childNodes[0];

    while (actualNode || expectedNode) {
      assert.ok(
        actualNode && expectedNode,
        `${context}: DOM trees have different lengths; actual=${nodeDescription(actualNode)} expected=${nodeDescription(expectedNode)}`
      );
      assert.equal(
        nodeDescription(actualNode),
        nodeDescription(expectedNode),
        `${context}: node mismatch`
      );

      if (actualNode.nodeType === actualNode.TEXT_NODE) {
        assert.equal(
          htmlTransform(actualNode.textContent),
          htmlTransform(expectedNode.textContent),
          `${context}: text mismatch`
        );
      } else if (actualNode.nodeType === actualNode.COMMENT_NODE) {
        assert.equal(
          actualNode.data,
          expectedNode.data,
          `${context}: comment mismatch`
        );
      } else if (actualNode.nodeType === actualNode.ELEMENT_NODE) {
        assert.deepEqual(
          attributesForNode(actualNode),
          attributesForNode(expectedNode),
          `${context}: attribute mismatch for ${nodeDescription(actualNode)}`
        );
      }

      actualNode = nextComparableNode(actualNode);
      expectedNode = nextComparableNode(expectedNode);
    }
  } finally {
    actualJSDOM.window.close();
    expectedJSDOM.window.close();
  }
}

module.exports = {
  assertDOMEqual,
  prettyHTML,
};
